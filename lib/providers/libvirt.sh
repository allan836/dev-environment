#!/usr/bin/env bash
# =============================================================================
# lib/providers/libvirt.sh — KVM/libvirt installation and VM boot
#
# Requires: lib/log.sh, HOST_OS, VM_DIR, LOG_FILE
# =============================================================================

_install_libvirt() {
  if has virsh; then
    success "KVM/libvirt already installed"
    return 0
  fi

  if [[ "${HOST_OS}" == "mac" ]]; then
    warn "KVM/libvirt is Linux-only and cannot run on macOS."
    return 1
  fi

  info "Installing KVM/libvirt..."
  case "$HOST_OS" in
    ubuntu|debian)
      sudo apt-get update -qq 2>&1 | tee -a "$LOG_FILE"
      sudo apt-get install -y \
        qemu-kvm libvirt-daemon-system libvirt-clients \
        bridge-utils cpu-checker 2>&1 | tee -a "$LOG_FILE"
      sudo adduser "$USER" libvirt 2>/dev/null || true
      sudo adduser "$USER" kvm    2>/dev/null || true
      sudo systemctl enable --now libvirtd 2>&1 | tee -a "$LOG_FILE"
      ;;
    fedora|rhel)
      sudo dnf install -y @virtualization 2>&1 | tee -a "$LOG_FILE"
      sudo systemctl enable --now libvirtd 2>&1 | tee -a "$LOG_FILE"
      sudo usermod -aG libvirt "$USER"
      sudo usermod -aG kvm    "$USER"
      ;;
    *)
      warn "Cannot auto-install KVM/libvirt on '${HOST_OS}'."
      return 1
      ;;
  esac

  if ! has virsh; then
    warn "KVM/libvirt installation did not produce virsh on PATH."
    return 1
  fi

  success "KVM/libvirt installed"
}

_install_vagrant_libvirt_plugin() {
  if vagrant plugin list 2>/dev/null | grep -q "vagrant-libvirt"; then
    success "vagrant-libvirt plugin already installed"
    return 0
  fi

  info "Installing vagrant-libvirt plugin..."
  case "$HOST_OS" in
    ubuntu|debian)
      sudo apt-get install -y libvirt-dev ruby-dev build-essential 2>&1 | tee -a "$LOG_FILE"
      ;;
    fedora|rhel)
      sudo dnf install -y libvirt-devel ruby-devel gcc make 2>&1 | tee -a "$LOG_FILE"
      ;;
  esac

  vagrant plugin install vagrant-libvirt 2>&1 | tee -a "$LOG_FILE"
}

# boot_libvirt — installs KVM/libvirt (if needed) and boots the VM.
# Sets ACTIVE_PROVIDER on success.
boot_libvirt() {
  info "Trying provider: KVM/libvirt"

  if [[ "${HOST_OS}" == "mac" ]]; then
    warn "KVM/libvirt is not available on macOS. Skipping."
    return 1
  fi

  # Verify hardware virtualisation support
  if ! grep -qE 'vmx|svm' /proc/cpuinfo 2>/dev/null; then
    warn "CPU does not appear to support hardware virtualisation."
    warn "  Why: KVM requires Intel VT-x or AMD-V."
    warn "  Fix: Enable virtualisation in your BIOS/UEFI settings."
    return 1
  fi

  _install_libvirt          || return 1
  _install_vagrant_libvirt_plugin || return 1

  cd "$VM_DIR"
  if vagrant up --provider=libvirt 2>&1 | tee -a "$LOG_FILE"; then
    ACTIVE_PROVIDER="libvirt"
    export ACTIVE_PROVIDER
    return 0
  fi

  warn "KVM/libvirt boot failed."
  warn "  Why: Common causes include missing kernel modules, permission issues,"
  warn "       or a conflicting libvirt network."
  warn "  Check ${LOG_FILE} for details."
  vagrant destroy -f 2>/dev/null || true
  return 1
}
