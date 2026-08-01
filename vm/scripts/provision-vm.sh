#!/usr/bin/env bash
# provision-vm.sh — Runs INSIDE the VM on first boot.
#
# Called by the Vagrantfile's shell provisioner (before Ansible takes over).
# Responsibility: get the VM to a state where Ansible can run.
#   - apt cache is fresh
#   - Ansible and Python are installed
#   - Directory structure exists
#   - Vagrant user can sudo without password
#
# Everything beyond this (Docker, Java, Node, Terraform, etc.) is Ansible's job.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "==> [provision-vm.sh] Starting first-boot shell setup inside VM..."

# ---- Apt ------------------------------------------------------------------
echo "==> Updating apt cache..."
apt-get update -qq

echo "==> Installing base dependencies..."
apt-get install -y \
  git \
  curl \
  wget \
  python3 \
  python3-pip \
  python3-venv \
  ansible \
  ca-certificates \
  gnupg \
  lsb-release \
  apt-transport-https \
  software-properties-common \
  unzip \
  jq \
  vim \
  net-tools \
  bash-completion \
  2>&1 | tail -10

# ---- Sudoers --------------------------------------------------------------
echo "==> Ensuring vagrant user has passwordless sudo..."
echo "vagrant ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vagrant
chmod 0440 /etc/sudoers.d/vagrant

# ---- Workspace directory --------------------------------------------------
echo "==> Creating workspace directory structure..."
sudo -u vagrant mkdir -p /home/vagrant/workspace/repos

# ---- Hostname -------------------------------------------------------------
echo "==> Setting hostname..."
hostnamectl set-hostname dev-env 2>/dev/null || true

# ---- Timezone -------------------------------------------------------------
echo "==> Setting timezone..."
timedatectl set-timezone Africa/Johannesburg 2>/dev/null || true

echo "==> [provision-vm.sh] First-boot setup complete."
echo "    Ansible will now install all developer tools."
