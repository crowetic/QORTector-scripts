#!/bin/bash
# Run as the desktop/Core user; sudo is used only for system packages.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="https://raw.githubusercontent.com/crowetic/QORTector-scripts/main"
WARNINGS=()
BACKUP_DIR=""

warn() {
  printf 'Warning: %s\n' "$*" >&2
  WARNINGS+=("$*")
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

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
  local name="$1" target="$2" mode="${3:-755}" source_file="$SCRIPT_DIR/$1" tmp
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

package_available() {
  local candidate
  candidate=$(LC_ALL=C apt-cache policy "$1" | awk '/Candidate:/ {print $2; exit}') || return 1
  [ -n "$candidate" ] && [ "$candidate" != '(none)' ]
}

install_packages_if_available() {
  local package
  for package in "$@"; do
    if package_available "$package"; then
      sudo apt-get install -y "$package" || warn "Could not install optional package: $package"
    else
      warn "Optional package is unavailable: $package"
    fi
  done
}

install_first_available_package() {
  local package
  for package in "$@"; do
    if package_available "$package" && sudo apt-get install -y "$package"; then
      return 0
    fi
  done
  return 1
}

ensure_qortal_setup_script() {
  QORTAL_SETUP_SCRIPT="$HOME/Qortal-Setup-Linux.sh"
  install_repo_file Qortal-Setup-Linux.sh "$QORTAL_SETUP_SCRIPT"
}

install_qortal_icons() {
  install_repo_file create-icon-theme-uni.sh "$HOME/create-icon-theme-uni.sh" || return 1
  bash "$HOME/create-icon-theme-uni.sh" || return 1
  if [ "${HEADLESS_MODE:-false}" = false ]; then
    gsettings set org.cinnamon.desktop.interface icon-theme Yaru-blue-qortal || \
      warn 'Could not select the Cinnamon icon theme; hicolor icons remain available.'
  fi
}

install_machine_artwork() {
  local work
  work=$(mktemp -d) || return 1
  if download_with_retry 'https://cloud.qortal.org/s/machinefilesnew/download' "$work/machine.zip" && \
      unzip -oq "$work/machine.zip" -d "$work" && [ -d "$work/Machine-files/Pictures" ]; then
    mkdir -p "$HOME/Pictures"
    # The bundle supplies artwork, not executable scripts or user configuration.
    rsync -a "$work/Machine-files/Pictures/" "$HOME/Pictures/" || { rm -rf "$work"; return 1; }
  else
    rm -rf "$work"
    return 1
  fi
  rm -rf "$work"
}

install_sensors_applet() {
  local work applets="${XDG_DATA_HOME:-$HOME/.local/share}/cinnamon/applets"
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
  mkdir -p "$HOME/.themes"
  if [ ! -d "$HOME/.themes/Windows-10" ]; then
    work=$(mktemp -d) || return 1
    if download_with_retry 'https://cinnamon-spices.linuxmint.com/files/themes/Windows-10.zip' "$work/theme.zip" && \
        unzip -oq "$work/theme.zip" -d "$work" && [ -d "$work/Windows-10" ]; then
      mv "$work/Windows-10" "$HOME/.themes/"
    else
      warn 'Windows-10 Cinnamon theme was unavailable; keeping installed theme.'
    fi
    rm -rf "$work"
  fi
  if [ ! -d "$HOME/.themes/Windows-10-Dark" ]; then
    work=$(mktemp -d) || return 1
    if git clone --depth 1 https://github.com/B00merang-Project/Windows-10-Dark.git "$work/theme"; then
      mv "$work/theme" "$HOME/.themes/Windows-10-Dark"
    else
      warn 'Windows-10-Dark GTK theme was unavailable; keeping installed theme.'
    fi
    rm -rf "$work"
  fi
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

install_desktop_launchers() {
  local config="${XDG_CONFIG_HOME:-$HOME/.config}" applications="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  write_managed_file "$HOME/run-script-in-terminal.sh" 755 <<'WRAPPER'
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
  write_managed_file "$applications/apply-cinnamon-settings.desktop" <<EOF
[Desktop Entry]
Type=Application
Exec=$(desktop_exec "$HOME/run-script-in-terminal.sh" "$HOME/apply-cinnamon-settings.sh")
Icon=preferences-desktop-theme
Name=Apply Cinnamon Settings
Comment=Apply Qortal desktop settings and the 40-pixel menu icon
Terminal=false
Categories=Settings;
EOF
  write_managed_file "$config/autostart/apply-cinnamon-settings.desktop" <<EOF
[Desktop Entry]
Type=Application
Exec=$(desktop_exec "$HOME/apply-cinnamon-settings.sh" --first-login)
OnlyShowIn=X-Cinnamon;
NoDisplay=true
Name=Finish Qortal Cinnamon Setup
Icon=qortal
EOF
  write_managed_file "$config/autostart/auto-fix-qortal-GUI.desktop" <<EOF
[Desktop Entry]
Type=Application
Exec=$(desktop_exec "$HOME/run-script-in-terminal.sh" --delay 420 "$HOME/auto-fix-qortal.sh")
Name=Qortal Maintenance
Comment=Run Qortal maintenance seven minutes after login
Icon=qortal
Terminal=false
EOF
  write_managed_file "$config/autostart/start-qortal.desktop" <<EOF
[Desktop Entry]
Type=Application
Exec=$(desktop_exec "$HOME/start-qortal-core.sh")
Name=Qortal Core
Icon=qortal
Terminal=false
EOF
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
  # Preserve comments, variables and unrelated jobs, including manual schedules.
  awk '/^[[:space:]]*#/ || ($0 !~ /(^|[ /])auto-fix-qortal\.sh(["[:space:]]|$)/ && !($0 ~ /^@reboot/ && $0 ~ /start-qortal-core\.sh/))' "$work/old" > "$work/new"
  if [ "$HEADLESS_MODE" = true ]; then
    printf '@reboot "${HOME}/start-qortal-core.sh"\n' >> "$work/new"
    printf '@reboot sleep 399 && "${HOME}/auto-fix-qortal.sh" > "${HOME}/auto-fix-startup.log" 2>&1\n' >> "$work/new"
  fi
  printf '1 1 */3 * * "${HOME}/auto-fix-qortal.sh" > "${HOME}/log-auto-fix-cron.log" 2>&1\n' >> "$work/new"
  if ! cmp -s "$work/old" "$work/new"; then
    [ -z "$BACKUP_DIR" ] || cp "$work/old" "$BACKUP_DIR/crontab"
    crontab "$work/new" || { rm -rf "$work"; return 1; }
  fi
  rm -rf "$work"
}

main() {
  set -Eeuo pipefail
  trap 'printf "Rebuild failed at line %s. Automatic reboot cancelled.\n" "$LINENO" >&2' ERR
  if [ "$(id -u)" -eq 0 ]; then
    echo 'Run this script as the intended desktop/Core user, without sudo. It requests sudo for packages.' >&2
    return 1
  fi
  command_exists apt-get && command_exists sudo || { echo 'An Ubuntu/Debian-based system with sudo is required.' >&2; return 1; }
  case "${REBUILT_MACHINE_HEADLESS:-auto}" in auto|0|1) ;; *) echo 'REBUILT_MACHINE_HEADLESS must be auto, 0 or 1.' >&2; return 1 ;; esac
  case "${REBUILT_MACHINE_REBOOT:-1}" in 0|1) ;; *) echo 'REBUILT_MACHINE_REBOOT must be 0 or 1.' >&2; return 1 ;; esac
  HEADLESS_MODE=false
  if is_headless_mode; then HEADLESS_MODE=true; fi
  if [ "$HEADLESS_MODE" = true ]; then
    # Do not let a forced headless run configure or launch a desktop in a child.
    unset DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
  fi
  printf 'Rebuilt-machine setup: %s mode\n' "$([ "$HEADLESS_MODE" = true ] && echo headless || echo desktop)"
  mkdir -p "$HOME/backups"
  BACKUP_DIR=$(mktemp -d "$HOME/backups/rebuilt-machine-$(date +%Y%m%d-%H%M%S).XXXXXX")
  sudo -v
  if command_exists pro; then sudo pro config set apt_news=false || warn 'Could not disable Ubuntu Pro terminal news.'; fi
  sudo apt-get -o APT::Update::Error-Mode=any update
  sudo apt-get -y upgrade
  sudo apt-get install -y git jq unzip curl wget ca-certificates rsync python3 imagemagick cron util-linux
  install_packages_if_available openssh-server vim zlib1g-dev htop net-tools ffmpeg sysbench smartmontools fonts-symbola lm-sensors xdg-utils
  install_first_available_package 7zip p7zip-full || warn 'No supported 7-Zip package could be installed.'
  install_first_available_package btop bpytop || warn 'No optional system monitor could be installed.'
  install_first_available_package openjdk-21-jre openjdk-21-jre-headless openjdk-17-jre openjdk-17-jre-headless || { echo 'A supported Java runtime is required.' >&2; return 1; }
  install_first_available_package libfuse2t64 libfuse2 || warn 'FUSE2 unavailable; Hub may require AppImage extraction mode.'
  if [ "$HEADLESS_MODE" = false ]; then
    install_first_available_package cinnamon-desktop-environment cinnamon || { echo 'Cinnamon installation failed.' >&2; return 1; }
    install_packages_if_available gnome-software yaru-theme-icon yaru-theme-gtk vlc chromium-browser ksnip xsensors gparted gnome-terminal dconf-cli
    install_first_available_package gnome-text-editor gedit || warn 'No supported text editor could be installed.'
    install_first_available_package loupe eog || warn 'No supported image viewer could be installed.'
    install_first_available_package papers evince || warn 'No supported PDF viewer could be installed.'
    install_sensors_applet || warn 'Sensors Monitor applet installation failed.'
    # Display managers may ignore .dmrc. Do not replace a custom .xsession.
    backup_file "$HOME/.dmrc"
    python3 - <<'PYSESSION'
import configparser, os
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
  ensure_qortal_setup_script
  # The rebuild installs automation after all assets/preferences are ready.
  QSL_INSTALL_AUTOMATION=0 bash "$QORTAL_SETUP_SCRIPT"
  local helper
  for helper in refresh-qortal.sh auto-fix-qortal.sh check-qortal-status.sh start-qortal-core.sh; do
    install_repo_file "$helper" "$HOME/$helper"
  done
  install_machine_artwork || warn 'Machine artwork bundle unavailable; the icon helper can fetch Qortal icons separately.'
  install_qortal_icons
  if [ "$HEADLESS_MODE" = false ]; then
    install_desktop_themes
    install_repo_file cinnamon-settings.json "$HOME/cinnamon-settings.json" 644
    install_repo_file apply-cinnamon-settings.sh "$HOME/apply-cinnamon-settings.sh"
    install_repo_file configure-terminal-and-more.sh "$HOME/configure-terminal-and-more.sh"
    REBUILT_MACHINE_BACKUP_DIR="$BACKUP_DIR" bash "$HOME/apply-cinnamon-settings.sh" --settings-only
    REBUILT_MACHINE_BACKUP_DIR="$BACKUP_DIR" bash "$HOME/configure-terminal-and-more.sh" || warn 'Some optional desktop preferences could not be applied.'
    install_desktop_launchers
    echo 'At the next login, choose Cinnamon in the login-screen session selector. Settings finish automatically in Cinnamon.'
  fi
  install_rebuilt_cron
  printf 'Setup complete. Previous configuration is backed up in %s\n' "$BACKUP_DIR"
  if [ "${#WARNINGS[@]}" -gt 0 ]; then
    printf 'Optional setup warnings:\n'
    printf ' - %s\n' "${WARNINGS[@]}"
  fi
  if [ "${REBUILT_MACHINE_REBOOT:-1}" = 0 ]; then
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
