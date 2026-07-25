#!/usr/bin/env bash
# Installs core system tools: Git, Docker, GitHub CLI, OpenVPN, AWS CLI,
# Terraform, kubectl. Idempotent: each install is skipped if already present.
# Expects OS_FAMILY to be exported by setup.sh ("mac" or "fedora").
set -euo pipefail

: "${OS_FAMILY:?OS_FAMILY must be set (run via ./setup.sh)}"

has() { command -v "$1" >/dev/null 2>&1; }

install_mac() {
  if ! has brew; then
    echo "Error: Homebrew is required. Install it first: https://brew.sh" >&2
    exit 1
  fi

  xcode-select --install 2>/dev/null || echo "Xcode CLT already installed"
  softwareupdate --install-rosetta --agree-to-license 2>/dev/null || echo "Rosetta 2 already installed or not applicable"

  has git       || brew install git
  has gh        || brew install gh
  has terraform || brew install terraform
  has openvpn   || brew install openvpn
  has aws       || brew install awscli
  has kubectl   || brew install kubectl
  if ! [ -d "/Applications/Docker.app" ]; then
    brew install --cask docker
    echo "NOTE: open Docker Desktop once manually to finish setup and enable Kubernetes if needed."
  fi
  if ! has code; then
    brew install --cask visual-studio-code
  fi
}

install_fedora() {
  sudo dnf install -y git gh openvpn awscli
  has kubectl || sudo dnf install -y kubernetes-client

  if ! has terraform; then
    sudo dnf install -y dnf-plugins-core
    sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
    sudo dnf install -y terraform
  fi

  if ! has docker; then
    sudo dnf-3 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"
    echo "NOTE: log out and back in for the 'docker' group membership to take effect."
  fi

  if ! has code; then
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    sudo dnf config-manager --add-repo https://packages.microsoft.com/yumrepos/vscode
    sudo dnf install -y code
  fi
}

case "$OS_FAMILY" in
  mac)    install_mac ;;
  fedora) install_fedora ;;
  *)      echo "Unsupported OS_FAMILY: $OS_FAMILY" >&2; exit 1 ;;
esac

echo "Core tools install stage complete."
