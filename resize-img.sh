#!/bin/bash
set -e

TARGET_SIZE_MB=28672  # 28GB to fit on all "32GB" SD cards
SECTOR_SIZE=512
PADDING_MB=4
IMAGE=""
COMPRESSED_NAME=""

echo "==== 🔍 SD Image Shrinker + Selector ===="

# === Step 1: Find .img files ===
mapfile -t IMAGES < <(find . -maxdepth 1 -type f -name "*.img" | sort)

if [ ${#IMAGES[@]} -eq 0 ]; then
  echo "❌ No .img files found in the current directory."
  exit 1
fi

echo ""
echo "📂 Found the following .img files:"
for i in "${!IMAGES[@]}"; do
  printf "  [%d] %s\n" "$((i+1))" "${IMAGES[$i]}"
done

echo ""
read -p "👉 Enter the number of the image you want to shrink: " SELECTION

if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "${#IMAGES[@]}" ]; then
  echo "❌ Invalid selection."
  exit 1
fi

IMAGE="${IMAGES[$((SELECTION-1))]}"
COMPRESSED_NAME="$IMAGE.xz"
echo "✅ Selected: $IMAGE"
echo ""

# === Step 2: Attach image to loop device ===
echo "📌 Attaching image to loop device..."
LOOP_DEV=$(sudo losetup --show -Pf "$IMAGE")

# === Step 3: Detect largest partition ===
PARTS=$(lsblk -nrpo NAME "$LOOP_DEV" | grep -E "$LOOP_DEV"p)
ROOT_PART=$(for P in $PARTS; do lsblk -bno SIZE "$P" | awk -v p="$P" '{print $1, p}'; done | sort -nr | head -n1 | awk '{print $2}')

if [ -z "$ROOT_PART" ]; then
  echo "❌ Error: Couldn't detect root partition."
  sudo losetup -d "$LOOP_DEV"
  exit 1
fi
PART_NUM=$(basename "$ROOT_PART" | grep -o '[0-9]*$')
echo "🔍 Detected rootfs: $ROOT_PART (Partition #$PART_NUM)"

# === Step 4: Unmount if mounted ===
sudo umount "$ROOT_PART" 2>/dev/null || true

# === Step 5: Shrink filesystem ===
echo "🔧 Running fsck and shrinking rootfs to ${TARGET_SIZE_MB}MB..."
sudo e2fsck -fy "$ROOT_PART"
sudo resize2fs "$ROOT_PART" "${TARGET_SIZE_MB}M"

# === Step 6: Resize partition in image ===
START_SECTOR=$(sudo parted -s "$IMAGE" unit s print | grep "^ $PART_NUM" | awk '{print $2}' | sed 's/s//')
TARGET_SECTORS=$((TARGET_SIZE_MB * 1024 * 1024 / SECTOR_SIZE))
END_SECTOR=$((START_SECTOR + TARGET_SECTORS - 1))

echo "📏 Updating partition table..."
sudo sgdisk --delete=$PART_NUM "$IMAGE"
sudo sgdisk --new=$PART_NUM:$START_SECTOR:$END_SECTOR "$IMAGE"

# === Step 7: Detach + reattach loop device to refresh layout ===
sudo losetup -d "$LOOP_DEV"
LOOP_DEV=$(sudo losetup --show -Pf "$IMAGE")

# === Step 8: Truncate image ===
TRUNC_SIZE=$(( (END_SECTOR + (PADDING_MB * 1024 * 1024 / SECTOR_SIZE)) * SECTOR_SIZE ))
echo "✂️ Truncating image to $((TRUNC_SIZE / 1024 / 1024))MB..."
truncate -s $TRUNC_SIZE "$IMAGE"

# === Step 9: Cleanup + compress ===
sudo losetup -d "$LOOP_DEV"
echo "📦 Compressing with xz -9 -T0..."
xz -T0 -9 "$IMAGE"

echo ""
echo "✅ All done! Compressed output: $COMPRESSED_NAME"

