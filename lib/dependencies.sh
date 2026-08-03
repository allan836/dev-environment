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
# _configure_docker_for_libvirt_coexistence
#
# WHY THIS EXISTS
# ───────────────
# When Docker and libvirt both run on the same host, their nftables rules
# collide in a way that silently breaks all guest VM internet access.
#
# The collision (confirmed by live packet-counter analysis):
#   Docker installs an ip filter table via iptables-nft with a FORWARD chain
#   that has policy DROP.  libvirt installs ip libvirt_network with a forward
#   chain that ACCEPTs packets from virbr0.
#
#   In nftables, when multiple tables register base chains at the SAME hook
#   and priority (both use hook forward, priority filter = 0), they execute
#   in table handle-number order (lower handle = registered earlier = runs first).
#   Docker's ip filter table (registered at boot, handle ~6) runs before
#   libvirt_network (handle ~9, registered when virtnetworkd starts), so
#   Docker's DROP policy fires first and terminates virbr0 packets before
#   libvirt's ACCEPT rule is ever evaluated.
#
#   Symptom: guest can ping the gateway (192.168.122.1) — that is local
#   bridge switching and never hits the FORWARD chain.  All routed packets
#   requiring host NAT (TCP, ICMP to 8.8.8.8, etc.) are silently dropped.
#   The libvirt guest_nat TCP masquerade counter stays at 0; only dnsmasq's
#   own host-originated DNS lookups (UDP, OUTPUT not FORWARD) increment.
#
# THE FIX
# ───────
# Add ACCEPT rules to Docker's DOCKER-USER chain for all libvirt bridge
# interfaces.  DOCKER-USER is the designed user-extension point for exactly
# this use case — Docker explicitly documents and preserves it across daemon
# restarts (it only flushes DOCKER, DOCKER-FORWARD, DOCKER-BRIDGE, DOCKER-CT).
#
# We install two rules per bridge:
#   -I DOCKER-USER -i vibrX -j ACCEPT
#       Allows forwarded packets FROM the guest to reach the internet.
#   -I DOCKER-USER -o vibrX -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
#       Allows reply packets TO reach the guest.
#
# The rules are applied by a systemd oneshot service
# (libvirt-docker-coexist.service) that starts after docker.service so the
# DOCKER-USER chain already exists when the rules are inserted.
#
# WHY NOT daemon.json "iptables: false"
# ─────────────────────────────────────
# Tested and does not work on Docker 29 (Fedora package 1.fc44).  With
# firewall-backend "iptables+firewalld", the daemon ignores "iptables: false"
# and reinstates iptables:true in its loaded config.  Using
# "firewall-backend": "nftables" creates a docker-bridges nftables table but
# STILL creates an ip filter FORWARD chain (for the DOCKER-USER hook point).
# The DROP policy remains regardless of backend choice.
#
# PORTABILITY
# ───────────
# Fedora:  iptables is iptables-nft (nf_tables backend). Docker creates
#          ip filter FORWARD with DROP policy. This fix applies.
# Ubuntu:  iptables is also iptables-nft on Ubuntu 20.10+. Same behaviour.
# Debian:  iptables-nft since Debian 11. Same behaviour.
# macOS:   Docker Desktop uses its own VM; DOCKER-USER is not exposed to the
#          host. libvirt is not supported on macOS. No conflict possible.
#
# IDEMPOTENCY
# ───────────
# The systemd service uses iptables -C (check) before -I (insert).
# Running provision.sh multiple times is safe.
# --------------------------------------------------------------------------- #
_configure_docker_for_libvirt_coexistence() {
  local _script_dest="/usr/local/sbin/libvirt-docker-coexist.sh"
  local _service_dest="/etc/systemd/system/libvirt-docker-coexist.service"

  # ------------------------------------------------------------------ #
  # 1. Write the coexistence script
  # ------------------------------------------------------------------ #
  info "Installing libvirt-Docker coexistence fix..."
  info "  Target: ${_script_dest}"

  sudo mkdir -p "$(dirname "${_script_dest}")"

  sudo tee "${_script_dest}" > /dev/null << 'COEXIST_SCRIPT'
#!/usr/bin/env bash
# libvirt-docker-coexist.sh — managed by provision.sh; do not edit manually.
# See lib/dependencies.sh:_configure_docker_for_libvirt_coexistence for docs.
set -euo pipefail

ACTION="${1:---apply}"

_get_libvirt_bridges() {
  local bridges=()
  while IFS= read -r iface; do
    bridges+=("${iface}")
  done < <(ip link show type bridge 2>/dev/null \
    | grep -oP '^\d+:\s+\K[^ :]+' \
    | grep '^virbr' || true)
  if command -v virsh &>/dev/null; then
    while IFS= read -r bridge; do
      [[ -n "${bridge}" ]] && bridges+=("${bridge}")
    done < <(virsh -c qemu:///system net-list --all 2>/dev/null \
      | awk 'NR>2 && $1 != "" {print $1}' \
      | xargs -I{} virsh -c qemu:///system net-info {} 2>/dev/null \
      | grep '^Bridge:' \
      | awk '{print $2}' || true)
  fi
  printf '%s\n' "${bridges[@]}" | sort -u
}

_docker_user_exists() {
  iptables -L DOCKER-USER -n &>/dev/null
}

_add_rules_for_bridge() {
  local bridge="$1"
  if ! iptables -C DOCKER-USER -i "${bridge}" -j ACCEPT &>/dev/null; then
    iptables -I DOCKER-USER 1 -i "${bridge}" -j ACCEPT
    echo "Added: DOCKER-USER ACCEPT -i ${bridge}"
  else
    echo "Already present: DOCKER-USER ACCEPT -i ${bridge}"
  fi
  if ! iptables -C DOCKER-USER -o "${bridge}" -m conntrack \
      --ctstate ESTABLISHED,RELATED -j ACCEPT &>/dev/null; then
    iptables -I DOCKER-USER 2 -o "${bridge}" -m conntrack \
      --ctstate ESTABLISHED,RELATED -j ACCEPT
    echo "Added: DOCKER-USER ACCEPT -o ${bridge} ESTABLISHED,RELATED"
  else
    echo "Already present: DOCKER-USER ACCEPT -o ${bridge} ESTABLISHED,RELATED"
  fi
}

_remove_rules_for_bridge() {
  local bridge="$1"
  iptables -D DOCKER-USER -i "${bridge}" -j ACCEPT &>/dev/null && \
    echo "Removed: DOCKER-USER ACCEPT -i ${bridge}" || true
  iptables -D DOCKER-USER -o "${bridge}" -m conntrack \
    --ctstate ESTABLISHED,RELATED -j ACCEPT &>/dev/null && \
    echo "Removed: DOCKER-USER ACCEPT -o ${bridge} ESTABLISHED,RELATED" || true
}

main() {
  if ! _docker_user_exists; then
    echo "DOCKER-USER chain not found — Docker not running or uses a different backend."
    echo "No rules added. Re-run after Docker starts."
    exit 0
  fi
  local bridges
  mapfile -t bridges < <(_get_libvirt_bridges)
  if [[ ${#bridges[@]} -eq 0 ]]; then
    echo "No libvirt bridge interfaces found. No rules added."
    exit 0
  fi
  case "${ACTION}" in
    --apply)
      echo "Applying libvirt-docker coexistence rules for: ${bridges[*]}"
      for bridge in "${bridges[@]}"; do _add_rules_for_bridge "${bridge}"; done
      echo "Done."
      ;;
    --remove)
      echo "Removing libvirt-docker coexistence rules for: ${bridges[*]}"
      for bridge in "${bridges[@]}"; do _remove_rules_for_bridge "${bridge}"; done
      echo "Done."
      ;;
    *) echo "Usage: $0 [--apply|--remove]" >&2; exit 1 ;;
  esac
}
main
COEXIST_SCRIPT

  sudo chmod 0755 "${_script_dest}"
  printf 'Wrote coexistence script: %s\n' "${_script_dest}" >> "${LOG_FILE}"

  # ------------------------------------------------------------------ #
  # 2. Write the systemd service unit
  # ------------------------------------------------------------------ #
  sudo tee "${_service_dest}" > /dev/null << 'COEXIST_SERVICE'
[Unit]
Description=Allow libvirt guest forwarding through Docker FORWARD chain
Documentation=https://docs.docker.com/network/packet-filtering-firewalls/
After=docker.service network.target
Wants=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/libvirt-docker-coexist.sh --apply
ExecStop=/usr/local/sbin/libvirt-docker-coexist.sh --remove
SuccessExitStatus=0

[Install]
WantedBy=multi-user.target
COEXIST_SERVICE

  printf 'Wrote coexistence service: %s\n' "${_service_dest}" >> "${LOG_FILE}"

  # ------------------------------------------------------------------ #
  # 3. Enable and start the service
  # ------------------------------------------------------------------ #
  sudo systemctl daemon-reload 2>>"${LOG_FILE}" || true
  sudo systemctl enable libvirt-docker-coexist.service 2>>"${LOG_FILE}" || true

  # Start immediately if Docker is already running
  if systemctl is-active docker &>/dev/null; then
    local svc_rc=0
    sudo systemctl restart libvirt-docker-coexist.service 2>>"${LOG_FILE}" || svc_rc=$?
    if [[ ${svc_rc} -eq 0 ]]; then
      success "libvirt-Docker coexistence fix applied (DOCKER-USER rules added)."
    else
      warn "libvirt-docker-coexist.service start failed — check: journalctl -u libvirt-docker-coexist"
    fi
  else
    info "Docker not running — coexistence rules will be applied on next boot/Docker start."
    success "libvirt-Docker coexistence service installed and enabled."
  fi
}

# --------------------------------------------------------------------------- #
# ensure_libvirt
# Installs KVM/libvirt and all required supporting tools.
# Required tools:
#   virsh, virt-install, virt-host-validate  — libvirt management
#   qemu-img                                  — disk image creation
#   cloud-localds / genisoimage / xorriso     — cloud-init ISO creation
# --------------------------------------------------------------------------- #
ensure_libvirt() {
  local _need_install=false
  for t in virsh virt-install qemu-img; do
    has "${t}" || _need_install=true
  done

  if [[ "${_need_install}" == "false" ]]; then
    success "KVM/libvirt already installed."
    # Still run the Docker coexistence fix on every invocation — it is idempotent
    # and must be applied even when libvirt was installed in a previous run but
    # Docker was installed later.
    _configure_docker_for_libvirt_coexistence
    return 0
  fi

  info "Installing KVM/libvirt and tools..."

  case "$PKG_MANAGER" in
    apt)
      sudo apt-get update -qq 2>>"$LOG_FILE"
      sudo apt-get install -y \
        qemu-kvm libvirt-daemon-system libvirt-clients \
        virt-install virt-manager libvirt-dev \
        cloud-image-utils genisoimage xorriso \
        bridge-utils cpu-checker \
        2>>"$LOG_FILE"
      ;;
    dnf)
      sudo dnf install -y \
        @virtualization \
        virt-install virt-manager \
        cloud-utils genisoimage xorriso \
        2>>"$LOG_FILE"
      ;;
    *)
      die "Cannot auto-install libvirt on '${HOST_OS}'. Install qemu-kvm, libvirt, virt-install manually."
      ;;
  esac

  # Enable the system daemon (not the session daemon).
  sudo systemctl enable --now libvirtd  2>>"$LOG_FILE" || \
    sudo systemctl enable --now virtqemud 2>>"$LOG_FILE" || true

  sudo usermod -aG libvirt,kvm "${USER}" 2>/dev/null || true

  has virsh || die "libvirt installation failed (virsh not found). Check ${LOG_FILE}."
  success "KVM/libvirt installed."

  # Fix Docker/libvirt nftables FORWARD chain conflict before any VM boots.
  _configure_docker_for_libvirt_coexistence

  # Group membership and KVM modules only take effect after a new session.
  _prompt_reboot "KVM/libvirt was just installed. A reboot is required so kernel modules load and your user gains libvirt/kvm group access."
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