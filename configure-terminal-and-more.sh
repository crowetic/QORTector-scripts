#!/bin/bash

# Get default GNOME terminal profile ID
#PROFILE_ID=$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d \')
#PROFILE_PATH="/org/gnome/terminal/legacy/profiles:/:$PROFILE_ID"



### Set Default Applications ###
xdg-mime default org.gnome.TextEditor.desktop text/plain
xdg-mime default org.gnome.eog.desktop image/jpeg
xdg-mime default org.gnome.eog.desktop image/png
xdg-mime default org.gnome.eog.desktop image/gif
xdg-mime default vlc.desktop audio/mpeg
xdg-mime default vlc.desktop video/mp4
xdg-mime default evince.desktop application/pdf


set -e

cat > terminal.conf <<EOL
[:b1dcc9dd-5262-4d8d-a863-c897e6d979b9]
background-color='rgb(12,30,34)'
default-size-columns=135
default-size-rows=35
foreground-color='rgb(131,148,150)'
palette=['rgb(7,54,66)', 'rgb(220,50,47)', 'rgb(43,201,123)', 'rgb(181,137,0)', 'rgb(38,139,210)', 'rgb(211,54,130)', 'rgb(42,161,152)', 'rgb(238,232,213)', 'rgb(0,43,54)', 'rgb(203,75,22)', 'rgb(88,110,117)', 'rgb(101,123,131)', 'rgb(131,148,150)', 'rgb(108,113,196)', 'rgb(147,161,161)', 'rgb(253,246,227)']
use-theme-colors=false
EOL

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
dconf load /org/gnome/terminal/legacy/profiles:/ < terminal.conf
rm -f nemo-settings.conf gedit.conf terminal.conf

echo "✅ Nemo preferences applied."

echo "🎉 Desktop configuration complete!"


# Optional: customize sidebar, sorting, etc. once exported with dconf

echo "✅ GNOME Terminal and application defaults configured."
echo "ℹ️  You can run 'dconf dump /org/nemo/' to export your current Nemo setup."
echo "   Then edit and apply with: dconf load /org/nemo/ < nemo-settings.conf"

