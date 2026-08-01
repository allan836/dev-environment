#!/usr/bin/env bash
# =============================================================================
# lib/vm.sh — VM lifecycle management
#
# Responsibilities:
#   - destroy_vm  : tear down an existing VM (--destroy flag)
#   - boot_vm     : try providers in priority order until one succeeds
#   - wait_for_ssh: poll until the VM accepts SSH connections
#   - setup_ssh_key: generate key inside VM, prompt user to add to GitHub
#
# Requires:
#   lib/log.sh, lib/providers/virtualbox.sh, lib/providers/libvirt.sh,
#   lib/providers/vmware.sh sourced.
#   VM_DIR, LOG_FILE, SELECTED_PROVIDER, PROVIDER_PRIORITY exported.
# =============================================================================

# --------------------------------------------------------------------------- #
# destroy_vm
# Destroys the current VM without prompting.
# --------------------------------------------------------------------------- #
destroy_vm() {
  info "Destroying existing VM..."
  cd "$VM_DIR"
  vagrant destroy -f 2>&1 | tee -a "$LOG_FILE" || true
  success "VM destroyed."
}

# --------------------------------------------------------------------------- #
# boot_vm
# Boots the VM using the selected provider.
# Falls back to the next provider in PROVIDER_PRIORITY on failure.
# Sets ACTIVE_PROVIDER on success.
# --------------------------------------------------------------------------- #
boot_vm() {
  banner "Creating VM"

  export VAGRANT_VM_NAME="$VM_NAME"
  export VAGRANT_VM_CPU="$VM_CPU"
  export VAGRANT_VM_RAM="$VM_RAM"

  local attempted=()

  for provider in "${PROVIDER_PRIORITY[@]}"; do
    # Skip providers we have already tried
    local already_tried=false
    for a in "${attempted[@]:-}"; do
      [[ "$a" == "$provider" ]] && { already_tried=true; break; }
    done
    $already_tried && continue

    # Only attempt the selected provider (detection already chose it)
    [[ "$provider" != "$SELECTED_PROVIDER" ]] && continue

    attempted+=("$provider")

    case "$provider" in
      virtualbox)     boot_virtualbox  && break ;;
      libvirt)        boot_libvirt     && break ;;
      vmware_desktop) boot_vmware      && break ;;
      *)
        error "Unknown provider: $provider"
        ;;
    esac

    # If the selected provider failed, try the next available one
    if [[ -z "${ACTIVE_PROVIDER:-}" ]]; then
      warn "Provider '${provider}' failed. Trying next available provider..."
      for fallback in "${AVAILABLE_PROVIDERS[@]}"; do
        [[ "$fallback" == "$provider" ]] && continue
        local already=false
        for a in "${attempted[@]:-}"; do
          [[ "$a" == "$fallback" ]] && { already=true; break; }
        done
        $already && continue

        attempted+=("$fallback")
        SELECTED_PROVIDER="$fallback"
        info "Falling back to: ${fallback}"
        case "$fallback" in
          virtualbox)     boot_virtualbox  && break 2 ;;
          libvirt)        boot_libvirt     && break 2 ;;
          vmware_desktop) boot_vmware      && break 2 ;;
        esac
      done
    fi
    break
  done

  if [[ -z "${ACTIVE_PROVIDER:-}" ]]; then
    die "All providers failed to boot the VM. Check ${LOG_FILE} for details."
  fi

  success "VM booted via provider: ${ACTIVE_PROVIDER}"
}

# --------------------------------------------------------------------------- #
# wait_for_ssh
# Polls `vagrant ssh` until the VM accepts connections.
# --------------------------------------------------------------------------- #
wait_for_ssh() {
  info "Waiting for VM SSH to become available..."
  cd "$VM_DIR"

  local max_attempts=60
  local attempt=0

  while ! vagrant ssh -c "echo ssh-ready" &>/dev/null; do
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
# Generates an SSH key inside the VM (if not present) and displays the public
# key so the developer can add it to GitHub.
# This is the ONLY manual step in the provisioning flow.
# --------------------------------------------------------------------------- #
setup_ssh_key() {
  banner "SSH Key Setup"
  info "Generating SSH key inside VM (skipped if already present)..."
  cd "$VM_DIR"

  vagrant ssh -c "
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
