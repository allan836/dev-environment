#!/usr/bin/env bash
# =============================================================================
# lib/providers/virtualbox.sh — VirtualBox installation and VM boot
#
# Requires: lib/log.sh, HOST_OS, VM_DIR, LOG_FILE
# =============================================================================

_install_virtualbox() {
  if has vboxmanage; then
    success "VirtualBox already installed: $(vboxmanage --version)"
    return 0
  fi

  info "Installing VirtualBox..."
  case "$HOST_OS" in
    mac)
      has brew || die "Homebrew required for VirtualBox install on macOS. See https://brew.sh"
      brew install --cask virtualbox 2>&1 | tee -a "$LOG_FILE"
      ;;
    ubuntu|debian)
      sudo apt-get update -qq 2>&1 | tee -a "$LOG_FILE"
      sudo apt-get install -y virtualbox 2>&1 | tee -a "$LOG_FILE" \
        || { warn "virtualbox package not found in default repos."; return 1; }
      ;;
    fedora|rhel)
      sudo dnf install -y VirtualBox 2>&1 | tee -a "$LOG_FILE" \
        || { warn "VirtualBox package not found via dnf."; return 1; }
      ;;
    *)
      warn "Cannot auto-install VirtualBox on '${HOST_OS}'."
      warn "Download from https://www.virtualbox.org/wiki/Downloads and re-run."
      return 1
      ;;
  esac

  if ! has vboxmanage; then
    warn "VirtualBox installation did not produce vboxmanage on PATH."
    return 1
  fi

  success "VirtualBox installed: $(vboxmanage --version)"
}

_ensure_vagrant_vbox_compat() {
  has vboxmanage || return 0
  has vagrant    || return 0

  local vbox_ver vbox_major vbox_minor
  vbox_ver=$(vboxmanage --version 2>/dev/null | grep -oP '^\d+\.\d+' || echo "0.0")
  vbox_major=$(echo "$vbox_ver" | cut -d. -f1)
  vbox_minor=$(echo "$vbox_ver" | cut -d. -f2)

  local vagrant_ver vagrant_major vagrant_minor
  vagrant_ver=$(vagrant --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
  vagrant_major=$(echo "$vagrant_ver" | cut -d. -f1)
  vagrant_minor=$(echo "$vagrant_ver" | cut -d. -f2)

  if [[ "$vbox_major" -ge 7 && "$vbox_minor" -ge 1 ]] \
     && [[ "$vagrant_major" -lt 2 || ( "$vagrant_major" -eq 2 && "$vagrant_minor" -lt 4 ) ]]; then
    warn "Vagrant ${vagrant_ver} does not support VirtualBox ${vbox_major}.${vbox_minor}."
    warn "Upgrading Vagrant to ${VAGRANT_INSTALL_VERSION}..."
    # shellcheck source=lib/dependencies.sh
    _install_vagrant_archive
    success "Vagrant upgraded: $(vagrant --version)"
  fi
}

# boot_virtualbox — installs VirtualBox (if needed) and boots the VM.
# Sets ACTIVE_PROVIDER on success.
boot_virtualbox() {
  info "Trying provider: VirtualBox"

  _install_virtualbox || return 1
  _ensure_vagrant_vbox_compat || true

  cd "$VM_DIR"
  if vagrant up --provider=virtualbox 2>&1 | tee -a "$LOG_FILE"; then
    ACTIVE_PROVIDER="virtualbox"
    export ACTIVE_PROVIDER
    return 0
  fi

  warn "VirtualBox boot failed."
  warn "  Why: VirtualBox could not start the VM. Common causes:"
  warn "       - Kernel modules not loaded (run: sudo modprobe vboxdrv)"
  warn "       - Secure Boot blocking kernel modules (disable in BIOS/UEFI)"
  warn "       - Insufficient disk space"
  warn "  Check ${LOG_FILE} for the full error."
  vagrant destroy -f 2>/dev/null || true
  return 1
}
