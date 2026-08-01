#!/usr/bin/env bash
# =============================================================================
# lib/ansible_runner.sh — Ansible provisioning inside the VM
#
# Runs the Ansible playbook that installs all developer tools.
# Ansible runs INSIDE the VM over vagrant ssh (ansible_local provisioner
# is also configured in the Vagrantfile for first-boot; this handles reruns).
#
# Requires:
#   lib/log.sh sourced
#   VM_DIR, ANSIBLE_DIR, LOG_FILE, DEV_USER, SKIP_ANSIBLE exported
# =============================================================================

# --------------------------------------------------------------------------- #
# run_ansible
# Installs Ansible inside the VM if needed, then runs the playbook.
# --------------------------------------------------------------------------- #
run_ansible() {
  if [[ "${SKIP_ANSIBLE:-false}" == "true" ]]; then
    warn "--skip-ansible set. Skipping Ansible provisioning."
    return 0
  fi

  banner "Provisioning VM"
  cd "$VM_DIR"

  info "Ensuring Ansible is installed inside the VM..."
  vagrant ssh -c "
    if ! command -v ansible >/dev/null 2>&1; then
      sudo apt-get update -qq
      sudo apt-get install -y ansible
    fi
    ansible --version | head -n1
  " 2>&1 | tee -a "$LOG_FILE"

  info "Running Ansible playbook (installs all developer tools)..."
  info "This typically takes 10–20 minutes on first run."
  vagrant ssh -c "
    cd ~/dev-environment/ansible
    ansible-playbook playbook.yml \
      -i inventory/hosts.yml \
      --extra-vars 'dev_user=${DEV_USER}' \
      2>&1
  " | tee -a "$LOG_FILE"

  local rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    error "Ansible playbook exited with code ${rc}."
    error "  Check ${LOG_FILE} for the full output."
    error "  To retry provisioning only: vagrant ssh -c 'cd ~/dev-environment/ansible && ansible-playbook playbook.yml -i inventory/hosts.yml'"
    return 1
  fi

  success "Ansible provisioning complete."
}

# --------------------------------------------------------------------------- #
# clone_kv_backend
# Clones the kv-backend repository inside the VM.
# Skips gracefully if already present or if SSH key is not yet on GitHub.
# --------------------------------------------------------------------------- #
clone_kv_backend() {
  banner "Cloning kv-backend"
  cd "$VM_DIR"

  vagrant ssh -c "
    KV_DIR=\$HOME/workspace/repos/kv-backend
    if [[ -d \"\$KV_DIR/.git\" ]]; then
      echo 'kv-backend already cloned — skipping.'
    else
      mkdir -p \"\$(dirname \$KV_DIR)\"
      if git clone git@github.com:knowledgevault/kv-backend.git \"\$KV_DIR\" 2>&1; then
        echo 'kv-backend cloned successfully.'
      else
        echo 'WARNING: kv-backend clone failed.'
        echo 'Check that your SSH key has been added to GitHub and re-run:'
        echo '  cd vm && vagrant ssh'
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
  cd "$VM_DIR"

  vagrant ssh -c "
    BOOTSTRAP=\$HOME/dev-environment/workstation-bootstrap
    if [[ -d \"\$BOOTSTRAP\" ]]; then
      cd \"\$BOOTSTRAP\"
      make kv-up 2>&1 \
        || echo 'WARNING: kv-up failed. Run: cd ~/dev-environment/workstation-bootstrap && make kv-up'
    else
      echo 'workstation-bootstrap not found inside VM — skipping kv-up.'
    fi
  " 2>&1 | tee -a "$LOG_FILE"
}
