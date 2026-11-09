#!/bin/bash
# Run as the desktop/Core user; sudo is used only for system packages.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="https://gitea.qortal.link/crowetic/QORTector-scripts/raw/branch/main"
WARNINGS=()
BACKUP_DIR=""

warn() {
  printf 'Warning: %s\n' "$*" >&2
  WARNINGS+=("$*")
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Flags are initialized here too so individual functions remain safe to source.
DRY_RUN=${REBUILT_MACHINE_DRY_RUN:-0}
UPDATE_CORE=${REBUILT_MACHINE_UPDATE_CORE:-0}
UPDATE_HUB=${REBUILT_MACHINE_UPDATE_HUB:-0}
UPGRADE_PACKAGES=${REBUILT_MACHINE_UPGRADE:-0}
APPLY_DEFAULTS=${REBUILT_MACHINE_APPLY_DEFAULTS:-0}
APPLY_BRANDING=0
FORCE_ARTWORK=${REBUILT_MACHINE_FORCE_ARTWORK:-0}
PKG_MANAGER=""
PACMAN_DATABASE_SYNCED=0
PACMAN_CONFLICT_RECOVERY_DONE=0
HUB_SANDBOX_FLAG=""

usage() {
  cat <<'HELP'
Usage: bash rebuilt-machine.sh [options]
Run as the desktop/Core user; sudo is requested for system packages.
  --help                Show this help
  --dry-run             Preview without sudo, downloads, writes or child scripts
  --update-core         Update an existing stopped Core jar; preserve data/settings
  --update-hub          Check the latest release and update Hub when needed
  --upgrade-packages    Opt in to a full system package upgrade
  --apply-defaults      Back up dconf, then apply repository desktop preferences
  --force-artwork       Replace repository artwork/themes/icons (with backups)
Equivalent REBUILT_MACHINE_* variables (0 or 1): DRY_RUN, UPDATE_CORE,
UPDATE_HUB, UPGRADE, APPLY_DEFAULTS, FORCE_ARTWORK. Defaults are all 0.
REBUILT_MACHINE_REBOOT=1 explicitly enables reboot after a 30-second delay.
REBUILT_MACHINE_HEADLESS=auto|1|0 selects automatic/server/desktop mode.
REBUILT_MACHINE_PKG_RETRIES=3 sets package install attempts (positive integer).
Failed noncritical packages warn and continue; required packages stop setup.
Pacman refreshes its database once; file/dependency conflicts may trigger one full upgrade.
A successful recovery gives the package a fresh install attempt budget.
Existing Core/Hub, preferences, custom cron and autostarts are preserved by default.
Fresh desktop installs receive Qortal branding; SSH setup defers it to Cinnamon login.
HELP
}

parse_args() {
  local option value
  for option in "$@"; do
    case "$option" in
      --help|-h) usage; return 10 ;;
      --dry-run) DRY_RUN=1 ;;
      --update-core) UPDATE_CORE=1 ;;
      --update-hub) UPDATE_HUB=1 ;;
      --upgrade-packages) UPGRADE_PACKAGES=1 ;;
      --apply-defaults) APPLY_DEFAULTS=1 ;;
      --force-artwork) FORCE_ARTWORK=1 ;;
      *) printf 'Unknown option: %s\n' "$option" >&2; return 1 ;;
    esac
  done
  for option in DRY_RUN UPDATE_CORE UPDATE_HUB UPGRADE_PACKAGES APPLY_DEFAULTS FORCE_ARTWORK; do
    value=${!option}
    case "$value" in 0|1) ;; *) printf '%s must be 0 or 1.\n' "$option" >&2; return 1 ;; esac
  done
  case "${REBUILT_MACHINE_REBOOT:-0}" in 0|1) ;; *) echo 'REBUILT_MACHINE_REBOOT must be 0 or 1.' >&2; return 1 ;; esac
  case "${REBUILT_MACHINE_HEADLESS:-auto}" in auto|0|1) ;; *) echo 'REBUILT_MACHINE_HEADLESS must be auto, 0 or 1.' >&2; return 1 ;; esac
  validate_pkg_retries
}

run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '[dry-run]'; printf ' %q' "$@"; printf '\n'
  else
    "$@"
  fi
}

# os-release may be overridden to exercise detection without touching the host.
detect_distro() {
  local ID=unknown ID_LIKE="" os_release=${REBUILT_MACHINE_OS_RELEASE:-/etc/os-release} preferred="" manager
  [ ! -r "$os_release" ] || . "$os_release"
  DISTRO_ID=${ID,,}
  case " $DISTRO_ID ${ID_LIKE,,} " in
    *' debian '*|*' ubuntu '*|*' linuxmint '*) preferred=apt-get ;;
    *' arch '*|*' manjaro '*) preferred=pacman ;;
    *' fedora '*|*' rhel '*|*' centos '*) preferred=dnf ;;
    *) warn "Unknown distribution $DISTRO_ID; trying an available supported package manager." ;;
  esac
  if [ -n "$preferred" ] && command_exists "$preferred"; then
    PKG_MANAGER=$preferred
  else
    for manager in apt-get pacman dnf; do
      if command_exists "$manager"; then PKG_MANAGER=$manager; break; fi
    done
  fi
  [ -n "$PKG_MANAGER" ] || { echo 'No supported package manager found (apt-get, pacman, dnf).' >&2; return 1; }
  printf 'Distribution: %s; package manager: %s\n' "$DISTRO_ID" "$PKG_MANAGER"
}

map_package() {
  local name=$1
  case "$PKG_MANAGER:$name" in
    pacman:python3) name=python ;;
    pacman:openssh-server) name=openssh ;;
    pacman:zlib1g-dev) name=zlib ;;
    pacman:cron) name=cronie ;;
    pacman:fonts-symbola) name=ttf-symbola ;;
    pacman:lm-sensors) name=lm_sensors ;;
    pacman:chromium-browser) name=chromium ;;
    pacman:dconf-cli) name=dconf ;;
    pacman:libglib2.0-bin) name=glib2 ;;
    pacman:openjdk-21-jre*) name=jre21-openjdk ;;
    pacman:openjdk-17-jre*) name=jre17-openjdk ;;
    pacman:libfuse2*) name=fuse2 ;;
    pacman:cinnamon-desktop-environment) name=cinnamon ;;
    pacman:p7zip-full) name=p7zip ;;
    dnf:imagemagick) name=ImageMagick ;;
    dnf:cron) name=cronie ;;
    dnf:zlib1g-dev) name=zlib-devel ;;
    dnf:fonts-symbola) name=gdouros-symbola-fonts ;;
    dnf:lm-sensors) name=lm_sensors ;;
    dnf:chromium-browser) name=chromium ;;
    dnf:dconf-cli) name=dconf ;;
    dnf:libglib2.0-bin) name=glib2 ;;
    dnf:openjdk-21-jre*) name=java-21-openjdk ;;
    dnf:openjdk-17-jre*) name=java-17-openjdk ;;
    dnf:libfuse2*) name=fuse-libs ;;
    dnf:cinnamon-desktop-environment) name=cinnamon ;;
    dnf:p7zip-full) name=p7zip ;;
    pacman:yaru-theme-*|dnf:yaru-theme-*) return 1 ;;
  esac
  printf '%s\n' "$name"
}

package_installed() {
  case "${PKG_MANAGER:-apt-get}" in
    apt-get) [ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" = 'install ok installed' ] ;;
    pacman) pacman -Q "$1" >/dev/null 2>&1 ;;
    dnf) rpm -q "$1" >/dev/null 2>&1 ;;
  esac
}

validate_pkg_retries() {
  local attempts=${REBUILT_MACHINE_PKG_RETRIES:-3}
  [[ "$attempts" =~ ^[1-9][0-9]*$ ]] && [ "$attempts" -gt 0 ] 2>/dev/null || {
    echo 'REBUILT_MACHINE_PKG_RETRIES must be a positive integer (total attempts).' >&2
    return 1
  }
}

sync_pacman_database() {
  if [ "$PACMAN_DATABASE_SYNCED" = 0 ]; then
    run sudo pacman -Sy --noconfirm || return $?
    PACMAN_DATABASE_SYNCED=1
  fi
}

pkg_install() {
  local package mapped attempt status option configured manual_command install_output required=0
  local attempts=${REBUILT_MACHINE_PKG_RETRIES:-3}
  local -a apt_options=() install_command=()
  validate_pkg_retries || return 1
  # Alternative-package callers need failure status so they can try the next
  # candidate, even when a normal install would only warn and continue.
  if [ "${1:-}" = --required ]; then required=1; shift; fi
  if [ "${PKG_MANAGER:-apt-get}" = pacman ]; then
    sync_pacman_database || return $?
  fi
  if [ "${PKG_MANAGER:-apt-get}" = apt-get ]; then
    for option in APT::Get::Retry Acquire::Retries; do
      configured=""
      if [ "$DRY_RUN" = 0 ] && command_exists apt-config; then
        configured=$(apt-config shell retry_value "$option" 2>/dev/null) || configured=""
      fi
      # Preserve explicit local settings, including zero. Acquire::Retries is
      # the effective APT download retry option; no persistent config is written.
      [ -n "$configured" ] || apt_options+=(-o "$option=$attempts")
    done
  fi
  for package in "$@"; do
    mapped=$(map_package "$package") || { warn "No $PKG_MANAGER equivalent for $package; skipping."; continue; }
    if [ "$DRY_RUN" = 0 ] && package_installed "$mapped"; then
      # Let pacman compare gcc-libs with the refreshed database before Java.
      if [ "$PKG_MANAGER" != pacman ] || [ "$mapped" != gcc-libs ]; then
        printf 'Package already installed: %s\n' "$mapped"
        continue
      fi
    fi
    case "${PKG_MANAGER:-apt-get}" in
      apt-get) install_command=(sudo apt-get install -y --no-upgrade "${apt_options[@]}" "$mapped") ;;
      # Pacman has no --retry option; retry the transaction in this loop.
      pacman) install_command=(sudo pacman -S --noconfirm --needed "$mapped") ;;
      dnf) install_command=(sudo dnf install -y "--setopt=retries=$attempts" "$mapped") ;;
      *) echo "Unsupported package manager: $PKG_MANAGER" >&2; return 1 ;;
    esac
    for ((attempt=1; attempt<=attempts; attempt++)); do
      install_output=""
      if [ "${PKG_MANAGER:-apt-get}" = pacman ] && [ "$DRY_RUN" = 0 ]; then
        # Keep pacman's English diagnostics for conflict detection. Capture both
        # streams without losing its exit status, then show the output to users.
        if install_output=$(LC_ALL=C run "${install_command[@]}" 2>&1); then
          status=0
        else
          status=$?
        fi
        [ -z "$install_output" ] || printf '%s\n' "$install_output" >&2
      elif run "${install_command[@]}"; then
        status=0
      else
        status=$?
      fi
      [ "$status" -ne 0 ] || break
      # Recover before checking the retry budget, including on the last attempt.
      # Upgrade all packages together to resolve exact-version dependencies.
      if [ "${PKG_MANAGER:-apt-get}" = pacman ] && [ "$PACMAN_CONFLICT_RECOVERY_DONE" = 0 ] &&
        [[ "$install_output" == *'conflicting files'* || "$install_output" == *'exists in filesystem'* ||
           "$install_output" == *'could not satisfy dependencies'* || "$install_output" == *'breaks dependency'* ||
           "$install_output" == *'failed to prepare transaction'* ]]; then
        PACMAN_CONFLICT_RECOVERY_DONE=1
        echo 'System packages are out of sync. Running full system upgrade to resolve dependencies...' >&2
        if run sudo pacman -Syu --noconfirm; then
          # The loop increments to 1; recovery consumes no package attempts.
          attempt=0
          continue
        else
          status=$?
          warn 'Pacman full system upgrade failed. Run manually: sudo pacman -Syu'
          echo 'Then re-run this script.' >&2
          return "$status"
        fi
      fi
      if [ "$attempt" -lt "$attempts" ]; then
        printf 'Package %s install failed (attempt %s/%s); retrying in %ss.\n' \
          "$mapped" "$attempt" "$attempts" "$((attempt * 2))" >&2
        sleep "$((attempt * 2))"
      fi
    done
    if [ "$status" -ne 0 ]; then
      printf -v manual_command '%q ' "${install_command[@]}"
      warn "Could not install package $mapped after $attempts attempts (exit $status). Retry manually: ${manual_command% }"
      # These tools are needed by later setup steps; fail here with the package
      # name rather than failing later on a missing command or TLS certificates.
      case "$package" in
        git|curl|jq|unzip|ca-certificates|rsync|python3|util-linux)
          printf 'Critical package %s is unavailable; stopping setup.\n' "$mapped" >&2
          return "$status"
          ;;
      esac
      [ "$required" = 0 ] || return "$status"
    fi
  done
  return 0
}

prepare_packages() {
  case "$PKG_MANAGER" in
    apt-get)
      run sudo apt-get -o APT::Update::Error-Mode=any update
      [ "$UPGRADE_PACKAGES" = 0 ] || run sudo apt-get -y upgrade
      ;;
    pacman)
      sync_pacman_database || return $?
      [ "$UPGRADE_PACKAGES" = 0 ] || run sudo pacman -Syu --noconfirm
      ;;
    dnf) [ "$UPGRADE_PACKAGES" = 0 ] || run sudo dnf upgrade -y ;;
  esac
  if [ "$UPGRADE_PACKAGES" = 0 ]; then
    echo 'System package upgrades skipped (opt in with --upgrade-packages).'
    if [ "$PKG_MANAGER" = pacman ]; then
      echo 'Pacman file or dependency conflicts may trigger one recovery system upgrade during installation.'
    fi
  fi
}

validate_download() {
  local file="$1" name="$2" first_line
  [ -s "$file" ] || return 1
  case "$name" in
    *.sh)
      IFS= read -r first_line < "$file" || return 1
      [[ "$first_line" == '#!'* ]] && bash -n "$file"
      ;;
    *.json) jq -e 'type == "object"' "$file" >/dev/null ;;
    *.zip) unzip -tq "$file" >/dev/null 2>&1 ;;
  esac
}

download_with_retry() {
  local url="$1" output="$2" attempts="${3:-5}" tmp try
  if [ "$DRY_RUN" = 1 ]; then printf '[dry-run] Download %s to %s\n' "$url" "$output"; return 0; fi
  tmp=$(mktemp "${output}.part.XXXXXX") || return 1
  for ((try=1; try<=attempts; try++)); do
    printf 'Downloading %s (attempt %s/%s)\n' "$url" "$try" "$attempts"
    # Restart short script/archive downloads: resuming can append an error page
    # or mix two revisions. Keep the installed file until a valid replacement exists.
    if command_exists curl && curl --fail --location --show-error \
        --connect-timeout 15 --max-time 180 --output "$tmp" "$url" && \
        validate_download "$tmp" "$output"; then
      mv -f "$tmp" "$output"
      return 0
    fi
    if command_exists wget && wget --tries=1 --timeout=30 -O "$tmp" "$url" && \
        validate_download "$tmp" "$output"; then
      mv -f "$tmp" "$output"
      return 0
    fi
    [ "$try" -eq "$attempts" ] || sleep "$((try * 2))"
  done
  rm -f "$tmp"
  printf 'Could not download a valid file: %s\n' "$url" >&2
  return 1
}

backup_file() {
  local target="$1" relative
  [ -f "$target" ] || return 0
  [ -n "$BACKUP_DIR" ] || return 0
  relative="${target#"$HOME"/}"
  mkdir -p "$BACKUP_DIR/$(dirname "$relative")"
  # Keep the pre-run copy if this file is updated more than once.
  [ -e "$BACKUP_DIR/$relative" ] || cp -p "$target" "$BACKUP_DIR/$relative"
}

write_managed_file() {
  local target="$1" mode="${2:-644}" tmp
  if [ "$DRY_RUN" = 1 ]; then cat >/dev/null; printf '[dry-run] Write %s\n' "$target"; return 0; fi
  mkdir -p "$(dirname "$target")"
  tmp=$(mktemp "${target}.new.XXXXXX") || return 1
  cat > "$tmp"
  if ! cmp -s "$tmp" "$target"; then
    backup_file "$target"
    chmod "$mode" "$tmp"
    mv -f "$tmp" "$target"
  else
    rm -f "$tmp"
    chmod "$mode" "$target"
  fi
}

install_repo_file() {
  local name="$1" target="$2" mode="${3:-755}" replace="${4:-0}" source_file="$SCRIPT_DIR/$1" tmp
  if { [ -e "$target" ] || [ -L "$target" ]; } && [ "$replace" = 0 ]; then
    printf 'Keeping existing helper: %s\n' "$target"
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then printf '[dry-run] Install helper %s\n' "$target"; return 0; fi
  mkdir -p "$(dirname "$target")"
  if [ -f "$source_file" ]; then
    validate_download "$source_file" "$name" || return 1
    write_managed_file "$target" "$mode" < "$source_file"
  else
    tmp=$(mktemp "${target}.download.XXXXXX") || return 1
    if ! download_with_retry "$REPO_URL/$name" "$tmp.$name"; then
      rm -f "$tmp" "$tmp.$name"
      return 1
    fi
    write_managed_file "$target" "$mode" < "$tmp.$name"
    rm -f "$tmp" "$tmp.$name"
  fi
}

is_headless_mode() {
  case "${REBUILT_MACHINE_HEADLESS:-auto}" in
    1) return 0 ;;
    0) return 1 ;;
    auto) ;;
    *) printf 'REBUILT_MACHINE_HEADLESS must be auto, 0 or 1.\n' >&2; return 2 ;;
  esac
  if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}${XDG_CURRENT_DESKTOP:-}" ]; then
    return 1
  fi
  # An empty sessions directory alone does not make a server a desktop.
  compgen -G '/usr/share/xsessions/*.desktop' >/dev/null && return 1
  compgen -G '/usr/share/wayland-sessions/*.desktop' >/dev/null && return 1
  return 0
}

is_fresh_desktop() {
  local config="${XDG_CONFIG_HOME:-$HOME/.config}"
  # Absence of setup history alone must never reset an existing user's desktop.
  [ ! -e "$HOME/.qortector-setup-state.json" ] &&
    [ ! -s "$config/dconf/user" ] && [ ! -e "$HOME/.dmrc" ] &&
    [ ! -d "$config/cinnamon/spices/menu@cinnamon.org" ] &&
    [ ! -d "$HOME/.cinnamon/configs/menu@cinnamon.org" ] &&
    [ ! -d "${XDG_DATA_HOME:-$HOME/.local/share}/cinnamon/applets/menu@cinnamon.org" ]
}

desktop_session_available() {
  [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]
}

package_available() {
  case "${PKG_MANAGER:-apt-get}" in
    apt-get)
      local candidate
      candidate=$(LC_ALL=C apt-cache policy "$1" | awk '/Candidate:/ {print $2; exit}') || return 1
      [ -n "$candidate" ] && [ "$candidate" != '(none)' ]
      ;;
    pacman) pacman -Si "$1" >/dev/null 2>&1 ;;
    dnf) dnf -q list --available "$1" >/dev/null 2>&1 ;;
  esac
}

install_packages_if_available() {
  local package mapped
  for package in "$@"; do
    mapped=$(map_package "$package") || { warn "No $PKG_MANAGER equivalent for $package; skipping."; continue; }
    if package_installed "$mapped" || package_available "$mapped"; then
      pkg_install "$package" || warn "Could not install optional package: $mapped"
    else
      warn "Optional package is unavailable: $mapped"
    fi
  done
}

install_first_available_package() {
  local package mapped
  # Keep any installed alternative rather than installing a preferred replacement.
  for package in "$@"; do
    mapped=$(map_package "$package") || continue
    if package_installed "$mapped"; then return 0; fi
  done
  for package in "$@"; do
    mapped=$(map_package "$package") || continue
    if package_available "$mapped" && pkg_install --required "$package"; then return 0; fi
  done
  return 1
}

install_java_runtime() {
  local package mapped
  # Keep an already installed supported runtime, including the former Java 21
  # default. Fresh installs request only Java 17, never a second major version.
  for package in openjdk-17-jre openjdk-17-jre-headless openjdk-21-jre openjdk-21-jre-headless; do
    mapped=$(map_package "$package") || continue
    if package_installed "$mapped"; then return 0; fi
  done
  if [ "$PKG_MANAGER" = pacman ]; then
    pkg_install --required gcc-libs || return $?
  fi
  install_first_available_package openjdk-17-jre openjdk-17-jre-headless
}

ensure_qortal_setup_script() {
  QORTAL_SETUP_SCRIPT="$HOME/Qortal-Setup-Linux.sh"
  install_repo_file Qortal-Setup-Linux.sh "$QORTAL_SETUP_SCRIPT"
}

install_qortal_icons() {
  if [ "$DRY_RUN" = 1 ]; then echo '[dry-run] Install missing Qortal icons'; return 0; fi
  install_repo_file create-icon-theme-uni.sh "$HOME/create-icon-theme-uni.sh" 755 "$APPLY_DEFAULTS" || return 1
  if ! command_exists magick && ! command_exists convert; then
    warn 'ImageMagick is unavailable; skipping Qortal icon generation. Install ImageMagick, then retry manually: bash ~/create-icon-theme-uni.sh'
    return 0
  fi
  # A preserved home copy may predate the safety switches; execute this
  # checkout's helper, or fetch a current temporary copy for standalone use.
  local helper="$SCRIPT_DIR/create-icon-theme-uni.sh" work="" status=0
  if [ ! -f "$helper" ]; then
    work=$(mktemp -d) || return 1
    helper="$work/create-icon-theme-uni.sh"
    download_with_retry "$REPO_URL/create-icon-theme-uni.sh" "$helper" || { rm -rf "$work"; return 1; }
  fi
  # Preference writes belong to the session-aware branding helper below.
  QORTAL_ICONS_PRESERVE_EXISTING="$((1 - FORCE_ARTWORK))" \
    QORTAL_ICONS_SELECT_THEME=0 bash "$helper" || status=$?
  [ -z "$work" ] || rm -rf "$work"
  return "$status"
}

install_machine_artwork() {
  local work marker="$HOME/Pictures/.qortector-artwork-installed"
  if [ "$FORCE_ARTWORK" = 0 ] && [ -f "$marker" ]; then echo 'Artwork already installed; keeping it.'; return 0; fi
  if [ "$DRY_RUN" = 1 ]; then echo '[dry-run] Install missing artwork'; return 0; fi
  work=$(mktemp -d) || return 1
  if download_with_retry 'https://cloud.qortal.org/s/machinefilesnew/download' "$work/machine.zip" && \
      unzip -oq "$work/machine.zip" -d "$work" && [ -d "$work/Machine-files/Pictures" ]; then
    mkdir -p "$HOME/Pictures"
    # The bundle supplies artwork, not executable scripts or user configuration.
    if [ "$FORCE_ARTWORK" = 1 ]; then
      [ ! -d "$HOME/Pictures" ] || [ -e "$BACKUP_DIR/Pictures" ] || cp -a "$HOME/Pictures" "$BACKUP_DIR/Pictures"
      rsync -a "$work/Machine-files/Pictures/" "$HOME/Pictures/" || { rm -rf "$work"; return 1; }
    else
      rsync -a --ignore-existing "$work/Machine-files/Pictures/" "$HOME/Pictures/" || { rm -rf "$work"; return 1; }
    fi
    touch "$marker"
  else
    rm -rf "$work"
    return 1
  fi
  rm -rf "$work"
}

install_sensors_applet() {
  local work applets="${XDG_DATA_HOME:-$HOME/.local/share}/cinnamon/applets"
  if [ -e "$applets/Sensors@claudiux" ]; then return 0; fi
  if [ "$DRY_RUN" = 1 ]; then echo '[dry-run] Install Sensors applet'; return 0; fi
  work=$(mktemp -d) || return 1
  if download_with_retry 'https://cinnamon-spices.linuxmint.com/files/applets/Sensors@claudiux.zip' "$work/sensors.zip" && \
      unzip -oq "$work/sensors.zip" -d "$work" && [ -f "$work/Sensors@claudiux/metadata.json" ]; then
    mkdir -p "$applets/Sensors@claudiux"
    # The ZIP already contains Sensors@claudiux/, so do not nest it twice.
    rsync -a "$work/Sensors@claudiux/" "$applets/Sensors@claudiux/" || { rm -rf "$work"; return 1; }
  else
    rm -rf "$work"
    return 1
  fi
  rm -rf "$work"
}

install_desktop_themes() {
  local work
  if [ "$DRY_RUN" = 1 ]; then echo '[dry-run] Install missing desktop themes'; return 0; fi
  mkdir -p "$HOME/.themes"
  if [ "$FORCE_ARTWORK" = 1 ] || [ ! -e "$HOME/.themes/Windows-10" ]; then
    work=$(mktemp -d) || return 1
    if download_with_retry 'https://cinnamon-spices.linuxmint.com/files/themes/Windows-10.zip' "$work/theme.zip" && \
        unzip -oq "$work/theme.zip" -d "$work" && [ -d "$work/Windows-10" ]; then
      if [ -e "$HOME/.themes/Windows-10" ]; then mv "$HOME/.themes/Windows-10" "$BACKUP_DIR/Windows-10"; fi
      mv "$work/Windows-10" "$HOME/.themes/" || { mv "$BACKUP_DIR/Windows-10" "$HOME/.themes/"; rm -rf "$work"; return 1; }
    else
      warn 'Windows-10 Cinnamon theme was unavailable; keeping installed theme.'
    fi
    rm -rf "$work"
  fi
  if [ "$FORCE_ARTWORK" = 1 ] || [ ! -e "$HOME/.themes/Windows-10-Dark" ]; then
    work=$(mktemp -d) || return 1
    if git clone --depth 1 https://github.com/B00merang-Project/Windows-10-Dark.git "$work/theme"; then
      if [ -e "$HOME/.themes/Windows-10-Dark" ]; then mv "$HOME/.themes/Windows-10-Dark" "$BACKUP_DIR/Windows-10-Dark"; fi
      mv "$work/theme" "$HOME/.themes/Windows-10-Dark" || { mv "$BACKUP_DIR/Windows-10-Dark" "$HOME/.themes/"; rm -rf "$work"; return 1; }
    else
      warn 'Windows-10-Dark GTK theme was unavailable; keeping installed theme.'
    fi
    rm -rf "$work"
  fi
}

write_missing_file() {
  if [ -e "$1" ] || [ -L "$1" ]; then
    cat >/dev/null
    printf 'Keeping existing file: %s\n' "$1"
    return 0
  fi
  write_managed_file "$@"
}

backup_desktop_settings() {
  command_exists dconf || { echo 'dconf is required before applying desktop defaults.' >&2; return 1; }
  dconf dump / > "$BACKUP_DIR/desktop.dconf" || return 1
  backup_file "$HOME/.dmrc" || return 1
  local directory
  for directory in "$HOME/.icons/Yaru-blue-qortal" "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"; do
    if [ -d "$directory" ]; then
      cp -a "$directory" "$BACKUP_DIR/$(basename "$directory")" || return 1
    fi
  done
}

# Quote arguments using both desktop-entry escaping and Exec quoting rules.
desktop_exec() {
  python3 - "$@" <<'PYEXEC'
import sys
# Keep the executable token stable: GIO checks it before expanding %% in paths.
print('/usr/bin/env', end=' ')
for arg in sys.argv[1:]:
    quoted = '"' + ''.join('\\' + c if c in '\\"`$' else c for c in arg) + '"'
    print(quoted.replace('\\', '\\\\').replace('%', '%%'), end=' ')
print()
PYEXEC
}

autostart_has_script() {
  local entry
  for entry in "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/"*.desktop; do
    [ -f "$entry" ] || continue
    if grep -E '^[[:space:]]*Exec=' "$entry" | grep -F "$1" >/dev/null; then return 0; fi
  done
  return 1
}

queue_desktop_branding() {
  local mode=--branding-only
  [ "$APPLY_DEFAULTS" = 0 ] || mode=--settings-only
  if ! autostart_has_script apply-cinnamon-settings.sh; then
    write_missing_file "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/apply-cinnamon-settings.desktop" <<EOF
[Desktop Entry]
Type=Application
Exec=$(desktop_exec "$HOME/apply-cinnamon-settings.sh" --first-login "$mode")
OnlyShowIn=X-Cinnamon;
NoDisplay=true
Name=Finish Qortal Cinnamon Setup
Icon=qortal
EOF
  fi
  echo 'Qortal desktop branding queued for the next Cinnamon login.'
}

apply_or_defer_desktop_branding() {
  [ "$APPLY_BRANDING" = 1 ] || return 0
  local mode=--branding-only
  [ "$APPLY_DEFAULTS" = 0 ] || mode=--settings-only
  if desktop_session_available; then
    if backup_desktop_settings && \
        REBUILT_MACHINE_BACKUP_DIR="$BACKUP_DIR" bash "$HOME/apply-cinnamon-settings.sh" "$mode"; then
      if [ "$APPLY_DEFAULTS" = 1 ]; then
        REBUILT_MACHINE_BACKUP_DIR="$BACKUP_DIR" bash "$HOME/configure-terminal-and-more.sh" || warn 'Some optional desktop preferences could not be applied.'
      fi
      return 0
    fi
    warn 'Desktop branding could not be applied in this session; retrying at Cinnamon login.'
  fi
  queue_desktop_branding
}

install_desktop_launchers() {
  local config="${XDG_CONFIG_HOME:-$HOME/.config}" applications="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  write_missing_file "$HOME/run-script-in-terminal.sh" 755 <<'WRAPPER'
#!/bin/bash
set -eu
if [ "${1:-}" = --delay ]; then
  sleep "$2"
  shift 2
fi
TARGET_SCRIPT="${1:-}"
[ -n "$TARGET_SCRIPT" ] && [ -x "$TARGET_SCRIPT" ] || { echo "Missing executable: $TARGET_SCRIPT" >&2; exit 1; }
shift
if command -v gnome-terminal >/dev/null 2>&1; then
  exec gnome-terminal -- "$TARGET_SCRIPT" "$@"
elif command -v mate-terminal >/dev/null 2>&1; then
  exec mate-terminal -- "$TARGET_SCRIPT" "$@"
elif command -v xfce4-terminal >/dev/null 2>&1; then
  exec xfce4-terminal --execute "$TARGET_SCRIPT" "$@"
elif command -v x-terminal-emulator >/dev/null 2>&1; then
  exec x-terminal-emulator -e "$TARGET_SCRIPT" "$@"
else
  exec "$TARGET_SCRIPT" "$@"
fi
WRAPPER
  write_missing_file "$applications/apply-cinnamon-settings.desktop" <<EOF
[Desktop Entry]
Type=Application
Exec=$(desktop_exec "$HOME/run-script-in-terminal.sh" "$HOME/apply-cinnamon-settings.sh")
Icon=preferences-desktop-theme
Name=Apply Cinnamon Settings
Comment=Apply Qortal desktop settings and the 40-pixel menu icon
Terminal=false
Categories=Settings;
EOF
  # Existing cron schedules take precedence over adding a second GUI trigger.
  if ! autostart_has_script auto-fix-qortal.sh && ! LC_ALL=C crontab -l 2>/dev/null | sed '/^[[:space:]]*#/d' | grep 'auto-fix-qortal[.]sh' >/dev/null; then
    write_missing_file "$config/autostart/auto-fix-qortal-GUI.desktop" <<EOF
[Desktop Entry]
Type=Application
Exec=$(desktop_exec "$HOME/run-script-in-terminal.sh" --delay 420 "$HOME/auto-fix-qortal.sh")
Name=Qortal Maintenance
Comment=Run Qortal maintenance seven minutes after login
Icon=qortal
Terminal=false
EOF
  fi
  if ! autostart_has_script start-qortal-core.sh && ! LC_ALL=C crontab -l 2>/dev/null | grep -E '^[[:space:]]*@reboot.*start-qortal-core[.]sh' >/dev/null; then
    write_missing_file "$config/autostart/start-qortal.desktop" <<EOF
[Desktop Entry]
Type=Application
Exec=$(desktop_exec "$HOME/start-qortal-core.sh")
Name=Qortal Core
Icon=qortal
Terminal=false
EOF
  fi
  command_exists update-desktop-database && update-desktop-database "$applications" || true
}

install_rebuilt_cron() {
  local work
  work=$(mktemp -d) || return 1
  if ! LC_ALL=C crontab -l > "$work/old" 2> "$work/errors"; then
    if ! grep -qi 'no crontab' "$work/errors"; then
      cat "$work/errors" >&2
      rm -rf "$work"
      return 1
    fi
  fi
  cp "$work/old" "$work/new"
  # Preserve custom schedules, including jobs for these same scripts.
  # Ignore comments when deciding whether an automation entry already exists.
  local active
  active=$(sed '/^[[:space:]]*#/d' "$work/old")
  if [ "$HEADLESS_MODE" = true ]; then
    if ! grep -Eq '^[[:space:]]*@reboot.*start-qortal-core[.]sh' <<< "$active"; then
      printf '@reboot "${HOME}/start-qortal-core.sh"\n' >> "$work/new"
    fi
    if ! grep -q 'auto-fix-qortal[.]sh' <<< "$active"; then
      printf '@reboot sleep 399 && "${HOME}/auto-fix-qortal.sh" > "${HOME}/auto-fix-startup.log" 2>&1\n' >> "$work/new"
    fi
  fi
  if ! sed '/^[[:space:]]*@/d' <<< "$active" | grep -q 'auto-fix-qortal[.]sh'; then
    printf '1 1 */3 * * "${HOME}/auto-fix-qortal.sh" > "${HOME}/log-auto-fix-cron.log" 2>&1\n' >> "$work/new"
  fi
  if ! cmp -s "$work/old" "$work/new"; then
    [ -z "$BACKUP_DIR" ] || cp "$work/old" "$BACKUP_DIR/crontab"
    run crontab "$work/new" || { rm -rf "$work"; return 1; }
  fi
  rm -rf "$work"
}

# Check only the JVM for this installation. An offline/syncing node is still
# an existing installation, and is never moved aside by the rebuild.
core_is_running() {
  python3 - "$HOME/qortal/qortal.jar" <<'PYCORE'
import os
import sys
from pathlib import Path
jar = Path(sys.argv[1]).resolve()
for proc in Path('/proc').glob('[0-9]*'):
    try:
        if Path(os.readlink(proc / 'exe')).name not in ('java', 'java (deleted)'):
            continue
        args = (proc / 'cmdline').read_bytes().decode(errors='surrogateescape').split('\0')
        if '-jar' not in args:
            continue
        argument = Path(args[args.index('-jar') + 1])
        if not argument.is_absolute():
            argument = Path(os.readlink(proc / 'cwd')) / argument
        if argument.resolve() == jar:
            sys.exit(0)
    except (FileNotFoundError, PermissionError, ProcessLookupError, IndexError):
        continue
sys.exit(1)
PYCORE
}

install_qortal_core() {
  local work jar="$HOME/qortal/qortal.jar"
  if [ -e "$HOME/qortal" ] || [ -L "$HOME/qortal" ]; then
    if [ "$UPDATE_CORE" = 0 ]; then
      echo 'Keeping existing Core installation (use --update-core to update its jar).'
      [ -s "$jar" ] || warn 'Existing Core has no nonempty qortal.jar; preserving it for manual repair.'
      return 0
    fi
    [ -d /proc/self ] || { echo 'Linux /proc is required to check Core before updating.' >&2; return 1; }
    if core_is_running; then
      echo 'Stop this Core with ~/qortal/stop.sh before using --update-core; no files changed.' >&2
      return 1
    fi
    [ -d "$HOME/qortal" ] || { echo '~/qortal is not a directory; refusing to replace it.' >&2; return 1; }
  fi
  work=$(mktemp -d "$HOME/.qortector-core.XXXXXX") || return 1
  if ! download_with_retry 'https://github.com/Qortal/qortal/releases/latest/download/qortal.zip' "$work/qortal.zip" 8 || \
      ! unzip -oq "$work/qortal.zip" -d "$work" || \
      ! unzip -tq "$work/qortal/qortal.jar" >/dev/null 2>&1 || \
      ! unzip -p "$work/qortal/qortal.jar" META-INF/MANIFEST.MF | grep -qi '^Main-Class:'; then
    rm -rf "$work"
    echo 'Invalid Core release; existing installation preserved.' >&2
    return 1
  fi
  if [ -d "$HOME/qortal" ]; then
    # No settings, database, lists, keys or custom scripts are replaced.
    if ! cmp -s "$work/qortal/qortal.jar" "$jar"; then
      backup_file "$jar"
      mv -f "$work/qortal/qortal.jar" "$jar"
    fi
  else
    chmod +x "$work/qortal/"*.sh
    mv "$work/qortal" "$HOME/qortal"
  fi
  rm -rf "$work"
}

hub_binary() {
  local file
  for file in "$HOME/qortal-hub/Qortal-Hub" "$HOME/qortal-hub/Qortal-Hub.AppImage" "$HOME/qortal-hub/Qortal-Hub-arm64.AppImage"; do
    if [ -s "$file" ]; then printf '%s\n' "$file"; return 0; fi
  done
  return 1
}

install_qortal_hub() {
  local existing="" work asset version="" url digest metadata="$HOME/qortal-hub/.qortector-release.json"
  existing=$(hub_binary) || true
  local HUB_WAS_PRESENT="$existing"
  if [ -n "$existing" ] && [ "$UPDATE_HUB" = 0 ]; then
    echo 'Keeping existing Hub AppImage (use --update-hub to check the latest release).'
    return 0
  fi
  case "$(uname -m)" in
    aarch64|arm64) asset=Qortal-Hub-arm64.AppImage ;;
    x86_64|amd64) asset=Qortal-Hub.AppImage ;;
    *) warn 'No supported Hub AppImage for this architecture; Core remains available.'; return 0 ;;
  esac
  work=$(mktemp -d "$HOME/.qortector-hub.XXXXXX") || return 1
  url="https://github.com/Qortal/Qortal-Hub/releases/latest/download/$asset"
  # Cache the release tag and binary hash together; an untracked or locally
  # modified AppImage is compared with the downloaded release instead.
  if download_with_retry 'https://api.github.com/repos/Qortal/Qortal-Hub/releases/latest' "$work/release.json" 1; then
    version=$(jq -r '.tag_name // empty' "$work/release.json")
  fi
  if [ -n "$existing" ] && [ -n "$version" ] && [ -f "$metadata" ]; then
    digest=$(sha256sum "$existing"); digest=${digest%% *}
    if jq -e --arg version "$version" --arg hash "$digest" \
        '.version == $version and .sha256 == $hash' "$metadata" >/dev/null 2>&1; then
      echo "Hub is already current ($version)."
      rm -rf "$work"
      return 0
    fi
  fi
  if ! download_with_retry "$url" "$work/$asset" 8 || \
      [ "$(od -An -tx1 -N4 "$work/$asset" | tr -d ' \n')" != 7f454c46 ]; then
    rm -rf "$work"
    echo 'Invalid Hub AppImage; existing binary preserved.' >&2
    return 1
  fi
  mkdir -p "$HOME/qortal-hub"
  if [ -z "$existing" ] || ! cmp -s "$work/$asset" "$existing"; then
    [ -z "$existing" ] || backup_file "$existing"
    chmod 755 "$work/$asset"
    # Preserve an existing .AppImage filename and its custom launchers.
    mv -f "$work/$asset" "${existing:-$HOME/qortal-hub/Qortal-Hub}"
  fi
  existing=${existing:-$HOME/qortal-hub/Qortal-Hub}
  digest=$(sha256sum "$existing"); digest=${digest%% *}
  jq -n --arg version "$version" --arg hash "$digest" '{version:$version,sha256:$hash}' | write_managed_file "$metadata" 644
  rm -rf "$work"
  if [ -z "${HUB_WAS_PRESENT:-}" ] && [ "${HEADLESS_MODE:-true}" = false ] && \
      [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}${XDG_CURRENT_DESKTOP:-}" ]; then
    local hub_pid
    # The GUI must not retain the maintenance lock. Persist this fallback in
    # the launcher below as well, since later sessions have a fresh environment.
    (exec 9>&-; if (ldconfig -p 2>/dev/null || true) | grep 'libfuse.so.2' >/dev/null; then "$existing"; else APPIMAGE_EXTRACT_AND_RUN=1 "$existing"; fi) &
    hub_pid=$!
    sleep 7
    if kill -0 "$hub_pid" 2>/dev/null; then
      kill -TERM "$hub_pid" 2>/dev/null || true
      wait "$hub_pid" 2>/dev/null || true
    else
      HUB_SANDBOX_FLAG=--no-sandbox
    fi
  fi
}

install_qortal_menu() {
  local applications="${XDG_DATA_HOME:-$HOME/.local/share}/applications" config="${XDG_CONFIG_HOME:-$HOME/.config}" binary prefix="" merge
  binary=$(hub_binary) || binary="$HOME/qortal-hub/Qortal-Hub"
  # Persist extraction mode when FUSE2 is unavailable, as the old child did.
  if ! (ldconfig -p 2>/dev/null || true) | grep 'libfuse.so.2' >/dev/null; then prefix='APPIMAGE_EXTRACT_AND_RUN=1'; fi
  write_missing_file "$applications/qortal-hub.desktop" <<ENTRY
[Desktop Entry]
Type=Application
Name=Qortal Hub
Exec=$(desktop_exec ${prefix:+"$prefix"} "$binary" ${HUB_SANDBOX_FLAG:+"$HUB_SANDBOX_FLAG"})
Icon=qortal-hub
Terminal=false
Categories=X-Qortal;Utility;
ENTRY
  write_missing_file "$applications/qortal-core.desktop" <<ENTRY
[Desktop Entry]
Type=Application
Name=Qortal Core
Exec=$(desktop_exec "$HOME/start-qortal-core.sh")
Icon=qortal
Terminal=false
Categories=X-Qortal;Utility;
ENTRY
  write_missing_file "${XDG_DATA_HOME:-$HOME/.local/share}/desktop-directories/Qortal.directory" <<'ENTRY'
[Desktop Entry]
Name=Qortal
Comment=Qortal Applications
Icon=qortal-menu-button-3
Type=Directory
ENTRY
  for merge in applications cinnamon-applications xfce-applications; do
    write_missing_file "$config/menus/$merge-merged/Qortal.menu" <<'MENU'
<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN" "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">
<Menu>
  <Name>Applications</Name>
  <Menu>
    <Name>Qortal</Name>
    <Directory>Qortal.directory</Directory>
    <Include><Category>X-Qortal</Category><Category>Qortal</Category></Include>
  </Menu>
</Menu>
MENU
  done
  if [ -d "$HOME/Desktop" ]; then
    write_missing_file "$HOME/Desktop/qortal-hub.desktop" 755 < "$applications/qortal-hub.desktop"
  fi
  command_exists update-desktop-database && update-desktop-database "$applications" || true
}

preview_setup() {
  echo '[dry-run] No changes, downloads, sudo calls or child scripts will run. Package commands below apply only to missing packages.'
  prepare_packages
  pkg_install git jq unzip curl wget ca-certificates rsync python3 imagemagick cron util-linux
  echo '[dry-run] Install missing optional utilities, Java and FUSE2 using distro package mappings.'
  if [ -e "$HOME/qortal" ] && [ "$UPDATE_CORE" = 0 ]; then
    echo '[dry-run] Keep existing Core'
  else
    echo '[dry-run] Download/validate Core; update only the jar of an existing stopped Core'
  fi
  if hub_binary >/dev/null && [ "$UPDATE_HUB" = 0 ]; then
    echo '[dry-run] Keep existing Hub'
  else
    echo '[dry-run] Check latest Hub release; download only if not current'
  fi
  printf '[dry-run] Artwork: fill missing assets; force replacement=%s\n' "$FORCE_ARTWORK"
  if [ "$HEADLESS_MODE" = false ]; then
    echo '[dry-run] Install missing Cinnamon packages, themes, applet and launchers'
    if [ "$APPLY_DEFAULTS" = 1 ]; then
      echo '[dry-run] Back up desktop files; apply repo preferences in a session or queue them for Cinnamon login'
    elif [ "$APPLY_BRANDING" = 1 ]; then
      echo '[dry-run] Fresh desktop: apply Qortal wallpaper, icons and menu branding, or queue them for Cinnamon login'
    else
      echo '[dry-run] Preserve desktop preferences and session selection'
    fi
  fi
  echo '[dry-run] Preserve custom helpers/autostarts/cron; add missing automation and record successful setup state'
  printf '[dry-run] Reboot requested: %s\n' "${REBUILT_MACHINE_REBOOT:-0}"
}

main() {
  set -Eeuo pipefail
  local parse_status=0
  parse_args "$@" || parse_status=$?
  if [ "$parse_status" = 10 ]; then return 0; fi
  [ "$parse_status" = 0 ] || return "$parse_status"
  trap 'printf "Rebuild failed at line %s. Automatic reboot cancelled.\n" "$LINENO" >&2' ERR
  detect_distro
  HEADLESS_MODE=false
  if is_headless_mode; then HEADLESS_MODE=true; fi
  APPLY_BRANDING=0
  if [ "$HEADLESS_MODE" = false ] && { [ "$APPLY_DEFAULTS" = 1 ] || is_fresh_desktop; }; then
    APPLY_BRANDING=1
  fi
  printf 'Rebuilt-machine setup: %s mode\n' "$([ "$HEADLESS_MODE" = true ] && echo headless || echo desktop)"
  if [ "$DRY_RUN" = 1 ]; then preview_setup; return 0; fi
  if [ "$(id -u)" -eq 0 ]; then
    echo 'Run this script as the intended desktop/Core user, without sudo. It requests sudo for packages.' >&2
    return 1
  fi
  command_exists sudo || { echo 'sudo is required for system packages.' >&2; return 1; }
  mkdir -p "$HOME/backups"
  BACKUP_DIR=$(mktemp -d "$HOME/backups/rebuilt-machine-$(date +%Y%m%d-%H%M%S).XXXXXX")
  sudo -v
  prepare_packages
  local cron_present=0
  if package_installed "$(map_package cron)"; then cron_present=1; fi
  pkg_install git jq unzip curl wget ca-certificates rsync python3 imagemagick cron util-linux
  if [ "$cron_present" = 0 ] && [ "$PKG_MANAGER" != apt-get ] && command_exists systemctl; then
    local cron_service=cronie.service
    [ "$PKG_MANAGER" != dnf ] || cron_service=crond.service
    sudo systemctl enable --now "$cron_service" || warn "Could not start $cron_service; enable cron manually."
  fi
  # Share the maintenance lock so the jar cannot change under an auto-fix run.
  exec 9>"$HOME/.auto-fix-qortal.lock"
  flock -n 9 || { echo 'Another rebuild/maintenance run is active; try again later.' >&2; return 1; }
  install_packages_if_available openssh-server vim zlib1g-dev htop net-tools ffmpeg sysbench smartmontools fonts-symbola lm-sensors xdg-utils
  install_first_available_package 7zip p7zip-full || warn 'No supported 7-Zip package could be installed.'
  install_first_available_package btop bpytop || warn 'No optional system monitor could be installed.'
  install_java_runtime || {
    if [ "$PKG_MANAGER" = pacman ]; then
      printf '%s\n' 'A supported Java runtime is required. The system appears to need a full upgrade. Run: sudo pacman -Syu' \
        'Then re-run this script.' >&2
    else
      echo 'A supported Java runtime is required (Java 17 packages unavailable).' >&2
    fi
    return 1
  }
  install_first_available_package libfuse2t64 libfuse2 || warn 'FUSE2 unavailable; Hub will use AppImage extraction mode.'
  if [ "$HEADLESS_MODE" = false ]; then
    # Fedora and Arch ship Cinnamon in the normal repositories. Never enable a
    # third-party repository automatically when a package is unavailable.
    install_first_available_package cinnamon-desktop-environment cinnamon || { echo 'Cinnamon installation failed; check your distro repositories.' >&2; return 1; }
    install_packages_if_available gnome-software yaru-theme-icon yaru-theme-gtk vlc chromium-browser ksnip xsensors gparted gnome-terminal dconf-cli libglib2.0-bin
    install_first_available_package gnome-text-editor gedit || warn 'No supported text editor could be installed.'
    install_first_available_package loupe eog || warn 'No supported image viewer could be installed.'
    install_first_available_package papers evince || warn 'No supported PDF viewer could be installed.'
    install_sensors_applet || warn 'Sensors Monitor applet installation failed.'
    if [ "$APPLY_DEFAULTS" = 1 ]; then
      backup_file "$HOME/.dmrc"
      if command_exists pro; then sudo pro config set apt_news=false || warn 'Could not disable Ubuntu Pro terminal news.'; fi
      python3 - <<'PYSESSION'
import configparser
from pathlib import Path
p = Path.home() / '.dmrc'
c = configparser.ConfigParser(interpolation=None)
c.optionxform = str
if p.exists():
    c.read(p)
if not c.has_section('Desktop'):
    c.add_section('Desktop')
c.set('Desktop', 'Session', 'cinnamon')
with p.open('w') as out:
    c.write(out)
PYSESSION
    fi
  fi
  # Do not invoke the standalone installer: its legacy replacement/preferences
  # behavior is intentionally separate from this preserve-existing entry point.
  install_qortal_core
  install_qortal_hub
  local helper
  for helper in refresh-qortal.sh auto-fix-qortal.sh check-qortal-status.sh start-qortal-core.sh; do
    install_repo_file "$helper" "$HOME/$helper"
  done
  if [ "$FORCE_ARTWORK" = 1 ] && [ -d "$HOME/Pictures" ]; then cp -a "$HOME/Pictures" "$BACKUP_DIR/Pictures"; fi
  install_machine_artwork || warn 'Machine artwork bundle unavailable; the icon helper can fetch missing icons.'
  if [ "$FORCE_ARTWORK" = 1 ]; then
    local directory
    for directory in "$HOME/.icons/Yaru-blue-qortal" "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"; do
      [ ! -d "$directory" ] || [ -e "$BACKUP_DIR/$(basename "$directory")" ] || cp -a "$directory" "$BACKUP_DIR/$(basename "$directory")"
    done
  fi
  install_qortal_icons
  install_qortal_menu
  if [ "$HEADLESS_MODE" = false ]; then
    install_desktop_themes
    # Refresh branding helpers when applying them, including after a partial
    # first install, so a preserved legacy helper cannot bypass session guards.
    install_repo_file cinnamon-settings.json "$HOME/cinnamon-settings.json" 644 "$APPLY_BRANDING"
    install_repo_file apply-cinnamon-settings.sh "$HOME/apply-cinnamon-settings.sh" 755 "$APPLY_BRANDING"
    install_repo_file configure-terminal-and-more.sh "$HOME/configure-terminal-and-more.sh" 755 "$APPLY_DEFAULTS"
    apply_or_defer_desktop_branding
    install_desktop_launchers
    echo 'Choose Cinnamon in the login-screen session selector when ready.'
  fi
  install_rebuilt_cron
  # Informational only: actual files/packages remain authoritative after a
  # partial run or manual change; an old state file never suppresses repairs.
  jq -n --arg distro "$DISTRO_ID" --arg manager "$PKG_MANAGER" \
    --arg completed "$(date -u +%FT%TZ)" --arg backups "$BACKUP_DIR" \
    '{schema:1,lastSuccessfulRun:$completed,distro:$distro,packageManager:$manager,backupDirectory:$backups}' | \
    write_managed_file "$HOME/.qortector-setup-state.json" 600
  printf 'Setup complete. Previous configuration is backed up in %s\n' "$BACKUP_DIR"
  if [ "${#WARNINGS[@]}" -gt 0 ]; then
    printf 'Optional setup warnings:\n'
    printf ' - %s\n' "${WARNINGS[@]}"
  fi
  if [ "${REBUILT_MACHINE_REBOOT:-0}" = 0 ]; then
    echo 'Automatic reboot disabled. Reboot when ready to start boot-time automation.'
    return 0
  fi
  echo 'Rebooting in 30 seconds. Press Ctrl+C to cancel.'
  sleep 30
  sudo reboot
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
