#!/usr/bin/env bash
# =============================================================================
# lib/dependencies.sh — Host provider installation
#
# Installs the selected virtualization provider (multipass, libvirt, or incus)
# on the host machine. Each provider's install function tries its primary
# package-manager path first; on failure (or if the binary is absent after
# install), it tries alternative download sources in order.
#
# Requires:
#   lib/log.sh sourced
#   HOST_OS, PKG_MANAGER, HOST_ARCH exported (from lib/detect.sh)
#   SELECTED_PROVIDER exported
# =============================================================================

# --------------------------------------------------------------------------- #
# _try_download
# curl-downloads $2 → $3; warns and returns 1 on any error (including 404).
# --------------------------------------------------------------------------- #
_try_download() {
  local label="$1" url="$2" dest="$3"
  info "  Trying ${label} → ${url}"
  if curl -fsSL --max-time 180 "$url" -o "$dest" 2>>"$LOG_FILE"; then
    return 0
  fi
  warn "  ✘ ${label} unavailable (404 or network error). Trying next..."
  rm -f "$dest"
  return 1
}

# =========================================================================== #
# MULTIPASS
# =========================================================================== #

# --------------------------------------------------------------------------- #
# _multipass_snap_candidates
# Returns snap channel candidates to try in order.
# --------------------------------------------------------------------------- #
_multipass_snap_candidates() {
  echo "stable"
  echo "candidate"
  echo "beta"
}

# --------------------------------------------------------------------------- #
# _install_multipass_linux
# Tries snap first (universal), then distro package, then direct deb/rpm.
# --------------------------------------------------------------------------- #
_install_multipass_linux() {
  if has snap; then
    info "Installing Multipass via snap..."
    while IFS= read -r channel; do
      info "  Trying snap channel: ${channel}"
      if sudo snap install multipass --channel="${channel}/linux" 2>>"$LOG_FILE"; then
        return 0
      fi
      warn "  ✘ snap channel ${channel} failed. Trying next..."
    done < <(_multipass_snap_candidates)
  fi

  case "$PKG_MANAGER" in
    apt)
      info "Installing Multipass via apt..."
      sudo apt-get update -qq 2>>"$LOG_FILE"
      if sudo apt-get install -y multipass 2>>"$LOG_FILE"; then
        has multipass && return 0
      fi
      warn "apt install failed. Attempting direct .deb download..."
      local ver
      ver=$(curl -fsSL --max-time 8 \
        "https://api.github.com/repos/canonical/multipass/releases/latest" \
        2>/dev/null | grep -oP '"tag_name":\s*"v\K[^"]+' || echo "")
      [[ -z "$ver" ]] && die "Cannot resolve latest Multipass release."
      local pkg="multipass_${ver}_linux_${HOST_ARCH}.deb"
      local url="https://github.com/canonical/multipass/releases/download/v${ver}/${pkg}"
      _try_download "Multipass ${ver} deb" "$url" "/tmp/${pkg}" \
        && sudo dpkg -i "/tmp/${pkg}" 2>&1 | tee -a "$LOG_FILE" \
        && rm -f "/tmp/${pkg}" \
        && return 0
      ;;
    dnf)
      info "Installing Multipass via snap (snap is the canonical path on Fedora/RHEL)..."
      local _snapd_freshly_installed=false
      if ! has snap; then
        sudo dnf install -y snapd 2>>"$LOG_FILE" || true
        sudo systemctl enable --now snapd.socket 2>>"$LOG_FILE" || true
        sudo ln -sf /var/lib/snapd/snap /snap 2>/dev/null || true
        _snapd_freshly_installed=true
      fi
      # Verify snap daemon is responsive; on Fedora a fresh snapd install
      # requires a reboot for SELinux policy and the socket to fully initialize.
      if ! snap list &>/dev/null; then
        if [[ "$_snapd_freshly_installed" == "true" ]]; then
          _prompt_reboot "snapd was just installed on Fedora/RHEL and requires a reboot before snap packages can be used."
        else
          warn "snap daemon is not responding. A reboot may be needed."
        fi
      fi
      while IFS= read -r channel; do
        info "  Trying snap channel: ${channel}"
        if sudo snap install multipass --channel="${channel}/linux" 2>>"$LOG_FILE"; then
          return 0
        fi
        warn "  ✘ snap channel ${channel} failed. Trying next..."
      done < <(_multipass_snap_candidates)
      ;;
  esac

  die "Could not install Multipass. See ${LOG_FILE}. Manual install: https://multipass.run/install"
}

# --------------------------------------------------------------------------- #
# _install_multipass_mac
# Uses Homebrew cask; falls back to direct .pkg download.
# --------------------------------------------------------------------------- #
_install_multipass_mac() {
  if has brew; then
    info "Installing Multipass via Homebrew..."
    if brew install --cask multipass 2>&1 | tee -a "$LOG_FILE"; then
      has multipass && return 0
    fi
    warn "Homebrew install failed. Trying direct .pkg download..."
  fi

  local ver
  ver=$(curl -fsSL --max-time 8 \
    "https://api.github.com/repos/canonical/multipass/releases/latest" \
    2>/dev/null | grep -oP '"tag_name":\s*"v\K[^"]+' || echo "")
  [[ -z "$ver" ]] && die "Cannot resolve latest Multipass release."

  local arch_label="x86_64"
  [[ "$HOST_ARCH" == "arm64" ]] && arch_label="arm64"
  local pkg="multipass-${ver}+mac-Darwin-${arch_label}.pkg"
  local url="https://github.com/canonical/multipass/releases/download/v${ver}/${pkg}"

  _try_download "Multipass ${ver} pkg" "$url" "/tmp/${pkg}" \
    || die "All Multipass download candidates failed."
  warn "Please open /tmp/${pkg} and run the macOS installer, then press Enter."
  read -rp ""
}

# --------------------------------------------------------------------------- #
# ensure_multipass
# --------------------------------------------------------------------------- #
ensure_multipass() {
  if has multipass; then
    success "Multipass $(multipass version 2>/dev/null | head -n1 | awk '{print $2}') already installed."
    return 0
  fi

  info "Multipass not found. Installing..."
  case "$HOST_OS" in
    mac)           _install_multipass_mac   ;;
    ubuntu|debian) _install_multipass_linux ;;
    fedora|rhel)   _install_multipass_linux ;;
    linux_generic) _install_multipass_linux ;;
    *) die "Cannot auto-install Multipass on '${HOST_OS}'. Install from https://multipass.run/install" ;;
  esac

  has multipass || die "Multipass installation failed. Check ${LOG_FILE}."
  success "Multipass installed: $(multipass version 2>/dev/null | head -n1)"
}

# =========================================================================== #
# LIBVIRT
# =========================================================================== #

# --------------------------------------------------------------------------- #
# ensure_libvirt
# Installs KVM/libvirt and supporting tools (cloud-image-utils, virt-install).
# --------------------------------------------------------------------------- #
ensure_libvirt() {
  if has virsh && has virt-install; then
    success "KVM/libvirt already installed."
    return 0
  fi

  info "Installing KVM/libvirt..."

  case "$PKG_MANAGER" in
    apt)
      sudo apt-get update -qq 2>>"$LOG_FILE"
      sudo apt-get install -y \
        qemu-kvm libvirt-daemon-system libvirt-clients \
        virt-install cloud-image-utils genisoimage \
        bridge-utils cpu-checker 2>&1 | tee -a "$LOG_FILE"
      ;;
    dnf)
      sudo dnf install -y @virtualization \
        virt-install cloud-utils genisoimage 2>&1 | tee -a "$LOG_FILE"
      ;;
    *)
      die "Cannot auto-install libvirt on '${HOST_OS}'. Install qemu-kvm, libvirt, virt-install manually."
      ;;
  esac

  sudo systemctl enable --now libvirtd 2>>"$LOG_FILE" || true
  sudo usermod -aG libvirt,kvm "${USER}" 2>/dev/null || true

  has virsh || die "libvirt installation failed. Check ${LOG_FILE}."
  success "KVM/libvirt installed."

  # Group membership (libvirt, kvm) only takes effect after a new login session.
  # A reboot is the most reliable way to ensure KVM modules are also fully loaded.
  _prompt_reboot "KVM/libvirt was just installed. A reboot is needed so that kernel modules load and your user gains libvirt/kvm group access."
}

# =========================================================================== #
# INCUS
# =========================================================================== #

# --------------------------------------------------------------------------- #
# _incus_zabbly_install
# Installs Incus from the Zabbly repository (official upstream packages).
# --------------------------------------------------------------------------- #
_incus_zabbly_install() {
  info "  Trying Zabbly repository..."
  local script_url="https://pkgs.zabbly.com/get/incus-stable"
  local script="/tmp/get-incus-stable.sh"
  if _try_download "Incus Zabbly installer" "$script_url" "$script"; then
    sudo bash "$script" 2>&1 | tee -a "$LOG_FILE"
    rm -f "$script"
    has incus && return 0
  fi
  return 1
}

# --------------------------------------------------------------------------- #
# ensure_incus
# --------------------------------------------------------------------------- #
ensure_incus() {
  if has incus; then
    success "Incus $(incus version 2>/dev/null | head -n1) already installed."
    return 0
  fi

  info "Incus not found. Installing..."

  case "$PKG_MANAGER" in
    apt)
      sudo apt-get update -qq 2>>"$LOG_FILE"
      info "  Trying apt install..."
      if sudo apt-get install -y incus 2>>"$LOG_FILE"; then
        has incus && { success "Incus installed."; return 0; }
      fi
      warn "  ✘ apt package not found. Trying Zabbly repo..."
      _incus_zabbly_install && return 0
      ;;
    dnf)
      info "  Trying dnf install..."
      if sudo dnf install -y incus 2>>"$LOG_FILE"; then
        has incus && { success "Incus installed."; return 0; }
      fi
      warn "  ✘ dnf package not found. Trying Zabbly repo..."
      _incus_zabbly_install && return 0
      ;;
    *)
      _incus_zabbly_install && return 0
      die "Cannot auto-install Incus on '${HOST_OS}'. Install from https://linuxcontainers.org/incus/docs/main/installing/"
      ;;
  esac

  has incus || die "Incus installation failed. Check ${LOG_FILE}."
  success "Incus installed."

  # The incus group is added during install; membership requires a new session.
  _prompt_reboot "Incus was just installed. A reboot is needed so your user gains incus group access."
}

# =========================================================================== #
# DISPATCHER
# =========================================================================== #

# --------------------------------------------------------------------------- #
# ensure_provider
# Installs the provider tool selected by detect.sh.
# Called from provision.sh step 2.
# --------------------------------------------------------------------------- #
ensure_provider() {
  banner "Installing provider: ${SELECTED_PROVIDER}"

  case "$SELECTED_PROVIDER" in
    multipass) ensure_multipass ;;
    libvirt)   ensure_libvirt   ;;
    incus)     ensure_incus     ;;
    *)
      die "Unknown provider '${SELECTED_PROVIDER}'. Valid: multipass, libvirt, incus."
      ;;
  esac
}
