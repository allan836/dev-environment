#!/usr/bin/env bash
# =============================================================================
# lib/providers/vmware.sh — VMware Workstation/Fusion and VM boot
#
# VMware requires a paid licence and cannot be downloaded automatically.
# This module only installs the Vagrant plugin and utility daemon.
#
# Requires: lib/log.sh, HOST_OS, VM_DIR, LOG_FILE, VMWARE_UTILITY_VERSION
# =============================================================================

_check_vmware_installed() {
  has vmware || has vmrun || return 1
  return 0
}

_install_vagrant_vmware_plugin() {
  if vagrant plugin list 2>/dev/null | grep -q "vagrant-vmware-desktop"; then
    success "vagrant-vmware-desktop plugin already installed"
    return 0
  fi

  info "Installing vagrant-vmware-desktop plugin..."
  vagrant plugin install vagrant-vmware-desktop 2>&1 | tee -a "$LOG_FILE"
}

_install_vmware_utility() {
  local ver="${VMWARE_UTILITY_VERSION}"
  local arch; arch="$(uname -m)"
  local pkg_arch="amd64"
  [[ "$arch" == "aarch64" || "$arch" == "arm64" ]] && pkg_arch="arm64"
  local base="https://releases.hashicorp.com/vagrant-vmware-utility/${ver}"

  if systemctl is-active --quiet vagrant-vmware-utility 2>/dev/null; then
    success "vagrant-vmware-utility service already running"
    return 0
  fi

  info "Installing Vagrant VMware Utility ${ver}..."
  case "$HOST_OS" in
    ubuntu|debian)
      local deb="vagrant-vmware-utility_${ver}-1_${pkg_arch}.deb"
      curl -fsSL "${base}/${deb}" -o "/tmp/${deb}" \
        || { warn "Failed to download VMware utility DEB."; return 1; }
      sudo dpkg -i "/tmp/${deb}" 2>&1 | tee -a "$LOG_FILE"
      rm -f "/tmp/${deb}"
      ;;
    fedora|rhel)
      local rpm="vagrant-vmware-utility_${ver}_${pkg_arch}.rpm"
      curl -fsSL "${base}/${rpm}" -o "/tmp/${rpm}" \
        || { warn "Failed to download VMware utility RPM."; return 1; }
      sudo rpm -i "/tmp/${rpm}" 2>&1 | tee -a "$LOG_FILE"
      rm -f "/tmp/${rpm}"
      ;;
    mac)
      local dmg="vagrant-vmware-utility_${ver}_darwin_${pkg_arch}.dmg"
      curl -fsSL "${base}/${dmg}" -o "/tmp/${dmg}" \
        || { warn "Failed to download VMware utility DMG."; return 1; }
      warn "Please mount /tmp/${dmg} and run the installer, then press Enter."
      read -rp ""
      ;;
  esac

  sudo systemctl enable --now vagrant-vmware-utility 2>/dev/null || true
}

# boot_vmware — verifies VMware is installed and boots the VM.
# Sets ACTIVE_PROVIDER on success.
boot_vmware() {
  info "Trying provider: VMware"

  if ! _check_vmware_installed; then
    warn "VMware Workstation (Linux) or VMware Fusion (macOS) is not detected."
    warn "  Why: VMware requires a paid licence and cannot be downloaded automatically."
    warn "  Fix:"
    warn "    Linux: Install VMware Workstation from https://www.vmware.com/products/desktop-hypervisor.html"
    warn "    macOS: Install VMware Fusion      from https://www.vmware.com/products/fusion.html"
    warn "  After installing, re-run ./provision.sh"
    return 1
  fi

  _install_vagrant_vmware_plugin || return 1
  _install_vmware_utility        || return 1

  cd "$VM_DIR"
  if vagrant up --provider=vmware_desktop 2>&1 | tee -a "$LOG_FILE"; then
    ACTIVE_PROVIDER="vmware_desktop"
    export ACTIVE_PROVIDER
    return 0
  fi

  warn "VMware boot failed."
  warn "  Check ${LOG_FILE} for details."
  vagrant destroy -f 2>/dev/null || true
  return 1
}
