#!/usr/bin/env bash
# =============================================================================
# lib/providers/multipass.sh — Multipass VM provider
#
# Boots an Ubuntu 24.04 VM via Canonical Multipass.
# Cross-platform: works on macOS and Linux.
#
# After a successful boot, exports:
#   ACTIVE_PROVIDER  = "multipass"
#   VM_IP            = <IP address of the VM>
#   VM_SSH_USER      = "ubuntu"
#   VM_SSH_PORT      = 22
#
# VM_SSH_KEY is set by ensure_host_ssh_key() in lib/vm.sh before boot.
#
# Requires: lib/log.sh, lib/dependencies.sh (ensure_multipass) sourced.
#           VM_NAME, VM_CPU, VM_RAM, VM_DISK_GB, VM_SSH_KEY exported.
# =============================================================================

# --------------------------------------------------------------------------- #
# _multipass_vm_exists
# --------------------------------------------------------------------------- #
_multipass_vm_exists() {
  multipass info "${VM_NAME}" &>/dev/null
}

# --------------------------------------------------------------------------- #
# _multipass_get_ip
# Returns the primary IPv4 address of a running Multipass instance.
# --------------------------------------------------------------------------- #
_multipass_get_ip() {
  multipass info "${VM_NAME}" --format json 2>/dev/null \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
info = d.get('info', {}).get('${VM_NAME}', {})
nets = info.get('ipv4', [])
print(nets[0] if nets else '')
" 2>/dev/null || true
}

# --------------------------------------------------------------------------- #
# _multipass_prepare_cloud_init
# Substitutes SSH_AUTHORIZED_KEY in the cloud-init template and writes a
# temporary file. Returns the path via stdout.
# --------------------------------------------------------------------------- #
_multipass_prepare_cloud_init() {
  local pub_key; pub_key="$(cat "${VM_SSH_KEY}.pub")"
  local tmp; tmp="$(mktemp /tmp/mp-user-data-XXXXXX.yaml)"
  sed "s|SSH_AUTHORIZED_KEY|${pub_key}|g" \
    "${REPO_ROOT}/vm/cloud-init/user-data" > "$tmp"
  echo "$tmp"
}

# --------------------------------------------------------------------------- #
# destroy_multipass
# --------------------------------------------------------------------------- #
destroy_multipass() {
  if _multipass_vm_exists; then
    info "Stopping and deleting Multipass VM '${VM_NAME}'..."
    multipass delete "${VM_NAME}" 2>&1 | tee -a "$LOG_FILE" || true
    multipass purge 2>&1 | tee -a "$LOG_FILE" || true
    success "Multipass VM '${VM_NAME}' destroyed."
  else
    info "Multipass VM '${VM_NAME}' does not exist — nothing to destroy."
  fi
}

# --------------------------------------------------------------------------- #
# boot_multipass
# --------------------------------------------------------------------------- #
boot_multipass() {
  info "Provider: Multipass"
  ensure_multipass

  if _multipass_vm_exists; then
    local state
    state=$(multipass info "${VM_NAME}" --format json 2>/dev/null \
      | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('info', {}).get('${VM_NAME}', {}).get('state', 'unknown'))
" 2>/dev/null || echo "unknown")

    if [[ "$state" == "Running" ]]; then
      info "VM '${VM_NAME}' already running."
    else
      info "VM '${VM_NAME}' exists (state: ${state}). Starting..."
      multipass start "${VM_NAME}" 2>&1 | tee -a "$LOG_FILE"
    fi
  else
    info "Launching new Multipass VM '${VM_NAME}'..."
    local cloud_init_file
    cloud_init_file="$(_multipass_prepare_cloud_init)"

    multipass launch "24.04" \
      --name "${VM_NAME}" \
      --cpus "${VM_CPU}" \
      --memory "${VM_RAM}M" \
      --disk "${VM_DISK_GB}G" \
      --cloud-init "${cloud_init_file}" \
      2>&1 | tee -a "$LOG_FILE"

    rm -f "${cloud_init_file}"
  fi

  info "Waiting for VM IP address..."
  local ip="" attempts=0
  while [[ -z "$ip" && $attempts -lt 30 ]]; do
    ip="$(_multipass_get_ip)"
    [[ -z "$ip" ]] && sleep 5 && attempts=$(( attempts + 1 )) && printf "."
  done
  echo ""

  if [[ -z "$ip" ]]; then
    error "Could not determine Multipass VM IP after 150 s."
    return 1
  fi

  # Mount the dev-environment repo into the VM so Ansible and verify can use it
  info "Mounting repo into VM at /home/ubuntu/dev-environment..."
  multipass mount "${REPO_ROOT}" "${VM_NAME}:/home/ubuntu/dev-environment" \
    2>&1 | tee -a "$LOG_FILE" || \
    warn "Multipass mount failed — will sync files via scp instead."

  VM_IP="$ip"
  VM_SSH_USER="ubuntu"
  VM_SSH_PORT=22
  ACTIVE_PROVIDER="multipass"
  export VM_IP VM_SSH_USER VM_SSH_PORT ACTIVE_PROVIDER

  success "Multipass VM '${VM_NAME}' is up. IP: ${VM_IP}"
}
