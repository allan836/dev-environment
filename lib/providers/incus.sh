#!/usr/bin/env bash
# =============================================================================
# lib/providers/incus.sh — Incus VM provider
#
# Boots an Ubuntu 24.04 VM via Incus (LXD fork, full VM mode).
# Linux-only. Lightweight alternative to full KVM stacks.
#
# After a successful boot, exports:
#   ACTIVE_PROVIDER  = "incus"
#   VM_IP            = <IP address of the VM>
#   VM_SSH_USER      = "ubuntu"
#   VM_SSH_PORT      = 22
#
# VM_SSH_KEY is set by ensure_host_ssh_key() in lib/vm.sh before boot.
#
# Requires: lib/log.sh, lib/dependencies.sh (ensure_incus) sourced.
#           VM_NAME, VM_CPU, VM_RAM, VM_DISK_GB, VM_SSH_KEY exported.
# =============================================================================

# --------------------------------------------------------------------------- #
# _incus_vm_exists
# --------------------------------------------------------------------------- #
_incus_vm_exists() {
  incus info "${VM_NAME}" &>/dev/null
}

# --------------------------------------------------------------------------- #
# _incus_ensure_initialized
# Runs `incus admin init --minimal` if Incus hasn't been initialised yet.
# --------------------------------------------------------------------------- #
_incus_ensure_initialized() {
  if incus network list 2>/dev/null | grep -q incusbr0; then
    return 0
  fi
  info "Initializing Incus (first-time setup)..."
  incus admin init --minimal 2>&1 | tee -a "$LOG_FILE"
  sudo usermod -aG incus-admin "${USER}" 2>/dev/null || true
}

# --------------------------------------------------------------------------- #
# _incus_get_ip
# Polls incus info for the VM's IPv4 address.
# --------------------------------------------------------------------------- #
_incus_get_ip() {
  local max_wait="${1:-120}" elapsed=0 ip=""
  while [[ -z "$ip" && $elapsed -lt $max_wait ]]; do
    ip=$(incus info "${VM_NAME}" 2>/dev/null \
      | grep -oP 'inet:\s+\K\d+\.\d+\.\d+\.\d+' | head -n1 || true)
    if [[ -z "$ip" ]]; then
      sleep 5
      elapsed=$(( elapsed + 5 ))
      printf "."
    fi
  done
  echo "$ip"
}

# --------------------------------------------------------------------------- #
# _incus_prepare_cloud_init
# Substitutes SSH_AUTHORIZED_KEY and returns the user-data content.
# --------------------------------------------------------------------------- #
_incus_prepare_cloud_init() {
  local pub_key; pub_key="$(cat "${VM_SSH_KEY}.pub")"
  sed "s|SSH_AUTHORIZED_KEY|${pub_key}|g" \
    "${REPO_ROOT}/vm/cloud-init/user-data"
}

# --------------------------------------------------------------------------- #
# destroy_incus
# --------------------------------------------------------------------------- #
destroy_incus() {
  if _incus_vm_exists; then
    info "Stopping and deleting Incus VM '${VM_NAME}'..."
    incus stop "${VM_NAME}" --force 2>/dev/null || true
    incus delete "${VM_NAME}" 2>&1 | tee -a "$LOG_FILE" || true
    success "Incus VM '${VM_NAME}' destroyed."
  else
    info "Incus VM '${VM_NAME}' does not exist — nothing to destroy."
  fi
}

# --------------------------------------------------------------------------- #
# boot_incus
# --------------------------------------------------------------------------- #
boot_incus() {
  info "Provider: Incus (VM mode)"
  ensure_incus
  _incus_ensure_initialized

  if _incus_vm_exists; then
    local state
    state=$(incus info "${VM_NAME}" 2>/dev/null \
      | grep -oP 'Status:\s+\K\S+' | head -n1 || echo "unknown")

    if [[ "${state,,}" == "running" ]]; then
      info "VM '${VM_NAME}' already running."
    else
      info "VM '${VM_NAME}' exists (state: ${state}). Starting..."
      incus start "${VM_NAME}" 2>&1 | tee -a "$LOG_FILE"
    fi
  else
    info "Launching Incus VM '${VM_NAME}' (Ubuntu 24.04)..."
    local user_data
    user_data="$(_incus_prepare_cloud_init)"

    incus launch images:ubuntu/24.04 "${VM_NAME}" \
      --vm \
      --config limits.cpu="${VM_CPU}" \
      --config limits.memory="${VM_RAM}MiB" \
      --config "user.user-data=${user_data}" \
      2>&1 | tee -a "$LOG_FILE"

    # Resize root disk to requested size
    incus config device override "${VM_NAME}" root size="${VM_DISK_GB}GiB" \
      2>&1 | tee -a "$LOG_FILE" || true
  fi

  # Mount dev-environment repo into the VM
  info "Mounting repo into VM at /home/ubuntu/dev-environment..."
  incus config device add "${VM_NAME}" devenv disk \
    source="${REPO_ROOT}" \
    path="/home/ubuntu/dev-environment" \
    2>&1 | tee -a "$LOG_FILE" || \
    warn "Incus disk device add failed — will sync files via scp instead."

  info "Waiting for VM to obtain an IP address..."
  local ip
  ip="$(_incus_get_ip 180)"
  echo ""

  if [[ -z "$ip" ]]; then
    error "Could not determine Incus VM IP after 180 s."
    error "Try: incus info ${VM_NAME}"
    return 1
  fi

  VM_IP="$ip"
  VM_SSH_USER="ubuntu"
  VM_SSH_PORT=22
  ACTIVE_PROVIDER="incus"
  export VM_IP VM_SSH_USER VM_SSH_PORT ACTIVE_PROVIDER

  success "Incus VM '${VM_NAME}' is up. IP: ${VM_IP}"
}
