#!/usr/bin/env bash
# =============================================================================
# lib/vm.sh — VM lifecycle management (provider-agnostic)
#
# Responsibilities:
#   ensure_host_ssh_key  — generate a dedicated keypair for VM access
#   vm_exec              — run a command inside the VM over SSH
#   vm_push              — copy a file into the VM over SCP
#   vm_sync_repo         — rsync / scp the dev-environment repo into the VM
#                          when the provider cannot do a native mount
#   destroy_vm           — tear down an existing VM (--destroy flag)
#   boot_vm              — try providers in priority order until one succeeds
#   wait_for_ssh         — poll until the VM accepts SSH connections
#   setup_ssh_key        — generate developer's GitHub key inside VM
#
# After boot_vm() succeeds, the following are exported by the provider:
#   ACTIVE_PROVIDER, VM_IP, VM_SSH_USER, VM_SSH_PORT
# And by ensure_host_ssh_key():
#   VM_SSH_KEY
#
# Requires:
#   lib/log.sh, lib/providers/multipass.sh, lib/providers/libvirt.sh,
#   lib/providers/incus.sh sourced.
#   VM_NAME, VM_CPU, VM_RAM, VM_USER, REPO_ROOT, LOG_FILE exported.
# =============================================================================

# Where the host-side provisioning SSH key lives
_HOST_SSH_KEY="${HOME}/.ssh/dev-env"

# --------------------------------------------------------------------------- #
# ensure_host_ssh_key
# Generates a dedicated ed25519 keypair for VM access if one does not exist.
# Exports VM_SSH_KEY (path to private key; public key is VM_SSH_KEY.pub).
# --------------------------------------------------------------------------- #
ensure_host_ssh_key() {
  if [[ ! -f "${_HOST_SSH_KEY}" ]]; then
    info "Generating provisioning SSH keypair at ${_HOST_SSH_KEY}..."
    mkdir -p "$(dirname "${_HOST_SSH_KEY}")"
    ssh-keygen -t ed25519 -C "dev-env-provision@$(hostname)" \
      -N "" -f "${_HOST_SSH_KEY}" &>/dev/null
    chmod 600 "${_HOST_SSH_KEY}"
    success "Provisioning keypair created."
  fi
  VM_SSH_KEY="${_HOST_SSH_KEY}"
  export VM_SSH_KEY
}

# --------------------------------------------------------------------------- #
# vm_exec <command ...>
# Runs a command inside the VM via SSH.
# --------------------------------------------------------------------------- #
vm_exec() {
  ssh \
    -i "${VM_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    -p "${VM_SSH_PORT:-22}" \
    "${VM_SSH_USER}@${VM_IP}" -- "$@"
}

# --------------------------------------------------------------------------- #
# vm_push <local_path> <remote_path>
# Copies a file from the host into the VM.
# --------------------------------------------------------------------------- #
vm_push() {
  scp \
    -i "${VM_SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -P "${VM_SSH_PORT:-22}" \
    "$1" "${VM_SSH_USER}@${VM_IP}:$2"
}

# --------------------------------------------------------------------------- #
# vm_sync_repo
# Rsyncs the dev-environment repo into the VM when a native mount is not
# available or failed.  Safe to call even when the mount succeeded.
# --------------------------------------------------------------------------- #
vm_sync_repo() {
  info "Syncing repo to VM:/home/${VM_SSH_USER}/dev-environment..."
  rsync -az \
    -e "ssh -i ${VM_SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p ${VM_SSH_PORT:-22}" \
    --exclude '.git' \
    --exclude '*.qcow2' \
    "${REPO_ROOT}/" \
    "${VM_SSH_USER}@${VM_IP}:/home/${VM_SSH_USER}/dev-environment/" \
    2>&1 | tee -a "$LOG_FILE" || true
}

# --------------------------------------------------------------------------- #
# destroy_vm
# Dispatches to the correct provider destroy function.
# When called before boot (--destroy flag), probes each provider in turn.
# --------------------------------------------------------------------------- #
destroy_vm() {
  info "Destroying existing VM '${VM_NAME}'..."

  local active="${ACTIVE_PROVIDER:-}"

  # If we don't know which provider was used, probe in priority order
  if [[ -z "$active" ]]; then
    for p in "${PROVIDER_PRIORITY[@]}"; do
      case "$p" in
        multipass) has multipass && multipass info "${VM_NAME}" &>/dev/null \
                     && active="multipass" && break ;;
        libvirt)   has virsh     && virsh -c qemu:///system dominfo "${VM_NAME}" &>/dev/null \
                     && active="libvirt"   && break ;;
        incus)     has incus     && incus info "${VM_NAME}" &>/dev/null \
                     && active="incus"     && break ;;
      esac
    done
  fi

  case "$active" in
    multipass) destroy_multipass ;;
    libvirt)   destroy_libvirt   ;;
    incus)     destroy_incus     ;;
    *)
      info "No existing '${VM_NAME}' VM found — nothing to destroy."
      ;;
  esac
}

# --------------------------------------------------------------------------- #
# boot_vm
# Tries providers in PROVIDER_PRIORITY order until one succeeds.
# Sets ACTIVE_PROVIDER, VM_IP, VM_SSH_USER, VM_SSH_PORT.
# --------------------------------------------------------------------------- #
boot_vm() {
  banner "Creating VM"

  ensure_host_ssh_key

  local attempted=()

  _try_provider() {
    local p="$1"
    for a in "${attempted[@]:-}"; do [[ "$a" == "$p" ]] && return 1; done
    attempted+=("$p")
    return 0
  }

  # Attempt SELECTED_PROVIDER first, then fall back through AVAILABLE_PROVIDERS
  local ordered=("${SELECTED_PROVIDER}")
  for p in "${AVAILABLE_PROVIDERS[@]}"; do
    [[ "$p" != "$SELECTED_PROVIDER" ]] && ordered+=("$p")
  done

  for provider in "${ordered[@]}"; do
    _try_provider "$provider" || continue

    info "Attempting provider: ${provider}"
    case "$provider" in
      multipass) boot_multipass && break ;;
      libvirt)   boot_libvirt   && break ;;
      incus)     boot_incus     && break ;;
      *)
        warn "Unknown provider '${provider}' — skipping."
        ;;
    esac

    if [[ -z "${ACTIVE_PROVIDER:-}" ]]; then
      warn "Provider '${provider}' failed. Trying next..."
    fi
  done

  if [[ -z "${ACTIVE_PROVIDER:-}" ]]; then
    die "All providers failed to boot the VM. Check ${LOG_FILE} for details."
  fi

  success "VM booted via: ${ACTIVE_PROVIDER}  |  IP: ${VM_IP}"
}

# --------------------------------------------------------------------------- #
# _ssh_failure_reason  STDERR_TEXT
# Converts raw SSH stderr into a short human-readable description.
# --------------------------------------------------------------------------- #
_ssh_failure_reason() {
  local text="${1:-}"
  if echo "${text}" | grep -qi "connection refused"; then
    echo "Connection refused — SSH daemon not yet running"
  elif echo "${text}" | grep -qi "no route to host\|network unreachable"; then
    echo "No route to host — VM network not ready"
  elif echo "${text}" | grep -qi "permission denied\|publickey"; then
    echo "Permission denied — SSH key not accepted by VM"
  elif echo "${text}" | grep -qi "operation timed out\|timed out\|timeout"; then
    echo "Connection timed out — VM may be under load"
  elif echo "${text}" | grep -qi "host is down\|unreachable"; then
    echo "Host unreachable — VM still starting up"
  elif [[ -n "${text}" ]]; then
    echo "${text:0:80}"
  else
    echo "No response from VM"
  fi
}

# --------------------------------------------------------------------------- #
# wait_for_ssh
# Polls SSH until the VM accepts connections (up to 5 minutes).
# Displays the specific failure reason on each attempt instead of a dot.
# For libvirt: prints VM state and DHCP lease every 10 attempts.
# On timeout: automatically collects and logs libvirt diagnostics.
#
# Returns 0 when SSH is ready.
# Returns 1 when the timeout is reached WITHOUT dying, so the caller can
# invoke ssh_recovery() from lib/recovery.sh instead of hard-aborting.
# --------------------------------------------------------------------------- #
wait_for_ssh() {
  if [[ ! "${VM_IP:-}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    die "No valid IPv4 address available (VM_IP='${VM_IP:-}') — cannot wait for SSH."
  fi

  info "Waiting for SSH at ${VM_SSH_USER}@${VM_IP}:${VM_SSH_PORT:-22}..."

  local max_attempts=60
  local attempt=0

  while [[ ${attempt} -lt ${max_attempts} ]]; do
    # Attempt SSH; capture stderr separately so we can show the failure reason.
    local tmp_err; tmp_err="$(mktemp /tmp/ssh-wait-XXXXXX)"
    local rc=0
    ssh \
      -i "${VM_SSH_KEY}" \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 \
      -o BatchMode=yes \
      -p "${VM_SSH_PORT:-22}" \
      "${VM_SSH_USER}@${VM_IP}" -- "echo ssh-ready" \
      >/dev/null 2>"${tmp_err}" || rc=$?

    if [[ ${rc} -eq 0 ]]; then
      rm -f "${tmp_err}"
      echo ""
      success "SSH is ready."
      return 0
    fi

    local raw_err; raw_err="$(tr -d '\n' < "${tmp_err}" 2>/dev/null || true)"
    rm -f "${tmp_err}"

    attempt=$(( attempt + 1 ))
    local reason; reason="$(_ssh_failure_reason "${raw_err}")"
    info "  SSH not ready (attempt ${attempt}/${max_attempts}): ${reason}"

    # For libvirt: surface VM state and DHCP lease every 10 attempts so the
    # user can see what the guest is doing while they wait.
    if [[ "${ACTIVE_PROVIDER:-}" == "libvirt" ]] && (( attempt % 10 == 0 )); then
      local vm_state dhcp_ip
      vm_state="$(virsh -c qemu:///system domstate "${VM_NAME}" 2>/dev/null \
        | tr -d '[:space:]' || echo "unknown")"
      dhcp_ip="$(virsh -c qemu:///system net-dhcp-leases default 2>/dev/null \
        | grep -oP '\d+\.\d+\.\d+\.\d+(?=/)' | grep -v '^127\.' | head -n1 || true)"
      info "  VM state: ${vm_state}  |  DHCP lease: ${dhcp_ip:-none yet}"
    fi

    sleep 5
  done

  echo ""
  error "VM SSH did not become available after $((max_attempts * 5)) seconds."
  error "SSH key auth timed out at ${VM_SSH_USER}@${VM_IP}:${VM_SSH_PORT:-22}"
  printf 'wait_for_ssh timed out after %d seconds\n' "$((max_attempts * 5))" >> "${LOG_FILE}"

  # Automatically collect libvirt diagnostics on timeout so the user does not
  # have to run these commands by hand.
  if [[ "${ACTIVE_PROVIDER:-}" == "libvirt" ]]; then
    info "Collecting libvirt diagnostics (also saved to ${LOG_FILE})..."
    {
      echo "=== virsh dominfo ==="
      virsh -c qemu:///system dominfo "${VM_NAME}" 2>&1 || true
      echo "=== virsh domifaddr ==="
      virsh -c qemu:///system domifaddr "${VM_NAME}" 2>&1 || true
      echo "=== virsh domifaddr --source arp ==="
      virsh -c qemu:///system domifaddr "${VM_NAME}" --source arp 2>&1 || true
      echo "=== virsh net-dhcp-leases default ==="
      virsh -c qemu:///system net-dhcp-leases default 2>&1 || true
      echo "=== journalctl virtqemud (last 30 lines) ==="
      journalctl -u virtqemud --no-pager -n 30 2>&1 || true
    } | tee -a "${LOG_FILE}" >&2
  fi

  return 1
}

# --------------------------------------------------------------------------- #
# wait_for_cloud_init
# Blocks until cloud-init reports that first-boot setup is complete.
#
# WHY THIS EXISTS
# ───────────────
# SSH becomes available very early in the boot sequence — often before
# cloud-init has finished installing packages, creating users, or resizing
# the filesystem.  If Ansible starts at that point it will fail on tasks
# that depend on those completed steps, and succeed on an immediate re-run.
# This gate eliminates that class of "second run always works" failures.
#
# cloud-init status codes:
#   running — first boot still in progress (packages installing, users being
#              created, filesystem resizing, runcmd executing)
#   done    — complete; safe to proceed with Ansible
#   error   — finished with errors; we warn and continue rather than abort
#   not run — cloud-init has not started yet; keep waiting
#
# Returns 0 in all cases — a timeout or reported error only produces a
# warning so that provisioning can still make progress.
# --------------------------------------------------------------------------- #
wait_for_cloud_init() {
  info "Waiting for cloud-init to complete first-boot setup..."
  info "(Prevents Ansible from starting before packages and users are fully ready.)"

  # Gracefully skip if cloud-init is not present in the guest image.
  if ! vm_exec "command -v cloud-init" &>/dev/null; then
    warn "cloud-init not found in VM — skipping first-boot readiness check."
    return 0
  fi

  local max_wait=300
  local elapsed=0
  local interval=10

  while [[ ${elapsed} -lt ${max_wait} ]]; do
    local ci_status=""
    ci_status="$(vm_exec "cloud-init status 2>/dev/null" 2>/dev/null || true)"

    case "${ci_status}" in
      *"status: done"*)
        success "Cloud-init: first boot complete. Guest is ready for provisioning."
        return 0
        ;;
      *"status: error"*)
        warn "Cloud-init finished with errors: ${ci_status}"
        warn "Provisioning will continue — investigate /var/log/cloud-init-output.log inside the VM."
        return 0
        ;;
      *"status: running"*)
        info "  Cloud-init: still running (${elapsed}s elapsed) — waiting..."
        ;;
      *"status: not run"*)
        info "  Cloud-init: not started yet (${elapsed}s elapsed) — waiting..."
        ;;
      *)
        info "  Cloud-init status: '${ci_status:-unknown}' (${elapsed}s elapsed)"
        ;;
    esac

    sleep "${interval}"
    elapsed=$(( elapsed + interval ))
  done

  warn "Cloud-init did not finish within ${max_wait}s — proceeding with Ansible anyway."
  warn "If Ansible fails, inspect cloud-init logs inside the VM:"
  warn "  ssh -i ~/.ssh/dev-env ${VM_SSH_USER}@${VM_IP} 'sudo cloud-init status; sudo tail -50 /var/log/cloud-init-output.log'"
  return 0
}

# --------------------------------------------------------------------------- #
# setup_ssh_key
# Generates an ed25519 SSH key INSIDE the VM for GitHub access.
# Displays the public key; this is the only manual step.
# --------------------------------------------------------------------------- #
setup_ssh_key() {
  banner "SSH Key Setup"
  info "Generating GitHub SSH key inside VM (skipped if already present)..."

  vm_exec "
    if [[ ! -f ~/.ssh/id_ed25519 ]]; then
      mkdir -p ~/.ssh && chmod 700 ~/.ssh
      ssh-keygen -t ed25519 -C '$(whoami)@dev-env' -N '' -f ~/.ssh/id_ed25519
    fi
    echo ''
    echo '============================================================'
    echo '  ACTION REQUIRED: Add the following public key to GitHub'
    echo '  Settings → SSH and GPG keys → New SSH key'
    echo '============================================================'
    cat ~/.ssh/id_ed25519.pub
    echo '============================================================'
  "

  echo ""
  warn "This is the only manual step — GitHub requires you to authenticate."
  warn "Once the key is added to your GitHub account:"
  read -rp "  Press Enter to continue... "
}
