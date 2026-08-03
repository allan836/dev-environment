#!/usr/bin/env bash
# =============================================================================
# lib/detect.sh — Host OS and virtualization provider detection
#
# Exports:
#   HOST_OS             — mac | ubuntu | debian | fedora | rhel | linux_generic
#   PKG_MANAGER         — brew | apt | dnf | unknown
#   HOST_ARCH           — amd64 | arm64
#   AVAILABLE_PROVIDERS — array of detected / installable providers
#   SELECTED_PROVIDER   — the provider chosen for this run
#
# Provider probe order comes from PROVIDER_PRIORITY (set in provision.sh).
# Source this file; do not execute it directly.
# =============================================================================

# --------------------------------------------------------------------------- #
# detect_host_os
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
      ubuntu:*|*:*ubuntu*) HOST_OS="ubuntu";       PKG_MANAGER="apt" ;;
      debian:*|*:*debian*) HOST_OS="debian";       PKG_MANAGER="apt" ;;
      rhel:*|centos:*|*:*rhel*)
                           HOST_OS="rhel";         PKG_MANAGER="dnf" ;;
      *)                   HOST_OS="linux_generic"; PKG_MANAGER="unknown" ;;
    esac
  else
    HOST_OS="unknown"
    PKG_MANAGER="unknown"
  fi

  local raw_arch; raw_arch="$(uname -m)"
  case "$raw_arch" in
    aarch64|arm64) HOST_ARCH="arm64" ;;
    *)             HOST_ARCH="amd64" ;;
  esac

  export HOST_OS PKG_MANAGER HOST_ARCH
  success "Host OS: ${HOST_OS} (${HOST_ARCH})"
}

# --------------------------------------------------------------------------- #
# _probe_multipass
# Returns 0 if multipass is installed (or macOS where it is auto-installable).
# Returns 1 if not present and host cannot install it.
# --------------------------------------------------------------------------- #
_probe_multipass() {
  if has multipass; then
    return 0
  fi
  # Multipass is installable on macOS and Linux via snap or package manager
  case "$HOST_OS" in
    mac|ubuntu|debian|fedora|rhel|linux_generic) return 0 ;;
    *) return 1 ;;
  esac
}

# --------------------------------------------------------------------------- #
# _probe_libvirt
# Returns 0 if KVM/libvirt is installed or installable on this Linux host.
# Returns 1 on macOS (not supported) or missing hardware virtualisation.
# --------------------------------------------------------------------------- #
_probe_libvirt() {
  [[ "$HOST_OS" == "mac" ]] && return 1

  # Require hardware virtualisation support
  if [[ -f /proc/cpuinfo ]]; then
    grep -qE '(vmx|svm)' /proc/cpuinfo || return 1
  fi

  if has virsh; then
    return 0
  fi

  # libvirt is installable via dnf / apt on Linux
  case "$HOST_OS" in
    ubuntu|debian|fedora|rhel|linux_generic) return 0 ;;
    *) return 1 ;;
  esac
}

# --------------------------------------------------------------------------- #
# _probe_incus
# Returns 0 if incus is installed or installable on this Linux host.
# Returns 1 on macOS.
# --------------------------------------------------------------------------- #
_probe_incus() {
  [[ "$HOST_OS" == "mac" ]] && return 1

  if has incus; then
    return 0
  fi

  case "$HOST_OS" in
    ubuntu|debian|fedora|rhel|linux_generic) return 0 ;;
    *) return 1 ;;
  esac
}

# --------------------------------------------------------------------------- #
# detect_providers
# Probes each provider in PROVIDER_PRIORITY and populates AVAILABLE_PROVIDERS.
# --------------------------------------------------------------------------- #
detect_providers() {
  banner "Checking virtualization providers"
  AVAILABLE_PROVIDERS=()
  local rc

  for backend in "${PROVIDER_PRIORITY[@]}"; do
    case "$backend" in
      multipass)
        _probe_multipass; rc=$?
        if [[ $rc -eq 0 ]]; then
          if has multipass; then
            success "Multipass $(multipass version 2>/dev/null | head -n1 | awk '{print $2}') — installed"
          else
            success "Multipass — installable on ${HOST_OS}"
          fi
          AVAILABLE_PROVIDERS+=("multipass")
        else
          warn "Multipass — not supported on ${HOST_OS}"
        fi
        ;;
      libvirt)
        _probe_libvirt; rc=$?
        if [[ $rc -eq 0 ]]; then
          if has virsh; then
            success "KVM/libvirt $(virsh --version 2>/dev/null | head -n1) — installed"
          else
            success "KVM/libvirt — installable on ${HOST_OS} (hardware-virt detected)"
          fi
          AVAILABLE_PROVIDERS+=("libvirt")
        else
          if [[ "$HOST_OS" == "mac" ]]; then
            warn "KVM/libvirt — not supported on macOS"
          else
            warn "KVM/libvirt — CPU does not expose virtualisation flags (vmx/svm)"
          fi
        fi
        ;;
      incus)
        _probe_incus; rc=$?
        if [[ $rc -eq 0 ]]; then
          if has incus; then
            success "Incus $(incus version 2>/dev/null | head -n1) — installed"
          else
            success "Incus — installable on ${HOST_OS}"
          fi
          AVAILABLE_PROVIDERS+=("incus")
        else
          warn "Incus — not supported on ${HOST_OS}"
        fi
        ;;
      *)
        warn "Unknown provider in PROVIDER_PRIORITY: ${backend} — skipping"
        ;;
    esac
  done

  export AVAILABLE_PROVIDERS
}

# --------------------------------------------------------------------------- #
# select_provider
# Prefers already-installed providers (fewest additional deps) over those that
# only qualify as "installable".  Falls back to priority order when nothing is
# installed yet.  If no provider was detected at all, defaults to multipass.
# --------------------------------------------------------------------------- #
select_provider() {
  if [[ ${#AVAILABLE_PROVIDERS[@]} -eq 0 ]]; then
    warn "No supported provider detected. Will attempt to install Multipass."
    SELECTED_PROVIDER="multipass"
    export SELECTED_PROVIDER
    return 0
  fi

  # Collect providers that are fully installed (binary present on PATH).
  # Order mirrors AVAILABLE_PROVIDERS, which already respects PROVIDER_PRIORITY.
  local installed_providers=()
  for p in "${AVAILABLE_PROVIDERS[@]}"; do
    case "$p" in
      multipass) has multipass && installed_providers+=("$p") ;;
      libvirt)   has virsh     && installed_providers+=("$p") ;;
      incus)     has incus     && installed_providers+=("$p") ;;
    esac
  done

  if [[ ${#installed_providers[@]} -gt 0 ]]; then
    SELECTED_PROVIDER="${installed_providers[0]}"
  else
    SELECTED_PROVIDER="${AVAILABLE_PROVIDERS[0]}"
  fi

  export SELECTED_PROVIDER
  info "Selected provider: ${_BOLD}${SELECTED_PROVIDER}${_RESET}"
}
