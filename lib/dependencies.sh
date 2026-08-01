#!/usr/bin/env bash
# =============================================================================
# lib/dependencies.sh — Host dependency installation
#
# Installs Vagrant on the host machine.
# Vagrant is the only host dependency beyond git and curl/wget.
#
# Requires:
#   lib/log.sh sourced
#   HOST_OS and PKG_MANAGER exported (from lib/detect.sh)
#   VAGRANT_MIN_VERSION and VAGRANT_INSTALL_VERSION from config.env
# =============================================================================

# --------------------------------------------------------------------------- #
# _vagrant_version_ok
# Returns 0 if the installed Vagrant meets the minimum version requirement.
# --------------------------------------------------------------------------- #
_vagrant_version_ok() {
  has vagrant || return 1

  local installed major minor
  installed=$(vagrant --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
  major=$(echo "$installed" | cut -d. -f1)
  minor=$(echo "$installed" | cut -d. -f2)
  local patch; patch=$(echo "$installed" | cut -d. -f3)

  local req_major req_minor req_patch
  req_major=$(echo "${VAGRANT_MIN_VERSION}" | cut -d. -f1)
  req_minor=$(echo "${VAGRANT_MIN_VERSION}" | cut -d. -f2)
  req_patch=$(echo "${VAGRANT_MIN_VERSION}" | cut -d. -f3)

  if [[ "$major" -gt "$req_major" ]]; then return 0; fi
  if [[ "$major" -eq "$req_major" && "$minor" -gt "$req_minor" ]]; then return 0; fi
  if [[ "$major" -eq "$req_major" && "$minor" -eq "$req_minor" && "$patch" -ge "$req_patch" ]]; then return 0; fi
  return 1
}

# --------------------------------------------------------------------------- #
# _install_vagrant_archive
# Downloads and installs a specific Vagrant release from HashiCorp.
# Used when the package-manager version is too old.
# --------------------------------------------------------------------------- #
_install_vagrant_archive() {
  local ver="${VAGRANT_INSTALL_VERSION}"
  local arch; arch="$(uname -m)"
  local pkg_arch="amd64"
  [[ "$arch" == "aarch64" || "$arch" == "arm64" ]] && pkg_arch="arm64"

  info "Downloading Vagrant ${ver} from HashiCorp releases..."

  case "$HOST_OS" in
    fedora|rhel)
      local rpm="vagrant-${ver}-1.${pkg_arch}.rpm"
      local url="https://releases.hashicorp.com/vagrant/${ver}/${rpm}"
      curl -fsSL "$url" -o "/tmp/${rpm}" \
        || die "Failed to download Vagrant RPM from ${url}"
      sudo rpm -Uvh "/tmp/${rpm}" 2>&1 | tee -a "$LOG_FILE"
      rm -f "/tmp/${rpm}"
      ;;
    mac)
      local dmg="vagrant_${ver}_darwin_${pkg_arch}.dmg"
      local url="https://releases.hashicorp.com/vagrant/${ver}/${dmg}"
      curl -fsSL "$url" -o "/tmp/${dmg}" \
        || die "Failed to download Vagrant DMG from ${url}"
      warn "Please open /tmp/${dmg} and run the installer, then press Enter."
      read -rp ""
      ;;
    *)
      local deb="vagrant_${ver}-1_${pkg_arch}.deb"
      local url="https://releases.hashicorp.com/vagrant/${ver}/${deb}"
      curl -fsSL "$url" -o "/tmp/${deb}" \
        || die "Failed to download Vagrant DEB from ${url}"
      sudo dpkg -i "/tmp/${deb}" 2>&1 | tee -a "$LOG_FILE"
      rm -f "/tmp/${deb}"
      ;;
  esac
}

# --------------------------------------------------------------------------- #
# ensure_vagrant
# Ensures Vagrant is installed and at least at VAGRANT_MIN_VERSION.
# --------------------------------------------------------------------------- #
ensure_vagrant() {
  banner "Installing host dependencies"

  if _vagrant_version_ok; then
    success "Vagrant $(vagrant --version) — meets minimum ${VAGRANT_MIN_VERSION}"
    return 0
  fi

  if has vagrant; then
    local installed; installed=$(vagrant --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
    warn "Vagrant ${installed} is below required minimum ${VAGRANT_MIN_VERSION}. Upgrading..."
  else
    info "Vagrant not found. Installing..."
  fi

  case "$HOST_OS" in
    mac)
      if ! has brew; then
        die "Homebrew is required on macOS. Install it from https://brew.sh then re-run."
      fi
      brew install --cask vagrant 2>&1 | tee -a "$LOG_FILE"
      if ! _vagrant_version_ok; then
        warn "Homebrew Vagrant may be below ${VAGRANT_MIN_VERSION}. Downloading directly..."
        _install_vagrant_archive
      fi
      ;;
    ubuntu|debian)
      sudo apt-get update -qq 2>&1 | tee -a "$LOG_FILE"
      sudo apt-get install -y vagrant 2>&1 | tee -a "$LOG_FILE"
      if ! _vagrant_version_ok; then
        warn "apt Vagrant is below ${VAGRANT_MIN_VERSION}. Downloading from HashiCorp..."
        _install_vagrant_archive
      fi
      ;;
    fedora|rhel)
      sudo dnf install -y vagrant 2>&1 | tee -a "$LOG_FILE"
      if ! _vagrant_version_ok; then
        warn "dnf Vagrant is below ${VAGRANT_MIN_VERSION}. Downloading from HashiCorp..."
        _install_vagrant_archive
      fi
      ;;
    linux_generic)
      _install_vagrant_archive
      ;;
    *)
      die "Cannot auto-install Vagrant on '${HOST_OS}'. Download from https://www.vagrantup.com/downloads and re-run."
      ;;
  esac

  if ! has vagrant; then
    die "Vagrant installation failed. Check ${LOG_FILE} for details."
  fi

  success "Vagrant $(vagrant --version) installed."
}
