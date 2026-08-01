#!/usr/bin/env bash
# =============================================================================
# lib/detect.sh — Host OS and hypervisor detection
#
# Exports:
#   HOST_OS         — mac | ubuntu | debian | fedora | linux_generic | unknown
#   PKG_MANAGER     — brew | apt | dnf | unknown
#   AVAILABLE_PROVIDERS — space-separated list of detected providers
#   SELECTED_PROVIDER   — the provider chosen for this run
#
# Source this file; do not execute it directly.
# =============================================================================

# Requires lib/log.sh to be sourced first.

# --------------------------------------------------------------------------- #
# detect_host_os
# Sets HOST_OS and PKG_MANAGER based on the running operating system.
# --------------------------------------------------------------------------- #
detect_host_os() {
  banner "Detecting host"

  if [[ "${OSTYPE:-}" == darwin* ]]; then
    HOST_OS="mac"
    PKG_MANAGER="brew"
  elif [[ -f /etc/fedora-release ]]; then
    HOST_OS="fedora"
    PKG_MANAGER="dnf"
  elif [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}:${ID_LIKE:-}" in
      ubuntu:*|*:*ubuntu*) HOST_OS="ubuntu"; PKG_MANAGER="apt" ;;
      debian:*|*:*debian*) HOST_OS="debian"; PKG_MANAGER="apt" ;;
      rhel:*|centos:*|*:*rhel*)
        HOST_OS="rhel"; PKG_MANAGER="dnf" ;;
      *) HOST_OS="linux_generic"; PKG_MANAGER="unknown" ;;
    esac
  else
    HOST_OS="unknown"
    PKG_MANAGER="unknown"
  fi

  export HOST_OS PKG_MANAGER
  success "Host OS: ${HOST_OS}"
}

# --------------------------------------------------------------------------- #
# _probe_virtualbox
# Returns:
#   0 — installed and compatible
#   1 — not installed
#   2 — installed but Vagrant version is incompatible (VirtualBox 7.1+ needs Vagrant 2.4+)
# --------------------------------------------------------------------------- #
_probe_virtualbox() {
  has vboxmanage || return 1

  local vbox_ver vbox_major vbox_minor
  vbox_ver=$(vboxmanage --version 2>/dev/null | grep -oP '^\d+\.\d+' || echo "0.0")
  vbox_major=$(echo "$vbox_ver" | cut -d. -f1)
  vbox_minor=$(echo "$vbox_ver" | cut -d. -f2)

  if has vagrant; then
    local vagrant_ver vagrant_major vagrant_minor
    vagrant_ver=$(vagrant --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
    vagrant_major=$(echo "$vagrant_ver" | cut -d. -f1)
    vagrant_minor=$(echo "$vagrant_ver" | cut -d. -f2)

    # VirtualBox 7.1+ requires Vagrant 2.4.0+
    if [[ "$vbox_major" -ge 7 && "$vbox_minor" -ge 1 ]] \
       && [[ "$vagrant_major" -lt 2 || ( "$vagrant_major" -eq 2 && "$vagrant_minor" -lt 4 ) ]]; then
      return 2
    fi
  fi

  return 0
}

_probe_libvirt() {
  [[ "${HOST_OS}" == "mac" ]] && return 1
  has virsh || return 1
  return 0
}

_probe_vmware() {
  has vmware || has vmrun || return 1
  return 0
}

# --------------------------------------------------------------------------- #
# detect_providers
# Probes each provider in PROVIDER_PRIORITY and populates AVAILABLE_PROVIDERS.
# --------------------------------------------------------------------------- #
detect_providers() {
  banner "Checking virtualization"
  AVAILABLE_PROVIDERS=()
  local rc label

  for backend in "${PROVIDER_PRIORITY[@]}"; do
    case "$backend" in
      virtualbox)
        _probe_virtualbox; rc=$?
        if [[ $rc -eq 0 ]]; then
          label="VirtualBox $(vboxmanage --version 2>/dev/null | head -n1) — compatible"
          success "$label"
          AVAILABLE_PROVIDERS+=("virtualbox")
        elif [[ $rc -eq 2 ]]; then
          label="VirtualBox $(vboxmanage --version 2>/dev/null | head -n1) — Vagrant too old (will upgrade automatically)"
          warn "$label"
          AVAILABLE_PROVIDERS+=("virtualbox")
        else
          warn "VirtualBox — not installed"
        fi
        ;;
      libvirt)
        _probe_libvirt; rc=$?
        if [[ $rc -eq 0 ]]; then
          label="KVM/libvirt $(virsh --version 2>/dev/null | head -n1) — compatible"
          success "$label"
          AVAILABLE_PROVIDERS+=("libvirt")
        else
          warn "KVM/libvirt — not installed"
        fi
        ;;
      vmware_desktop)
        _probe_vmware; rc=$?
        if [[ $rc -eq 0 ]]; then
          success "VMware — detected"
          AVAILABLE_PROVIDERS+=("vmware_desktop")
        else
          warn "VMware — not installed"
        fi
        ;;
    esac
  done

  export AVAILABLE_PROVIDERS
}

# --------------------------------------------------------------------------- #
# select_provider
# Picks the first available provider (priority order).
# Sets SELECTED_PROVIDER.
# If no provider is installed, defaults to "virtualbox" (will be auto-installed).
# --------------------------------------------------------------------------- #
select_provider() {
  if [[ ${#AVAILABLE_PROVIDERS[@]} -eq 0 ]]; then
    warn "No hypervisor detected. Will attempt to install VirtualBox automatically."
    SELECTED_PROVIDER="virtualbox"
    export SELECTED_PROVIDER
    return 0
  fi

  SELECTED_PROVIDER="${AVAILABLE_PROVIDERS[0]}"
  export SELECTED_PROVIDER
  info "Selected provider: ${_BOLD}${SELECTED_PROVIDER}${_RESET}"
}
