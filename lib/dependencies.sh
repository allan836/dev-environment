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
# _vagrant_candidate_versions
# Emits an ordered list of Vagrant versions to try:
#   1. The version pinned in config.env (VAGRANT_INSTALL_VERSION)
#   2. The latest stable version from the HashiCorp checkpoint API
#   3. A small set of known-good fallback versions
# Duplicates are filtered out while preserving order.
# --------------------------------------------------------------------------- #
_vagrant_candidate_versions() {
  local candidates=()
  candidates+=("${VAGRANT_INSTALL_VERSION}")

  local checkpoint_ver
  checkpoint_ver=$(curl -fsSL --max-time 8 \
    "https://checkpoint-api.hashicorp.com/v1/check/vagrant" 2>/dev/null \
    | grep -oP '"current_version"\s*:\s*"\K[^"]+' || true)
  [[ -n "$checkpoint_ver" ]] && candidates+=("$checkpoint_ver")

  candidates+=("2.4.1" "2.4.0" "2.3.7")

  local seen=()
  for v in "${candidates[@]}"; do
    local dup=0
    for s in "${seen[@]:-}"; do [[ "$s" == "$v" ]] && dup=1 && break; done
    [[ $dup -eq 0 ]] && seen+=("$v") && echo "$v"
  done
}

# --------------------------------------------------------------------------- #
# _try_download
# Attempts to download $2 to $3 using curl.
# Returns 0 on success, 1 on any error (including HTTP 404).
# --------------------------------------------------------------------------- #
_try_download() {
  local label="$1" url="$2" dest="$3"
  info "  Trying ${label} → ${url}"
  if curl -fsSL --max-time 120 "$url" -o "$dest" 2>>"$LOG_FILE"; then
    return 0
  fi
  warn "  ✘ ${label} not available at that URL (404 or network error). Trying next..."
  rm -f "$dest"
  return 1
}

# --------------------------------------------------------------------------- #
# _install_vagrant_archive
# Downloads and installs a Vagrant release from HashiCorp.
# Tries multiple candidate versions in order; moves to the next on 404.
# --------------------------------------------------------------------------- #
_install_vagrant_archive() {
  local arch; arch="$(uname -m)"
  local pkg_arch="amd64"
  [[ "$arch" == "aarch64" || "$arch" == "arm64" ]] && pkg_arch="arm64"

  info "Resolving Vagrant download candidates..."
  local versions=()
  while IFS= read -r v; do versions+=("$v"); done < <(_vagrant_candidate_versions)

  local installed=false ver url dest

  case "$HOST_OS" in
    fedora|rhel)
      for ver in "${versions[@]}"; do
        dest="/tmp/vagrant-${ver}.rpm"
        url="https://releases.hashicorp.com/vagrant/${ver}/vagrant-${ver}-1.${pkg_arch}.rpm"
        if _try_download "Vagrant ${ver} RPM" "$url" "$dest"; then
          info "  Installing Vagrant ${ver} via rpm..."
          sudo rpm -Uvh "$dest" 2>&1 | tee -a "$LOG_FILE"
          rm -f "$dest"
          installed=true
          break
        fi
      done
      ;;
    mac)
      for ver in "${versions[@]}"; do
        dest="/tmp/vagrant-${ver}.dmg"
        url="https://releases.hashicorp.com/vagrant/${ver}/vagrant_${ver}_darwin_${pkg_arch}.dmg"
        if _try_download "Vagrant ${ver} DMG" "$url" "$dest"; then
          warn "Please open ${dest} and run the installer, then press Enter."
          read -rp ""
          installed=true
          break
        fi
      done
      ;;
    *)
      for ver in "${versions[@]}"; do
        dest="/tmp/vagrant-${ver}.deb"
        url="https://releases.hashicorp.com/vagrant/${ver}/vagrant_${ver}-1_${pkg_arch}.deb"
        if _try_download "Vagrant ${ver} DEB" "$url" "$dest"; then
          info "  Installing Vagrant ${ver} via dpkg..."
          sudo dpkg -i "$dest" 2>&1 | tee -a "$LOG_FILE"
          rm -f "$dest"
          installed=true
          break
        fi
      done
      ;;
  esac

  if [[ "$installed" != "true" ]]; then
    die "All Vagrant download candidates failed. Check ${LOG_FILE} or download manually from https://developer.hashicorp.com/vagrant/downloads"
  fi
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
