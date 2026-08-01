#!/usr/bin/env bash
# =============================================================================
# install-core.sh — Core system tools installation
#
# Installs: Git, Docker, GitHub CLI, AWS CLI, Terraform, kubectl
#
# Idempotent: each tool is skipped if already present.
# Requires OS_FAMILY to be exported by setup.sh.
# =============================================================================
set -euo pipefail

: "${OS_FAMILY:?OS_FAMILY must be set (run via ./setup.sh)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_ENV="$(cd "$SCRIPT_DIR/../.." && pwd)/config.env"
if [[ -f "$CONFIG_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_ENV"
fi

has() { command -v "$1" >/dev/null 2>&1; }

# --------------------------------------------------------------------------- #
# macOS
# --------------------------------------------------------------------------- #
_install_mac() {
  if ! has brew; then
    echo "Error: Homebrew is required. Install it from https://brew.sh" >&2
    exit 1
  fi

  xcode-select --install 2>/dev/null || echo "Xcode CLT already installed"
  softwareupdate --install-rosetta --agree-to-license 2>/dev/null || true

  has git       || brew install git
  has gh        || brew install gh
  has terraform || brew install terraform
  has aws       || brew install awscli
  has kubectl   || brew install kubectl
  has az        || brew install azure-cli

  if ! has gcloud; then
    brew install --cask google-cloud-sdk
  fi

  if ! [ -d "/Applications/Docker.app" ]; then
    brew install --cask docker
    echo "NOTE: open Docker Desktop once manually to finish setup."
  fi
}

# --------------------------------------------------------------------------- #
# Fedora / RHEL
# --------------------------------------------------------------------------- #
_install_fedora() {
  sudo dnf install -y git

  if ! has gh; then
    sudo dnf install -y gh 2>/dev/null \
      || { sudo dnf install -y 'dnf-command(config-manager)' \
             && sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo \
             && sudo dnf install -y gh; }
  fi

  if ! has aws; then
    local arch; arch="$(uname -m)"
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${arch}.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp/awscliv2
    sudo /tmp/awscliv2/aws/install
    rm -rf /tmp/awscliv2 /tmp/awscliv2.zip
  fi

  if ! has terraform; then
    sudo dnf install -y dnf-plugins-core
    sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
    sudo dnf install -y terraform
  fi

  if ! has kubectl; then
    _install_kubectl_apt_or_direct "dnf"
  fi

  if ! has docker; then
    sudo dnf-3 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null \
      || sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"
    echo "NOTE: log out and back in for docker group to take effect."
  fi

  if ! has az; then
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    sudo dnf install -y 'dnf-command(config-manager)'
    sudo dnf config-manager --add-repo https://packages.microsoft.com/yumrepos/azure-cli
    sudo dnf install -y azure-cli
  fi

  if ! has gcloud; then
    sudo tee /etc/yum.repos.d/google-cloud-sdk.repo <<'EOF'
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
    sudo dnf install -y google-cloud-cli
  fi
}

# --------------------------------------------------------------------------- #
# Ubuntu / Debian
# --------------------------------------------------------------------------- #
_install_ubuntu_debian() {
  sudo apt-get update -qq
  sudo apt-get install -y git curl wget gnupg ca-certificates lsb-release apt-transport-https unzip

  # GitHub CLI
  if ! has gh; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
      https://cli.github.com/packages stable main" \
      | sudo tee /etc/apt/sources.list.d/github-cli.list
    sudo apt-get update -qq
    sudo apt-get install -y gh
  fi

  # AWS CLI v2
  if ! has aws; then
    local arch; arch="$(uname -m)"
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${arch}.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp/awscliv2
    sudo /tmp/awscliv2/aws/install
    rm -rf /tmp/awscliv2 /tmp/awscliv2.zip
  fi

  # Terraform
  if ! has terraform; then
    curl -fsSL https://apt.releases.hashicorp.com/gpg \
      | gpg --dearmor \
      | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
      https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
      | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt-get update -qq
    sudo apt-get install -y terraform
  fi

  # kubectl
  if ! has kubectl; then
    local channel="${KUBECTL_CHANNEL:-v1.30}"
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/${channel}/deb/Release.key" \
      | gpg --dearmor \
      | sudo tee /etc/apt/keyrings/kubernetes-apt-keyring.gpg >/dev/null
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
      https://pkgs.k8s.io/core:/stable:/${channel}/deb/ /" \
      | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update -qq
    sudo apt-get install -y kubectl
  fi

  # Docker
  if ! has docker; then
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor \
      | sudo tee /etc/apt/keyrings/docker.gpg >/dev/null
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list
    sudo apt-get update -qq
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"
    echo "NOTE: log out and back in for docker group to take effect."
  fi

  # Azure CLI
  if ! has az; then
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | gpg --dearmor \
      | sudo tee /etc/apt/keyrings/microsoft.gpg >/dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] \
      https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" \
      | sudo tee /etc/apt/sources.list.d/azure-cli.list
    sudo apt-get update -qq
    sudo apt-get install -y azure-cli
  fi

  # Google Cloud CLI
  if ! has gcloud; then
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
      | gpg --dearmor \
      | sudo tee /usr/share/keyrings/cloud.google.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] \
      https://packages.cloud.google.com/apt cloud-sdk main" \
      | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
    sudo apt-get update -qq
    sudo apt-get install -y google-cloud-cli
  fi
}

# --------------------------------------------------------------------------- #
# Dispatch
# --------------------------------------------------------------------------- #
case "$OS_FAMILY" in
  mac)            _install_mac ;;
  fedora|rhel)    _install_fedora ;;
  ubuntu|debian)  _install_ubuntu_debian ;;
  *)
    echo "Error: Unsupported OS_FAMILY: $OS_FAMILY" >&2
    exit 1
    ;;
esac

echo "==> Core tools install complete."
