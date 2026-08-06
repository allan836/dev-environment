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
# Downloads the pre-built Docker image tarball onto the HOST first, then
# pushes it into the VM.  This avoids Google Drive downloads failing inside
# the VM (cookie/consent pages produce corrupt HTML instead of the real file).
#
# The tarball is placed at:
#   Host: ${REPO_ROOT}/assets/preload_kv.tar.gz
#   VM:   ~/dev-environment/assets/preload_kv.tar.gz
#
# If the tarball already exists on the host, the download is skipped and the
# file is just pushed to the VM (if the VM doesn't already have it).
#
# Skips silently if KV_BACKEND_TARBALL_URL is empty.
# --------------------------------------------------------------------------- #
download_kv_assets() {
  if [[ -z "${KV_BACKEND_TARBALL_URL:-}" ]]; then
    info "KV_BACKEND_TARBALL_URL not set — skipping Docker image tarball download."
    return 0
  fi

  local host_tarball="${REPO_ROOT}/assets/preload_kv.tar.gz"
  local vm_tarball='$HOME/dev-environment/assets/preload_kv.tar.gz'

  banner "Downloading kv-backend Docker image tarball"
  info "URL: ${KV_BACKEND_TARBALL_URL}"
  info "Host destination: ${host_tarball}"
  info "VM destination: ~/dev-environment/assets/preload_kv.tar.gz"

  # ── Step 1: Download on the HOST if not already present ──────────────── #
  if [[ -f "${host_tarball}" ]]; then
    info "Tarball already present on host — skipping download."
  else
    info "Downloading tarball to host (~750 MB, this may take several minutes)..."
    mkdir -p "$(dirname "${host_tarball}")"

    local dl_rc=0
    # Public HTTPS download — no AWS credentials required.
    # curl progress goes to stderr (terminal) so the % column is visible.
    curl -fL \
      -o "${host_tarball}" \
      "${KV_BACKEND_TARBALL_URL}" || dl_rc=$?

    if [[ ${dl_rc} -ne 0 ]]; then
      warn "Tarball download failed (exit ${dl_rc})."
      warn "Docker images will be pulled from Hub on first kv-up."
      rm -f "${host_tarball}"
      return 0
    fi

    # Validate the downloaded file is actually a gzip/tar archive.
    if ! file "${host_tarball}" | grep -qE 'gzip|tar archive'; then
      warn "Downloaded tarball is not a valid gzip/tar file."
      warn "Removing corrupt file. Docker images will be pulled from Hub on first kv-up."
      rm -f "${host_tarball}"
      return 0
    fi

    info "Tarball downloaded: $(du -sh "${host_tarball}" | cut -f1)"
  fi

  # ── Step 2: Push to VM if not already present ────────────────────────── #
  local vm_has_tarball
  vm_has_tarball="$(vm_exec "test -f ${vm_tarball} && echo yes || echo no" 2>/dev/null || echo no)"

  if [[ "${vm_has_tarball}" == "yes" ]]; then
    info "Tarball already present in VM — skipping push."
    return 0
  fi

  info "Pushing tarball to VM (~$(du -sh "${host_tarball}" 2>/dev/null | cut -f1))..."
  vm_exec "mkdir -p \$HOME/dev-environment/assets" 2>/dev/null || true
  # rsync over SSH gives a proper progress bar (%, speed, ETA) unlike scp.
  if command -v rsync >/dev/null 2>&1; then
    rsync --progress --human-readable \
      -e "ssh -i ${VM_SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p ${VM_SSH_PORT:-22}" \
      "${host_tarball}" \
      "${VM_SSH_USER}@${VM_IP}:/home/${VM_USER}/dev-environment/assets/preload_kv.tar.gz"
  else
    # Fallback to scp if rsync is not available (no progress bar).
    vm_push "${host_tarball}" "/home/${VM_USER}/dev-environment/assets/preload_kv.tar.gz"
  fi
  success "Tarball pushed to VM."
}

# --------------------------------------------------------------------------- #
# _push_kv_env
# Copies the host-side kv-backend secrets file into the VM so that
# sshprovision.sh can run in --ci mode (no interactive prompts).
#
# Lookup order for the host-side file:
#   1. ${KV_ENV_FILE}  environment variable (CI override)
#   2. ${REPO_ROOT}/kv-backend.env
#   3. ${REPO_ROOT}/preload-docker-compose/.env  (legacy location)
#
# If none exist, the function prints guidance and returns 1 so the caller
# can decide whether to abort or continue with a degraded run.
# --------------------------------------------------------------------------- #
_push_kv_env() {
  local remote_env_path='$HOME/workspace/repos/kv-backend/preload-docker-compose/.env'

  # ── Check whether the VM already has a valid .env ─────────────────────── #
  local remote_has_env
  remote_has_env="$(vm_exec "
    f=\$HOME/workspace/repos/kv-backend/preload-docker-compose/.env
    if [[ -f \"\$f\" ]] && grep -q '^NEXUS_USERNAME=[^[:space:]]' \"\$f\" 2>/dev/null; then
      echo yes
    else
      echo no
    fi
  " 2>/dev/null || echo no)"

  if [[ "${remote_has_env}" == "yes" ]]; then
    info "VM already has a valid kv-backend .env — skipping push."
    return 0
  fi

  # ── Find the host-side secrets file ───────────────────────────────────── #
  local host_env=""
  local candidates=(
    "${KV_ENV_FILE:-}"
    "${REPO_ROOT}/kv-backend.env"
    "${REPO_ROOT}/preload-docker-compose/.env"
  )
  for f in "${candidates[@]}"; do
    [[ -z "${f}" ]] && continue
    if [[ -f "${f}" ]]; then
      host_env="${f}"
      break
    fi
  done

  if [[ -z "${host_env}" ]]; then
    warn "No host-side kv-backend secrets file found."
    warn "sshprovision.sh will run in non-interactive mode and FAIL if"
    warn "~/workspace/repos/kv-backend/preload-docker-compose/.env is absent."
    warn ""
    warn "To pre-seed secrets, create one of these files on the HOST:"
    warn "  ${REPO_ROOT}/kv-backend.env   (recommended)"
    warn "  ${REPO_ROOT}/preload-docker-compose/.env"
    warn "  export KV_ENV_FILE=/path/to/file"
    warn ""
    warn "Template: ${REPO_ROOT}/preload-docker-compose/.env.template"
    warn "          (if present in the kv-backend repo checkout)"
    return 1
  fi

  info "Pushing kv-backend secrets to VM: ${host_env} → preload-docker-compose/.env"
  vm_push "${host_env}" \
    "/home/${VM_USER}/workspace/repos/kv-backend/preload-docker-compose/.env"
  success "kv-backend .env pushed to VM."
}

# --------------------------------------------------------------------------- #
# start_kv_services
# SSHes into the VM and runs preload-docker-compose/sshprovision.sh in --ci
# mode (non-interactive).  Secrets are pre-seeded by _push_kv_env() which
# copies the host-side kv-backend.env before the script runs.
# --------------------------------------------------------------------------- #
start_kv_services() {
  banner "Running sshprovision.sh inside VM"

  local script_path='$HOME/workspace/repos/kv-backend/preload-docker-compose/sshprovision.sh'

  info "Script path (inside VM): ~/workspace/repos/kv-backend/preload-docker-compose/sshprovision.sh"

  # Push the host .env into the VM so sshprovision.sh runs in --ci mode.
  # _push_kv_env() warns if no host file is found but does NOT abort; the
  # script itself will give a clear error if NEXUS_USERNAME is still missing.
  _push_kv_env || true

  # Remove corrupt preload tarball from a previous run.
  vm_exec "
    TARBALL=\$HOME/dev-environment/assets/preload_kv.tar.gz
    if [[ -f \"\$TARBALL\" ]] && ! file \"\$TARBALL\" | grep -qE 'gzip|tar archive'; then
      echo 'Removing corrupt preload tarball from previous run...'
      rm -f \"\$TARBALL\"
    fi
  " 2>/dev/null || true

  vm_exec "
    set -euo pipefail

    # nvm is shell-function based and is only loaded via ~/.bashrc in interactive
    # sessions.  Non-interactive SSH (vm_exec) never sources .bashrc, so we must
    # initialise nvm explicitly to put 'node' and 'npm' on PATH.
    export NVM_DIR=\"\$HOME/.nvm\"
    if [[ -s \"\$NVM_DIR/nvm.sh\" ]]; then
      . \"\$NVM_DIR/nvm.sh\" --no-use
      nvm use default 2>/dev/null || nvm use node 2>/dev/null || true
    fi

    SCRIPT=${script_path}
    if [[ ! -f \"\$SCRIPT\" ]]; then
      echo 'ERROR: sshprovision.sh not found at \$SCRIPT'
      echo 'Ensure clone_kv_backend() completed successfully before this step.'
      exit 1
    fi
    chmod +x \"\$SCRIPT\"
    cd \"\$(dirname \"\$SCRIPT\")\"
    bash \"\$SCRIPT\" --ci 2>&1
  " 2>&1 | tee -a "$LOG_FILE"

  local rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    error "sshprovision.sh exited with code ${rc}."
    error "  Full output: ${LOG_FILE}"
    error "  To retry inside the VM:"
    error "    ssh -i ~/.ssh/dev-env ${VM_SSH_USER}@${VM_IP}"
    error "    cd ~/workspace/repos/kv-backend/preload-docker-compose"
    error "    ./sshprovision.sh"
    return 1
  fi

  success "sshprovision.sh completed — kv-backend stack is up."
}
