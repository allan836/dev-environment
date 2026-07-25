#!/usr/bin/env bash
# Installs desktop/communication apps, best-effort per OS.
# On macOS: Homebrew casks cover nearly everything.
# On Fedora: dnf/Flatpak cover most; a few (FortiClient, Shottr, LICEcap)
# have no direct Fedora equivalent and are called out below instead of
# silently skipped.
#
# Optional: pass --with-local-dns on macOS to additionally set up the
# dnsmasq + nginx + /etc/resolver/test local ".test" TLD from the original
# onboarding doc. Not run by default — see docs/architecture.md#local-dns--https.
set -euo pipefail

: "${OS_FAMILY:?OS_FAMILY must be set (run via ./setup.sh)}"

install_mac_apps() {
  local casks=(
    forticlient lens obs shottr licecap inkscape gimp dbeaver-community
    libreoffice microsoft-teams zoom google-drive vlc openshot mongodb-compass
  )
  for c in "${casks[@]}"; do
    brew install --cask "$c" || echo "warning: failed to install cask '$c', skipping"
  done
  brew install --cask slack || echo "warning: failed to install slack, skipping"

  if [[ "${1:-}" == "--with-local-dns" ]]; then
    brew install dnsmasq
    echo "address=/.test/127.0.0.1" >> /opt/homebrew/etc/dnsmasq.conf
    sudo mkdir -pv /etc/resolver
    sudo bash -c 'echo "nameserver 127.0.0.1" > /etc/resolver/test'
    sudo brew services start dnsmasq
    echo "Local .test TLD enabled. If you lose internet access, delete /etc/resolver/test."
  fi
}

install_fedora_apps() {
  sudo dnf install -y slack obs-studio gimp inkscape libreoffice vlc dbeaver

  # Flatpak covers apps without native Fedora packages.
  if command -v flatpak >/dev/null 2>&1; then
    flatpak install -y flathub com.microsoft.Teams || echo "warning: MS Teams flatpak failed"
    flatpak install -y flathub us.zoom.Zoom || echo "warning: Zoom flatpak failed"
    flatpak install -y flathub com.mongodb.Compass || echo "warning: MongoDB Compass flatpak failed"
    flatpak install -y flathub org.openshot.OpenShot || echo "warning: OpenShot flatpak failed"
  else
    echo "warning: flatpak not available; skipping Teams/Zoom/Compass/OpenShot. Install flatpak first."
  fi

  echo "NOTE: no Fedora equivalent found for FortiClient, Shottr, LICEcap, Google Drive for Mac, Lens (use 'flatpak search lens' or the AppImage release)."
}

case "$OS_FAMILY" in
  mac)    install_mac_apps "$@" ;;
  fedora) install_fedora_apps ;;
  *)      echo "Unsupported OS_FAMILY: $OS_FAMILY" >&2; exit 1 ;;
esac

echo "Desktop apps install stage complete (best-effort)."
