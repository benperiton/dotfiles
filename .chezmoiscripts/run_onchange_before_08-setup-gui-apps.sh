#!/bin/bash
set -euo pipefail

echo "Setting up GUI apps via Flatpak..."

# Enable Flathub
if ! flatpak remotes | grep -q flathub; then
    echo "Adding Flathub repository"
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

FLATPAKS=(
    com.google.Chrome
    org.gimp.GIMP
    org.inkscape.Inkscape
    org.flameshot.Flameshot
    com.sublimetext.three
    org.libreoffice.LibreOffice
    org.filezillaproject.Filezilla
    com.usebruno.Bruno
    net.cozic.joplin_desktop
    org.remmina.Remmina
    com.github.tchx84.Flatseal
    io.github.martchus.syncthingtray
)

MISSING=()
for app in "${FLATPAKS[@]}"; do
    if ! flatpak info --user "$app" &>/dev/null && ! flatpak info --system "$app" &>/dev/null; then
        MISSING+=("$app")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "Installing: ${MISSING[*]}"
    sudo flatpak install -y flathub "${MISSING[@]}"
fi

echo "GUI apps configured"
