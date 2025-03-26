#!/bin/bash

# Get default GNOME terminal profile ID
PROFILE_ID=$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d \')
PROFILE_PATH="/org/gnome/terminal/legacy/profiles:/:$PROFILE_ID"

### Configure GNOME Terminal ###

# Disable theme colors so custom ones apply
gsettings set ${PROFILE_PATH} use-theme-colors false

# Set custom font
gsettings set ${PROFILE_PATH} use-system-font false
gsettings set ${PROFILE_PATH} font 'Ubuntu Mono 12'

# Enable unlimited scrollback
gsettings set ${PROFILE_PATH} scrollback-unlimited true

# Set Solarized Dark palette
SOLARIZED_PALETTE="['#073642', '#dc322f', '#859900', '#b58900', '#268bd2', '#d33682', '#2aa198', '#eee8d5', '#002b36', '#cb4b16', '#586e75', '#657b83', '#839496', '#6c71c4', '#93a1a1', '#fdf6e3']"
gsettings set ${PROFILE_PATH} palette "$SOLARIZED_PALETTE"

# Set background and foreground
# Solarized Dark background and light green text (customized)
gsettings set ${PROFILE_PATH} background-color '#002b36'
gsettings set ${PROFILE_PATH} foreground-color '#aaff99'  # lighter green for text

# Set bold color same as foreground
gsettings set ${PROFILE_PATH} bold-color '#aaff99'
gsettings set ${PROFILE_PATH} bold-color-same-as-fg true

# Enable transparency (optional; 0.9 = 10% transparent)
gsettings set ${PROFILE_PATH} use-transparent-background true
gsettings set ${PROFILE_PATH} background-transparency-percent 10

# Set default terminal window size
gsettings set ${PROFILE_PATH} default-size-columns 135
gsettings set ${PROFILE_PATH} default-size-rows 35

### Set Default Applications ###
xdg-mime default org.gnome.TextEditor.desktop text/plain
xdg-mime default org.gnome.eog.desktop image/jpeg
xdg-mime default org.gnome.eog.desktop image/png
xdg-mime default org.gnome.eog.desktop image/gif
xdg-mime default vlc.desktop audio/mpeg
xdg-mime default vlc.desktop video/mp4
xdg-mime default evince.desktop application/pdf


set -e

echo "🖋 Applying Gedit settings..."

cat > gedit.conf <<EOL
[plugins]
active-plugins=['filebrowser', 'docinfo', 'sort', 'modelines', 'spell', 'openlinks', 'terminal']

[plugins/filebrowser]
root='file:///'
tree-view=true
virtual-root='file:///home/qortector/Desktop'

[preferences/editor]
display-line-numbers=false
scheme='solarized-dark'
wrap-last-split-mode='word'

[preferences/ui]
show-tabs-mode='auto'

[state/window]
bottom-panel-active-page='GeditTerminalPanel'
bottom-panel-size=140
side-panel-active-page='GeditWindowDocumentsPanel'
side-panel-size=200
size=(900, 700)
state=87168
EOL

echo "✅ Gedit preferences set."

echo "📁 Applying Nemo preferences using dconf..."
cat > nemo-settings.conf <<EON
[list-view]
default-column-order=['name', 'size', 'type', 'date_modified', 'date_created_with_time', 'date_accessed', 'date_created', 'detailed_type', 'group', 'where', 'mime_type', 'date_modified_with_time', 'octal_permissions', 'owner', 'permissions', 'selinux_context']
default-visible-columns=['name', 'size', 'type', 'date_modified', 'date_created', 'mime_type']

[preferences]
close-device-view-on-device-eject=true
confirm-move-to-trash=true
enable-delete=false
show-computer-icon-toolbar=true
show-home-icon-toolbar=true
show-new-folder-icon-toolbar=true
show-open-in-terminal-toolbar=true
show-reload-icon-toolbar=true
show-show-thumbnails-toolbar=true

[preferences/menu-config]
selection-menu-make-link=true

[window-state]
geometry='1248x743+115+53'
maximized=false
sidebar-bookmark-breakpoint=5
start-with-sidebar=true
EON

# Load into dconf
dconf load /org/nemo/ < nemo-settings.conf
dconf load /org/gnome/gedit/preferences/ < gedit.conf
rm -f nemo-settings.conf gedit.conf

echo "✅ Nemo preferences applied."

echo "🎉 Desktop configuration complete!"


# Optional: customize sidebar, sorting, etc. once exported with dconf

echo "✅ GNOME Terminal and application defaults configured."
echo "ℹ️  You can run 'dconf dump /org/nemo/' to export your current Nemo setup."
echo "   Then edit and apply with: dconf load /org/nemo/ < nemo-settings.conf"

