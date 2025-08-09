#!/bin/bash
set -e

REQUIRED_TOOLS=(losetup lsblk parted sgdisk e2fsck resize2fs dumpe2fs du truncate xz 7z)

echo "==== 🔍 Smart SD Image Shrinker ===="

# --- Cleanup handler (set early so it works on error/CTRL+C) ---
cleanup() {
  [[ -n "$MNT_DIR" && -d "$MNT_DIR" ]] && sudo umount "$MNT_DIR" 2>/dev/null || true
  [[ -n "$LOOP_DEV" ]] && sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
}
trap cleanup EXIT

# --- Check dependencies ---
MISSING_TOOLS=()
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    echo "⚠️ Missing required tools: ${MISSING_TOOLS[*]}"
    echo "📦 Attempting to install..."
    if command -v apt &>/dev/null; then
        sudo apt update
        sudo apt install -y util-linux parted gdisk e2fsprogs xz-utils p7zip-full
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y util-linux parted gdisk e2fsprogs xz p7zip
    elif command -v yum &>/dev/null; then
        sudo yum install -y util-linux parted gdisk e2fsprogs xz p7zip
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --needed util-linux parted gptfdisk e2fsprogs xz p7zip coreutils
    else
        echo "❌ Unsupported package manager. Please install manually."
        exit 1
    fi
    echo "✅ Dependencies installed."
fi

SECTOR_SIZE=512
PADDING_MB=4

# --- Find images ---
mapfile -t IMAGES < <(find . -maxdepth 1 -type f -name "*.img" | sort)
if [ ${#IMAGES[@]} -eq 0 ]; then
    echo "❌ No .img files found."
    exit 1
fi

echo "📂 Found:"
for i in "${!IMAGES[@]}"; do
    printf "  [%d] %s\n" "$((i+1))" "${IMAGES[$i]}"
done

read -p "👉 Enter the number of the image: " SELECTION
if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "${#IMAGES[@]}" ]; then
    echo "❌ Invalid selection."
    exit 1
fi

IMAGE="${IMAGES[$((SELECTION-1))]}"
echo "✅ Selected: $IMAGE"

# --- Attach image ---
echo "📌 Attaching..."
# Detach any existing loop devices linked to this image
EXISTING_LOOP=$(losetup -j "$IMAGE" | awk -F: '{print $1}')
if [ -n "$EXISTING_LOOP" ]; then
    echo "⚠️ Image already attached at $EXISTING_LOOP, detaching..."
    sudo losetup -d "$EXISTING_LOOP"
fi

# Try attaching with partitions
if ! LOOP_DEV=$(sudo losetup --find --show -Pf "$IMAGE" 2>/dev/null); then
    echo "❌ Failed to attach loop device. Trying without -P..."
    if ! LOOP_DEV=$(sudo losetup --find --show "$IMAGE" 2>/dev/null); then
        echo "❌ Could not attach image at all. Check that the file exists and is not in use."
        exit 1
    else
        echo "ℹ️ Attached without partition scan. Will manually rescan..."
        sudo partprobe "$LOOP_DEV"
    fi
fi

echo "✅ Attached at: $LOOP_DEV"


# --- Find largest partition ---
PARTS=$(lsblk -nrpo NAME "$LOOP_DEV" | grep -E "$LOOP_DEV"p)
ROOT_PART=$(for P in $PARTS; do lsblk -bno SIZE "$P" | awk -v p="$P" '{print $1, p}'; done | sort -nr | head -n1 | awk '{print $2}')
if [ -z "$ROOT_PART" ]; then
    echo "❌ Could not detect root partition."
    exit 1
fi
PART_NUM=$(basename "$ROOT_PART" | grep -o '[0-9]*$')
echo "🔍 Rootfs: $ROOT_PART (Partition #$PART_NUM)"

# --- Unmount if mounted ---
sudo umount "$ROOT_PART" 2>/dev/null || true

# --- Measure usage ---
MNT_DIR=$(mktemp -d)
sudo mount "$ROOT_PART" "$MNT_DIR"
USED_MB=$(sudo du -sx --block-size=1M "$MNT_DIR" | awk '{print $1}')
sudo umount "$MNT_DIR" && rmdir "$MNT_DIR"

MIN_SAFE_MB=$((USED_MB + 500))
echo "📊 Used: ${USED_MB}MB"
echo "💡 Minimum safe size: ${MIN_SAFE_MB}MB"

# --- Size selection ---
SD_OPTIONS=("8GB" "16GB" "32GB" "64GB" "Custom")
SD_MB_VALUES=(8192 16384 32768 65536)

DEFAULT_CHOICE=""
for i in "${!SD_MB_VALUES[@]}"; do
    if (( SD_MB_VALUES[i] >= MIN_SAFE_MB )) && [ -z "$DEFAULT_CHOICE" ]; then
        DEFAULT_CHOICE=$((i+1))
    fi
done
echo "💡 Recommended: [$DEFAULT_CHOICE] ${SD_OPTIONS[$((DEFAULT_CHOICE-1))]}"

read -p "👉 Choice (default $DEFAULT_CHOICE): " SD_CHOICE
SD_CHOICE=${SD_CHOICE:-$DEFAULT_CHOICE}

if [[ "$SD_CHOICE" == "5" ]]; then
    read -p "Enter custom size in MB: " TARGET_SIZE_MB
else
    TARGET_SIZE_MB=${SD_MB_VALUES[$((SD_CHOICE-1))]}
fi
echo "✅ Target shrink size: ${TARGET_SIZE_MB}MB"

# --- Confirm ---
read -p "⚠️ Proceed with shrinking? (y/N): " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || exit 0

# --- Shrink FS ---
CUR_BLOCKS=$(sudo dumpe2fs "$ROOT_PART" 2>/dev/null | grep '^Block count:' | awk '{print $3}')
BLOCK_SIZE=$(sudo dumpe2fs "$ROOT_PART" 2>/dev/null | grep '^Block size:' | awk '{print $3}')
CUR_MB=$((CUR_BLOCKS * BLOCK_SIZE / 1024 / 1024))

if [ "$CUR_MB" -gt "$TARGET_SIZE_MB" ]; then
    sudo e2fsck -fy "$ROOT_PART"
    sudo resize2fs "$ROOT_PART" "${TARGET_SIZE_MB}M"
else
    echo "ℹ️ Already <= target size."
fi

# --- Partition update ---
PART_TYPE=$(sudo parted -s "$IMAGE" print | grep "^Partition Table:" | awk '{print $3}')
START_SECTOR=$(sudo parted -s "$IMAGE" unit s print | grep "^ $PART_NUM" | awk '{print $2}' | sed 's/s//')
TARGET_SECTORS=$((TARGET_SIZE_MB * 1024 * 1024 / SECTOR_SIZE))
END_SECTOR=$((START_SECTOR + TARGET_SECTORS - 1))

echo "📏 Updating partition table..."
if [[ "$PART_TYPE" == "gpt" ]]; then
    sudo sgdisk --delete=$PART_NUM "$IMAGE"
    sudo sgdisk --new=$PART_NUM:$START_SECTOR:$END_SECTOR "$IMAGE"
    sudo sgdisk -e "$IMAGE"
else
    sudo parted -s "$IMAGE" rm $PART_NUM
    sudo parted -s "$IMAGE" mkpart primary ext4 ${START_SECTOR}s ${END_SECTOR}s
fi

# --- Detach/reattach & truncate ---
sudo losetup -d "$LOOP_DEV"
TRUNC_SIZE=$(( (END_SECTOR + (PADDING_MB * 1024 * 1024 / SECTOR_SIZE)) * SECTOR_SIZE ))
echo "✂️ Truncating to $((TRUNC_SIZE / 1024 / 1024))MB..."
truncate -s $TRUNC_SIZE "$IMAGE"

# --- Compression ---
echo ""
echo "📦 Compression:"
echo "  [1] xz (max, multi-thread)"
echo "  [2] 7z (ultra)"
echo "  [3] None"
read -p "👉 Choose: " COMP_METHOD
case "$COMP_METHOD" in
    1) echo "⚙️ Compressing with xz..."; xz -T0 -9 "$IMAGE"; COMPRESSED_NAME="$IMAGE.xz" ;;
    2) echo "⚙️ Compressing with 7z..."; 7z a -t7z -mx=9 "${IMAGE}.7z" "$IMAGE"; COMPRESSED_NAME="$IMAGE.7z" ;;
    *) echo "⚠️ Skipping compression."; COMPRESSED_NAME="$IMAGE" ;;
esac

echo ""
echo "✅ Done! Output: $COMPRESSED_NAME"
