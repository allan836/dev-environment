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
#   VM_NAME, VM_CPU, VM_RAM, REPO_ROOT, LOG_FILE, DEV_USER exported.
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
        libvirt)   has virsh     && virsh dominfo "${VM_NAME}" &>/dev/null \
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
# wait_for_ssh
# Polls SSH until the VM accepts connections (up to 5 minutes).
# --------------------------------------------------------------------------- #
wait_for_ssh() {
  info "Waiting for SSH at ${VM_SSH_USER}@${VM_IP}:${VM_SSH_PORT:-22}..."

  local max_attempts=60 attempt=0
  until vm_exec "echo ssh-ready" &>/dev/null; do
    attempt=$(( attempt + 1 ))
    if [[ $attempt -ge $max_attempts ]]; then
      die "VM SSH did not become available after $((max_attempts * 5)) seconds."
    fi
    printf "."
    sleep 5
  done

  echo ""
  success "SSH is ready."
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
      ssh-keygen -t ed25519 -C '${DEV_USER}@dev-env' -N '' -f ~/.ssh/id_ed25519
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
