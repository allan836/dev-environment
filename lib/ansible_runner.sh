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
# Clones the kv-backend repo into ~/workspace/repos/kv-backend inside the VM.
# Called immediately after setup_ssh_key() has verified the GitHub connection.
# KV_BACKEND_REPO is set in config.env.
# --------------------------------------------------------------------------- #
clone_kv_backend() {
  banner "Cloning kv-backend"

  local repo="${KV_BACKEND_REPO:-git@github.com:Klantenvertellen-NextGen/kv-backend.git}"
  local kv_dir='$HOME/workspace/repos/kv-backend'

  info "Repository: ${repo}"
  info "Destination (inside VM): ~/workspace/repos/kv-backend"

  local clone_out clone_rc=0
  clone_out="$(vm_exec "
    set -euo pipefail
    KV_DIR=${kv_dir}
    if [[ -d \"\$KV_DIR/.git\" ]]; then
      echo 'kv-backend already cloned — skipping.'
      exit 0
    fi
    mkdir -p \"\$(dirname \"\$KV_DIR\")\"
    GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=accept-new' \
      git clone ${repo} \"\$KV_DIR\" 2>&1
    echo 'kv-backend cloned successfully.'
  " 2>&1)" || clone_rc=$?

  echo "${clone_out}" | tee -a "$LOG_FILE"

  if [[ ${clone_rc} -ne 0 ]]; then
    error "kv-backend clone failed (exit ${clone_rc})."
    error "The GitHub SSH key was verified — this is likely a repository permission issue."
    error "Check that your GitHub account has access to: ${repo}"
    error "To retry inside the VM:"
    error "  ssh -i ~/.ssh/dev-env ${VM_SSH_USER}@${VM_IP}"
    error "  git clone ${repo} ~/workspace/repos/kv-backend"
    return 1
  fi
}

# --------------------------------------------------------------------------- #
# download_kv_assets
# Downloads the pre-built Docker image tarball into the VM so that
# 'make kv-up' does not have to pull all images from Docker Hub on first run.
#
# The tarball is placed at ~/dev-environment/assets/preload_kv.tar.gz, which
# is where the kv_backend Ansible role's Docker load task looks for it.
#
# Skips silently if KV_BACKEND_TARBALL_URL is empty.
# --------------------------------------------------------------------------- #
download_kv_assets() {
  if [[ -z "${KV_BACKEND_TARBALL_URL:-}" ]]; then
    info "KV_BACKEND_TARBALL_URL not set — skipping Docker image tarball download."
    return 0
  fi

  banner "Downloading kv-backend Docker image tarball"
  info "URL: ${KV_BACKEND_TARBALL_URL}"
  info "Destination (inside VM): ~/dev-environment/assets/preload_kv.tar.gz"

  local dl_out dl_rc=0
  dl_out="$(vm_exec "
    set -euo pipefail
    DEST=\$HOME/dev-environment/assets/preload_kv.tar.gz
    if [[ -f \"\$DEST\" ]]; then
      echo 'Tarball already present — skipping download.'
      exit 0
    fi
    mkdir -p \"\$(dirname \"\$DEST\")\"
    echo 'Downloading tarball (this may take a few minutes)...'
    # Google Drive large-file download: the first request returns a cookie-gated
    # confirmation page; follow it with the confirm token to get the real file.
    COOKIEJAR=\$(mktemp /tmp/gdrive-cookies-XXXXXX)
    curl -fsSL --max-time 30 \
      --cookie-jar \"\$COOKIEJAR\" \
      '${KV_BACKEND_TARBALL_URL}' -o /dev/null
    curl -fL --progress-bar --max-time 1800 \
      --cookie \"\$COOKIEJAR\" \
      '${KV_BACKEND_TARBALL_URL}' -o \"\$DEST\"
    rm -f \"\$COOKIEJAR\"
    echo 'Tarball downloaded: '\$(du -sh \"\$DEST\" | cut -f1)
  " 2>&1)" || dl_rc=$?

  echo "${dl_out}" | tee -a "$LOG_FILE"

  if [[ ${dl_rc} -ne 0 ]]; then
    warn "Tarball download failed (exit ${dl_rc}) — Docker images will be pulled from Hub on first kv-up."
    warn "To retry: ssh -i ~/.ssh/dev-env ${VM_SSH_USER}@${VM_IP}"
    warn "  curl -fL '${KV_BACKEND_TARBALL_URL}' -o ~/dev-environment/assets/preload_kv.tar.gz"
    return 0
  fi
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
