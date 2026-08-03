#!/usr/bin/env bash
# =============================================================================
# lib/ansible_runner.sh — Ansible provisioning via SSH
#
# Runs the Ansible playbook FROM THE HOST targeting the VM over SSH.
# No Vagrant, no ansible_local — standard ansible-playbook with SSH transport.
#
# Requires:
#   lib/log.sh, lib/vm.sh sourced (for vm_exec, vm_sync_repo)
#   VM_IP, VM_SSH_USER, VM_SSH_KEY, VM_SSH_PORT, VM_USER, SKIP_ANSIBLE,
#   ANSIBLE_DIR, LOG_FILE exported
# =============================================================================

# --------------------------------------------------------------------------- #
# _ensure_ansible_on_host
# Installs Ansible on the HOST machine if not present.
# --------------------------------------------------------------------------- #
_ensure_ansible_on_host() {
  if has ansible; then
    return 0
  fi

  info "Ansible not found on host. Installing..."
  case "$PKG_MANAGER" in
    apt)
      sudo apt-get update -qq 2>>"$LOG_FILE"
      sudo apt-get install -y ansible 2>&1 | tee -a "$LOG_FILE"
      ;;
    dnf)
      sudo dnf install -y ansible 2>&1 | tee -a "$LOG_FILE"
      ;;
    brew)
      brew install ansible 2>&1 | tee -a "$LOG_FILE"
      ;;
    *)
      pip3 install --user ansible 2>&1 | tee -a "$LOG_FILE"
      ;;
  esac

  has ansible || die "Ansible installation failed. Check ${LOG_FILE}."
  success "Ansible installed: $(ansible --version | head -n1)"
}

# --------------------------------------------------------------------------- #
# _build_ssh_args
# Returns the common SSH args string for ansible-playbook.
# --------------------------------------------------------------------------- #
_build_ssh_args() {
  echo "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
}

# --------------------------------------------------------------------------- #
# run_ansible
# Installs Ansible on the host (if needed), then runs the playbook against
# the VM using the inventory pattern  user@ip,  (trailing comma = no hosts
# file lookup).
# --------------------------------------------------------------------------- #
run_ansible() {
  if [[ "${SKIP_ANSIBLE:-false}" == "true" ]]; then
    warn "--skip-ansible set. Skipping Ansible provisioning."
    return 0
  fi

  banner "Provisioning VM"

  _ensure_ansible_on_host

  # Ensure the repo is available inside the VM (native mount is preferred;
  # vm_sync_repo falls back to rsync/scp if the mount failed or unavailable).
  vm_sync_repo

  info "Running Ansible playbook (installs all developer tools)..."
  info "This typically takes 10–20 minutes on first run."

  local inventory="${VM_SSH_USER}@${VM_IP},"
  local ssh_args; ssh_args="$(_build_ssh_args)"

  # dev_user is the VM-side user that owns the developer toolchain.
  # VM_USER is always "ubuntu" — it is never derived from the host environment.
  ANSIBLE_HOST_KEY_CHECKING=False \
  ansible-playbook \
    -i "${inventory}" \
    --private-key "${VM_SSH_KEY}" \
    --user "${VM_SSH_USER}" \
    --ssh-extra-args "${ssh_args}" \
    --extra-vars "dev_user=${VM_USER}" \
    "${ANSIBLE_DIR}/playbook.yml" \
    2>&1 | tee -a "$LOG_FILE"

  local rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    error "Ansible playbook exited with code ${rc}."
    error "  Full output: ${LOG_FILE}"
    error "  To retry:"
    error "    ansible-playbook -i '${VM_SSH_USER}@${VM_IP},' \\"
    error "      --private-key ${VM_SSH_KEY} \\"
    error "      --extra-vars 'dev_user=${VM_USER}' \\"
    error "      ${ANSIBLE_DIR}/playbook.yml"
    return 1
  fi

  success "Ansible provisioning complete."
}

# --------------------------------------------------------------------------- #
# clone_kv_backend
# Clones the kv-backend repo inside the VM via SSH.
# Skips gracefully if already present or SSH key not yet on GitHub.
# --------------------------------------------------------------------------- #
clone_kv_backend() {
  banner "Cloning kv-backend"

  vm_exec "
    KV_DIR=\$HOME/workspace/repos/kv-backend
    if [[ -d \"\$KV_DIR/.git\" ]]; then
      echo 'kv-backend already cloned — skipping.'
    else
      mkdir -p \"\$(dirname \$KV_DIR)\"
      if git clone git@github.com:knowledgevault/kv-backend.git \"\$KV_DIR\" 2>&1; then
        echo 'kv-backend cloned successfully.'
      else
        echo 'WARNING: kv-backend clone failed.'
        echo 'Add your SSH key to GitHub then run inside the VM:'
        echo '  git clone git@github.com:knowledgevault/kv-backend.git ~/workspace/repos/kv-backend'
      fi
    fi
  " 2>&1 | tee -a "$LOG_FILE"
}

# --------------------------------------------------------------------------- #
# start_kv_services
# Starts the kv-backend Docker Compose stack inside the VM.
# --------------------------------------------------------------------------- #
start_kv_services() {
  banner "Starting kv-backend Services"

  vm_exec "
    BOOTSTRAP=\$HOME/dev-environment/workstation-bootstrap
    if [[ -d \"\$BOOTSTRAP\" ]]; then
      cd \"\$BOOTSTRAP\"
      make kv-up 2>&1 \
        || echo 'WARNING: kv-up failed. Run inside VM: cd ~/dev-environment/workstation-bootstrap && make kv-up'
    else
      echo 'workstation-bootstrap not found inside VM — skipping kv-up.'
    fi
  " 2>&1 | tee -a "$LOG_FILE"
}
