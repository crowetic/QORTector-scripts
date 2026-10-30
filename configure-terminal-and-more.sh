#!/bin/bash
# Optional preferences for applications that are actually installed.

application_installed() {
  local app="$1" directory
  local -a data_dirs
  [ -f "${XDG_DATA_HOME:-$HOME/.local/share}/applications/$app" ] && return 0
  IFS=: read -r -a data_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  for directory in "${data_dirs[@]}"; do
    [ -f "$directory/applications/$app" ] && return 0
  done
  return 1
}

set_default_application() {
  local mime="$1" app
  shift
  for app in "$@"; do
    if application_installed "$app"; then
      xdg-mime default "$app" "$mime" || return 1
      return 0
    fi
  done
  printf 'No installed application found for %s; leaving its default unchanged.\n' "$mime"
}

main() {
  set -euo pipefail
  local work backup profile mime
  work=$(mktemp -d)
  PREFERENCES_WORK_DIR="$work"
  trap 'rm -rf "$PREFERENCES_WORK_DIR"' EXIT
  backup="${REBUILT_MACHINE_BACKUP_DIR:-$HOME/backups/desktop-preferences-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$backup"
  local defaults
  for defaults in "${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list" \
      "${XDG_DATA_HOME:-$HOME/.local/share}/applications/mimeapps.list"; do
    if [ -f "$defaults" ]; then
      cp -p "$defaults" "$backup/$(basename "$(dirname "$defaults")")-mimeapps.list"
    fi
  done
  if command -v xdg-mime >/dev/null 2>&1; then
    set_default_application text/plain org.gnome.TextEditor.desktop org.gnome.gedit.desktop gedit.desktop
    for mime in image/jpeg image/png image/gif; do
      set_default_application "$mime" org.gnome.Loupe.desktop org.gnome.eog.desktop
    done
    set_default_application audio/mpeg vlc.desktop
    set_default_application video/mp4 vlc.desktop
    set_default_application application/pdf org.gnome.Papers.desktop org.gnome.Evince.desktop evince.desktop
  fi
  if ! command -v dconf >/dev/null 2>&1; then
    echo 'dconf is unavailable; skipping optional application preferences.'
    return 0
  fi

  # Customize the active profile, without replacing the profile list or UUID.
  if command -v gsettings >/dev/null 2>&1 && \
      profile=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null); then
    profile="${profile//\'/}"
    if [[ "$profile" =~ ^[0-9a-fA-F-]{36}$ ]]; then
      dconf dump "/org/gnome/terminal/legacy/profiles:/:$profile/" > "$backup/terminal.dconf"
      cat > "$work/terminal.conf" <<'EOL'
[/]
background-color='rgb(12,30,34)'
default-size-columns=135
default-size-rows=35
foreground-color='rgb(131,148,150)'
palette=['rgb(7,54,66)', 'rgb(220,50,47)', 'rgb(43,201,123)', 'rgb(181,137,0)', 'rgb(38,139,210)', 'rgb(211,54,130)', 'rgb(42,161,152)', 'rgb(238,232,213)', 'rgb(0,43,54)', 'rgb(203,75,22)', 'rgb(88,110,117)', 'rgb(101,123,131)', 'rgb(131,148,150)', 'rgb(108,113,196)', 'rgb(147,161,161)', 'rgb(253,246,227)']
use-theme-colors=false
EOL
      dconf load "/org/gnome/terminal/legacy/profiles:/:$profile/" < "$work/terminal.conf"
    else
      echo 'No valid default GNOME Terminal profile; leaving profiles unchanged.'
    fi
  fi
  if application_installed org.gnome.gedit.desktop || application_installed gedit.desktop; then
    dconf dump /org/gnome/gedit/ > "$backup/gedit.dconf"
    cat > "$work/gedit.conf" <<'EOL'
[preferences/editor]
display-line-numbers=false
scheme='solarized-dark'
wrap-last-split-mode='word'

[preferences/ui]
show-tabs-mode='auto'
EOL
    # Sections are relative to the application root, not preferences/preferences.
    dconf load /org/gnome/gedit/ < "$work/gedit.conf"
  fi
  if application_installed nemo.desktop; then
    dconf dump /org/nemo/ > "$backup/nemo.dconf"
    cat > "$work/nemo.conf" <<'EOL'
[preferences]
confirm-move-to-trash=true
enable-delete=false
show-home-icon-toolbar=true
show-open-in-terminal-toolbar=true
show-reload-icon-toolbar=true

[preferences/menu-config]
selection-menu-make-link=true
EOL
    dconf load /org/nemo/ < "$work/nemo.conf"
  fi
  echo "Available application defaults and preferences configured. Backups: $backup"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
