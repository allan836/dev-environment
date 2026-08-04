#!/usr/bin/env bash
# =============================================================================
# lib/recovery.sh — SSH failure detection and assisted recovery
#
# Invoked when wait_for_ssh() times out.  Attempts to restore SSH access
# automatically using each provider's native in-band execution channel
# (which does not require SSH), then falls back to guided manual steps.
#
# Recovery strategy per provider
# ───────────────────────────────
#   multipass  — multipass exec (bypasses SSH entirely)
#                Injects the correct authorized_keys file and enables
#                password authentication as a belt-and-suspenders fallback.
#
#   incus      — incus exec (same principle as multipass)
#
#   libvirt    — Tries in order:
#                  1. virt-customize: offline disk repair (VM shut down,
#                     keys written directly to qcow2, VM restarted).
#                  2. virsh set-user-password: if the QEMU guest agent is
#                     running inside the VM.
#                  3. Guided manual steps: exact commands for the user to
#                     run at the virsh console.
#
# Design constraints honoured
# ───────────────────────────
#   • Passwords are never hardcoded.  Every recovery password is generated
#     fresh from /dev/urandom at runtime and is only ever shown once.
#   • Recovery only activates after SSH has definitively timed out.
#   • The existing SSH-first workflow is untouched on the happy path.
#   • Idempotent: safe to call again via ./provision.sh --resume.
#
# Exports (after ssh_recovery completes)
# ───────────────────────────────────────
#   RECOVERY_ACTIVATED  — "true"  when recovery was needed and attempted
#   RECOVERY_METHOD     — "auto"  (provider exec fixed it transparently)
#                       | "manual" (user must follow printed instructions)
#
# State file (for --resume)
# ──────────────────────────
#   save_provision_state  writes ${REPO_ROOT}/.provision-state
#   load_provision_state  reads  ${REPO_ROOT}/.provision-state and exports
#                         VM_NAME, VM_IP, VM_SSH_USER, VM_SSH_PORT,
#                         ACTIVE_PROVIDER, VM_SSH_KEY
#
# Requires: lib/log.sh sourced.
#           VM_NAME, VM_IP, VM_SSH_USER, VM_SSH_PORT, VM_SSH_KEY,
#           ACTIVE_PROVIDER, REPO_ROOT, LOG_FILE exported.
# =============================================================================

# Public flags set by ssh_recovery()
RECOVERY_ACTIVATED="false"
RECOVERY_METHOD=""
export RECOVERY_ACTIVATED RECOVERY_METHOD

# How long to wait for SSH to come back after automatic credential injection
_RECOVERY_RETRY_TIMEOUT=300   # 5 minutes (seconds)

# How long to wait after telling the user to fix things manually
_RECOVERY_MANUAL_TIMEOUT=1200  # 20 minutes (seconds)

# Path to the VM state file written after a successful boot
_PROVISION_STATE_FILE="${REPO_ROOT}/.provision-state"

# --------------------------------------------------------------------------- #
# _recovery_gen_password
# Generates a 24-character alphanumeric random password.
# stdout: the password string
# --------------------------------------------------------------------------- #
_recovery_gen_password() {
  # openssl rand gives uniform-random bytes; base64 encodes them; tr strips the
  # non-alphanumeric base64 characters (+, /, =).  We ask for more bytes than
  # needed so head -c 24 is always satisfied even after stripping.
  openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24
}

# --------------------------------------------------------------------------- #
# _recovery_print_credentials  PASSWORD
# Prints the recovery credentials box to stdout.
# --------------------------------------------------------------------------- #
_recovery_print_credentials() {
  local password="$1"
  echo ""
  echo -e "${_YELLOW}${_BOLD}"
  echo "  ╔══════════════════════════════════════════════════════╗"
  echo "  ║                                                      ║"
  echo "  ║   SSH PROVISIONING FAILED — RECOVERY MODE ACTIVE     ║"
  echo "  ║                                                      ║"
  echo "  ║   The VM is running but SSH key auth did not work.   ║"
  echo "  ║   Temporary recovery credentials have been set:      ║"
  echo "  ║                                                      ║"
  printf "  ║   Username : %-38s║\n" "ubuntu"
  printf "  ║   Password : %-38s║\n" "${password}"
  echo "  ║                                                      ║"
  printf "  ║   VM IP    : %-38s║\n" "${VM_IP}"
  echo "  ║                                                      ║"
  echo "  ╚══════════════════════════════════════════════════════╝"
  echo -e "${_RESET}"
}

# --------------------------------------------------------------------------- #
# _recovery_print_console_access
# Prints the provider-specific console/login instructions.
# --------------------------------------------------------------------------- #
_recovery_print_console_access() {
  echo ""
  echo -e "${_BOLD}Open the VM console:${_RESET}"
  echo ""
  case "${ACTIVE_PROVIDER}" in
    libvirt)
      echo "    virt-viewer ${VM_NAME}"
      echo "  or"
      echo "    virt-manager   (select '${VM_NAME}' → Open console)"
      echo "  or (text console)"
      echo "    virsh console ${VM_NAME}"
      echo "  (Press Ctrl+] to exit the virsh console)"
      ;;
    multipass)
      echo "    multipass shell ${VM_NAME}"
      ;;
    incus)
      echo "    incus console ${VM_NAME}"
      ;;
    *)
      echo "    Open the VM console via your hypervisor."
      ;;
  esac
  echo ""
}

# --------------------------------------------------------------------------- #
# _recovery_print_diagnostic_commands
# Prints the exact commands the user should run once logged into the VM.
# --------------------------------------------------------------------------- #
_recovery_print_diagnostic_commands() {
  local pub_key_file="${VM_SSH_KEY}.pub"
  local pub_key=""
  [[ -f "${pub_key_file}" ]] && pub_key="$(cat "${pub_key_file}")"

  echo ""
  echo -e "${_BOLD}Once logged in, run these commands to diagnose:${_RESET}"
  echo ""
  echo "    sudo cloud-init status"
  echo "    sudo cloud-init analyze show"
  echo "    sudo cat /var/log/cloud-init-output.log | tail -50"
  echo "    sudo cat /var/log/cloud-init.log        | tail -50"
  echo ""
  echo -e "${_BOLD}To repair SSH key authentication manually:${_RESET}"
  echo ""
  echo "    mkdir -p ~/.ssh && chmod 700 ~/.ssh"
  if [[ -n "${pub_key}" ]]; then
    echo "    echo '${pub_key}' >> ~/.ssh/authorized_keys"
  else
    echo "    echo '<paste your ~/.ssh/dev-env.pub here>' >> ~/.ssh/authorized_keys"
  fi
  echo "    chmod 600 ~/.ssh/authorized_keys"
  echo ""
  echo -e "${_BOLD}To re-run cloud-init (if first-boot failed partway through):${_RESET}"
  echo ""
  echo "    sudo rm -f /etc/cloud/cloud-init.disabled"
  echo "    sudo cloud-init clean --logs"
  echo "    sudo cloud-init init"
  echo "    sudo cloud-init modules --mode config"
  echo "    sudo cloud-init modules --mode final"
  echo ""
  echo -e "${_BOLD}After SSH is repaired, resume provisioning from the host:${_RESET}"
  echo ""
  echo "    ./provision.sh --resume"
  echo ""
}

# --------------------------------------------------------------------------- #
# _recovery_inject_via_exec  EXEC_PREFIX...
#
# Runs a self-contained repair script inside the VM using an in-band exec
# channel (multipass exec or incus exec) that does not require SSH.
#
# The repair script:
#   1. Writes the correct authorized_keys for the ubuntu and developer users
#   2. Enables SSH password authentication (belt-and-suspenders fallback)
#   3. Restarts the SSH daemon
#
# The public key is passed base64-encoded to avoid all quoting concerns.
#
# Arguments: EXEC_PREFIX — the provider exec command prefix, e.g.
#              multipass exec dev-env --
#              incus exec dev-env --
#
# Returns 0 on success, 1 if the exec command itself failed.
# --------------------------------------------------------------------------- #
_recovery_inject_via_exec() {
  local pub_key_file="${VM_SSH_KEY}.pub"

  if [[ ! -f "${pub_key_file}" ]]; then
    error "Recovery: public key not found at ${pub_key_file} — cannot inject credentials."
    return 1
  fi

  local encoded_key
  encoded_key="$(base64 -w0 "${pub_key_file}" 2>/dev/null || base64 "${pub_key_file}")"

  local password
  password="$(_recovery_gen_password)"

  info "Recovery: injecting authorized_keys and recovery password via provider exec..."

  # This script runs INSIDE the VM as root (sudo).
  # It must be self-contained: no host-side variables except what we bake in.
  local inject_script
  inject_script="$(cat <<INNERSCRIPT
set -euo pipefail

ENCODED_KEY='${encoded_key}'
RECOVERY_PASS='${password}'

# Decode the host's provisioning public key
PUB_KEY=\$(echo "\${ENCODED_KEY}" | base64 -d)

# Fix authorized_keys for ubuntu
mkdir -p /home/ubuntu/.ssh
echo "\${PUB_KEY}" > /home/ubuntu/.ssh/authorized_keys
chmod 700 /home/ubuntu/.ssh
chmod 600 /home/ubuntu/.ssh/authorized_keys
chown -R ubuntu:ubuntu /home/ubuntu/.ssh

# Fix authorized_keys for developer (if user exists)
if id developer &>/dev/null; then
  mkdir -p /home/developer/.ssh
  echo "\${PUB_KEY}" > /home/developer/.ssh/authorized_keys
  chmod 700 /home/developer/.ssh
  chmod 600 /home/developer/.ssh/authorized_keys
  chown -R developer:developer /home/developer/.ssh
fi

# Set recovery password on both accounts
printf 'ubuntu:%s\n' "\${RECOVERY_PASS}" | chpasswd
id developer &>/dev/null && printf 'developer:%s\n' "\${RECOVERY_PASS}" | chpasswd || true

# Enable SSH password authentication as a fallback
mkdir -p /etc/ssh/sshd_config.d
printf 'PasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/99-recovery.conf
chmod 0644 /etc/ssh/sshd_config.d/99-recovery.conf

# Re-enable cloud-init so it can finish if it was interrupted
rm -f /etc/cloud/cloud-init.disabled

# Restart SSH daemon (Ubuntu uses 'ssh', RHEL-based use 'sshd')
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true

echo "RECOVERY_INJECT_OK"
INNERSCRIPT
)"

  local exec_rc=0
  local exec_out
  exec_out="$( "$@" sudo bash -c "${inject_script}" 2>&1 )" || exec_rc=$?

  printf 'Recovery inject output:\n%s\n' "${exec_out}" >> "${LOG_FILE}"

  if [[ ${exec_rc} -ne 0 ]] || ! echo "${exec_out}" | grep -q "RECOVERY_INJECT_OK"; then
    error "Recovery exec injection failed (exit ${exec_rc})."
    [[ -n "${exec_out}" ]] && error "Output: ${exec_out}"
    return 1
  fi

  success "Recovery: authorized_keys and password injected successfully."
  _recovery_print_credentials "${password}"
  return 0
}

# --------------------------------------------------------------------------- #
# _recovery_inject_multipass
# Uses multipass exec for credential injection.
# --------------------------------------------------------------------------- #
_recovery_inject_multipass() {
  if ! has multipass; then
    error "Recovery: multipass not found — cannot inject credentials."
    return 1
  fi
  _recovery_inject_via_exec multipass exec "${VM_NAME}" --
}

# --------------------------------------------------------------------------- #
# _recovery_inject_incus
# Uses incus exec for credential injection.
# --------------------------------------------------------------------------- #
_recovery_inject_incus() {
  if ! has incus; then
    error "Recovery: incus not found — cannot inject credentials."
    return 1
  fi
  _recovery_inject_via_exec incus exec "${VM_NAME}" --
}

# --------------------------------------------------------------------------- #
# _recovery_inject_libvirt
# Libvirt recovery — tried in order:
#   1. Offline disk repair via virt-customize  (most reliable; no guest agent)
#   2. virsh set-user-password                 (requires QEMU guest agent)
#   3. Guided manual instructions only
#
# Returns 0 if auto-recovery was attempted (caller should retry SSH).
# Returns 1 if only manual instructions were printed.
# --------------------------------------------------------------------------- #
_recovery_inject_libvirt() {
  local disk_path="${_LIBVIRT_POOL_DIR:-/var/lib/libvirt/images}/${VM_NAME}.qcow2"
  local pub_key_file="${VM_SSH_KEY}.pub"

  if [[ ! -f "${pub_key_file}" ]]; then
    error "Recovery: public key not found at ${pub_key_file}."
    return 1
  fi

  local password
  password="$(_recovery_gen_password)"

  # ------------------------------------------------------------------ #
  # Attempt 1: virt-customize (offline — most reliable)
  # ------------------------------------------------------------------ #
  if has virt-customize && [[ -f "${disk_path}" ]]; then
    info "Recovery: attempting offline disk repair via virt-customize..."
    info "Recovery: shutting VM down for offline disk modification..."

    virsh -c qemu:///system shutdown "${VM_NAME}" 2>>"${LOG_FILE}" || true

    # Wait up to 60 s for the domain to stop
    local elapsed=0
    while [[ $elapsed -lt 60 ]]; do
      local state
      state="$(virsh -c qemu:///system domstate "${VM_NAME}" 2>/dev/null | tr -d '[:space:]' || echo "unknown")"
      [[ "${state}" == "shut off" ]] && break
      sleep 3
      elapsed=$(( elapsed + 3 ))
    done

    local final_state
    final_state="$(virsh -c qemu:///system domstate "${VM_NAME}" 2>/dev/null | tr -d '[:space:]' || echo "unknown")"
    if [[ "${final_state}" != "shut off" ]]; then
      warn "Recovery: graceful shutdown timed out — forcing off..."
      virsh -c qemu:///system destroy "${VM_NAME}" 2>>"${LOG_FILE}" || true
      sleep 3
    fi

    # Write the public key to a temp file so virt-customize --upload can use
    # it — avoids all quoting issues with key content.
    local tmp_pubkey
    tmp_pubkey="$(mktemp /tmp/recovery-pubkey-XXXXXX)"
    cat "${pub_key_file}" > "${tmp_pubkey}"

    local vc_rc=0
    virt-customize \
      -a "${disk_path}" \
      --root-password "password:${password}" \
      --upload "${tmp_pubkey}:/tmp/recovery.pub" \
      --run-command "mkdir -p /home/ubuntu/.ssh" \
      --run-command "cp /tmp/recovery.pub /home/ubuntu/.ssh/authorized_keys" \
      --run-command "chmod 700 /home/ubuntu/.ssh && chmod 600 /home/ubuntu/.ssh/authorized_keys && chown -R ubuntu:ubuntu /home/ubuntu/.ssh" \
      --run-command "id developer &>/dev/null && mkdir -p /home/developer/.ssh && cp /tmp/recovery.pub /home/developer/.ssh/authorized_keys && chmod 700 /home/developer/.ssh && chmod 600 /home/developer/.ssh/authorized_keys && chown -R developer:developer /home/developer/.ssh || true" \
      --run-command "printf 'ubuntu:%s\n' '${password}' | chpasswd" \
      --run-command "id developer &>/dev/null && printf 'developer:%s\n' '${password}' | chpasswd || true" \
      --run-command "mkdir -p /etc/ssh/sshd_config.d && printf 'PasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/99-recovery.conf && chmod 0644 /etc/ssh/sshd_config.d/99-recovery.conf" \
      --run-command "rm -f /etc/cloud/cloud-init.disabled" \
      --run-command "rm -f /tmp/recovery.pub" \
      2>>"${LOG_FILE}" || vc_rc=$?

    rm -f "${tmp_pubkey}"

    if [[ ${vc_rc} -eq 0 ]]; then
      success "Recovery: disk repaired via virt-customize."
      info "Recovery: restarting VM..."
      virsh -c qemu:///system start "${VM_NAME}" 2>>"${LOG_FILE}" || true

      # Re-acquire the IP (the VM just rebooted)
      if _libvirt_get_ip 120; then
        VM_IP="${_LIBVIRT_VM_IP}"
        export VM_IP
        success "Recovery: VM is back up at ${VM_IP}."
      else
        warn "Recovery: could not re-acquire IP after restart — retrying SSH at ${VM_IP}."
      fi

      _recovery_print_credentials "${password}"
      return 0
    else
      warn "Recovery: virt-customize failed (exit ${vc_rc}) — trying next method."
      # The VM may still be stopped; bring it back up before attempting other methods
      virsh -c qemu:///system start "${VM_NAME}" 2>>"${LOG_FILE}" || true
      sleep 10
    fi
  fi

  # ------------------------------------------------------------------ #
  # Attempt 2: virsh set-user-password (requires QEMU guest agent)
  # ------------------------------------------------------------------ #
  local ga_rc=0
  virsh -c qemu:///system qemu-agent-command "${VM_NAME}" \
    '{"execute":"guest-ping"}' &>>"${LOG_FILE}" || ga_rc=$?

  if [[ ${ga_rc} -eq 0 ]]; then
    info "Recovery: QEMU guest agent detected — setting recovery password..."
    local pu_rc=0
    virsh -c qemu:///system set-user-password "${VM_NAME}" ubuntu "${password}" \
      &>>"${LOG_FILE}" || pu_rc=$?
    if [[ ${pu_rc} -eq 0 ]]; then
      success "Recovery: password set for ubuntu via guest agent."
      virsh -c qemu:///system set-user-password "${VM_NAME}" developer "${password}" \
        &>>"${LOG_FILE}" || true
      # Guest-agent exec to enable password auth and fix authorized_keys
      local encoded_key
      encoded_key="$(base64 -w0 "${pub_key_file}" 2>/dev/null || base64 "${pub_key_file}")"
      local ga_cmd
      # shellcheck disable=SC2016
      # $PK is intentionally not expanded on the host — it expands inside the VM.
      ga_cmd="$(printf \
        'PK=%s; mkdir -p /home/ubuntu/.ssh; echo "$PK" | base64 -d > /home/ubuntu/.ssh/authorized_keys; chmod 700 /home/ubuntu/.ssh; chmod 600 /home/ubuntu/.ssh/authorized_keys; chown -R ubuntu:ubuntu /home/ubuntu/.ssh; mkdir -p /etc/ssh/sshd_config.d; echo PasswordAuthentication yes > /etc/ssh/sshd_config.d/99-recovery.conf; systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null' \
        "${encoded_key}")"
      local escaped_cmd ga_exec_json
      escaped_cmd="${ga_cmd//\"/\\\"}"
      ga_exec_json="$(printf '{"execute":"guest-exec","arguments":{"path":"/bin/bash","arg":["-c","%s"],"capture-output":true}}' \
        "${escaped_cmd}")"
      virsh -c qemu:///system qemu-agent-command "${VM_NAME}" "${ga_exec_json}" \
        &>>"${LOG_FILE}" || true
      _recovery_print_credentials "${password}"
      return 0
    fi
    warn "Recovery: virsh set-user-password failed (exit ${pu_rc})."
  fi

  # ------------------------------------------------------------------ #
  # Attempt 3: No automated path available — print manual instructions
  # ------------------------------------------------------------------ #
  warn "Recovery: no automated injection method succeeded for libvirt."
  warn "Recovery: falling back to guided manual recovery."
  return 1
}

# --------------------------------------------------------------------------- #
# _recovery_wait_for_ssh_retry  TIMEOUT_SECONDS
# Polls SSH (key auth) until it succeeds or the timeout is reached.
# Prints a progress indicator.
# Returns 0 if SSH became available, 1 if timeout.
# --------------------------------------------------------------------------- #
_recovery_wait_for_ssh_retry() {
  local timeout="${1:-${_RECOVERY_RETRY_TIMEOUT}}"
  local elapsed=0

  info "Waiting up to ${timeout}s for SSH to become available..."

  while [[ ${elapsed} -lt ${timeout} ]]; do
    if vm_exec "echo ssh-ready" &>/dev/null; then
      echo ""
      success "SSH is available."
      return 0
    fi
    printf "."
    sleep 5
    elapsed=$(( elapsed + 5 ))
  done

  echo ""
  return 1
}

# --------------------------------------------------------------------------- #
# ssh_recovery
#
# Main recovery entry point.  Called by provision.sh when wait_for_ssh()
# returns 1 (SSH authentication timed out).
#
# Behaviour:
#   1. Prints a clear failure notice.
#   2. Attempts automatic credential injection using the provider's exec channel.
#   3. If automatic injection succeeded: waits for SSH to come back, then
#      returns 0 so provisioning can continue transparently.
#   4. If automatic injection failed or SSH still does not work: prints full
#      manual recovery instructions, then waits up to _RECOVERY_MANUAL_TIMEOUT
#      for the user to fix things.  If SSH eventually works, returns 0.
#      If it never works, die()s with a hint to use --resume.
# --------------------------------------------------------------------------- #
ssh_recovery() {
  RECOVERY_ACTIVATED="true"
  export RECOVERY_ACTIVATED

  echo ""
  error "SSH provisioning failed."
  error ""
  error "The VM is running, but SSH key authentication could not be established."
  error "Attempting automatic recovery..."
  echo ""
  printf 'SSH recovery triggered at %s\n' "$(date)" >> "${LOG_FILE}"

  local auto_ok=false

  case "${ACTIVE_PROVIDER}" in
    multipass)
      if _recovery_inject_multipass; then
        auto_ok=true
        RECOVERY_METHOD="auto"
      fi
      ;;
    incus)
      if _recovery_inject_incus; then
        auto_ok=true
        RECOVERY_METHOD="auto"
      fi
      ;;
    libvirt)
      if _recovery_inject_libvirt; then
        auto_ok=true
        RECOVERY_METHOD="auto"
      fi
      ;;
    *)
      warn "Recovery: unknown provider '${ACTIVE_PROVIDER}' — cannot auto-inject."
      ;;
  esac

  export RECOVERY_METHOD

  if [[ "${auto_ok}" == "true" ]]; then
    info "Automatic recovery injection complete — retrying SSH..."
    if _recovery_wait_for_ssh_retry "${_RECOVERY_RETRY_TIMEOUT}"; then
      success "Recovery successful — SSH is working.  Provisioning will continue."
      echo ""
      warn "NOTE: Cloud-init SSH provisioning failed on first boot."
      warn "      Check /var/log/cloud-init-output.log inside the VM for the root cause."
      warn "      The recovery SSH password should be rotated after provisioning."
      echo ""
      RECOVERY_METHOD="auto"
      export RECOVERY_METHOD
      return 0
    fi
    warn "SSH still not available after automatic recovery — restarting clean."
    RECOVERY_METHOD="manual"
    export RECOVERY_METHOD
  else
    RECOVERY_METHOD="manual"
    export RECOVERY_METHOD
  fi

  # ─── Auto-restart path ────────────────────────────────────────────── #
  # Automatic injection failed (or SSH did not recover after injection).
  # Rather than leaving the user staring at a 20-minute manual-wait prompt,
  # print the diagnostic steps for information and then destroy the broken VM
  # and start a completely fresh provision run automatically.
  echo ""
  echo -e "${_YELLOW}${_BOLD}"
  echo "  ╔══════════════════════════════════════════════════════╗"
  echo "  ║                                                      ║"
  echo "  ║   SSH recovery failed — restarting clean             ║"
  echo "  ║                                                      ║"
  echo "  ║   The VM could not be recovered automatically.       ║"
  echo "  ║   Destroying the broken VM and starting fresh.       ║"
  echo "  ║                                                      ║"
  echo "  ╚══════════════════════════════════════════════════════╝"
  echo -e "${_RESET}"

  # Print diagnostics so the user has context in the log.
  _recovery_print_console_access
  _recovery_print_diagnostic_commands

  warn "Diagnostic information printed above (also saved to ${LOG_FILE})."
  warn "Automatically restarting with: ./provision.sh"
  echo ""
  sleep 3

  # exec replaces this process — no subprocess nesting, clean restart.
  exec "${REPO_ROOT}/provision.sh"
}

# --------------------------------------------------------------------------- #
# save_provision_state
#
# Persists the current VM connection details to .provision-state so that
# ./provision.sh --resume can skip the boot phase and go straight to SSH.
# Called immediately after boot_vm() succeeds.
# --------------------------------------------------------------------------- #
save_provision_state() {
  mkdir -p "$(dirname "${_PROVISION_STATE_FILE}")"
  cat > "${_PROVISION_STATE_FILE}" <<EOF
# dev-env provision state — written by provision.sh after successful VM boot.
# Safe to delete; it will be regenerated on the next full provision run.
# DO NOT commit this file (it is listed in .gitignore).
VM_NAME=${VM_NAME}
VM_IP=${VM_IP}
VM_SSH_USER=${VM_SSH_USER}
VM_SSH_PORT=${VM_SSH_PORT:-22}
ACTIVE_PROVIDER=${ACTIVE_PROVIDER}
VM_SSH_KEY=${VM_SSH_KEY}
EOF
  info "Provision state saved to ${_PROVISION_STATE_FILE}"
}

# --------------------------------------------------------------------------- #
# load_provision_state
#
# Reads .provision-state and re-exports the VM connection variables.
# Returns 0 on success, 1 if the state file does not exist or is incomplete.
# --------------------------------------------------------------------------- #
load_provision_state() {
  if [[ ! -f "${_PROVISION_STATE_FILE}" ]]; then
    error "No provision state file found at ${_PROVISION_STATE_FILE}."
    error "Run ./provision.sh (without --resume) to create the VM first."
    return 1
  fi

  # Source the state file in a sub-shell to avoid polluting the environment
  # with unexpected variables, then re-export only the known keys.
  local _svm_name _svm_ip _svm_user _svm_port _svm_provider _svm_key
  _svm_name="$(     grep '^VM_NAME='         "${_PROVISION_STATE_FILE}" | cut -d= -f2-)"
  _svm_ip="$(       grep '^VM_IP='           "${_PROVISION_STATE_FILE}" | cut -d= -f2-)"
  _svm_user="$(     grep '^VM_SSH_USER='     "${_PROVISION_STATE_FILE}" | cut -d= -f2-)"
  _svm_port="$(     grep '^VM_SSH_PORT='     "${_PROVISION_STATE_FILE}" | cut -d= -f2-)"
  _svm_provider="$( grep '^ACTIVE_PROVIDER=' "${_PROVISION_STATE_FILE}" | cut -d= -f2-)"
  _svm_key="$(      grep '^VM_SSH_KEY='      "${_PROVISION_STATE_FILE}" | cut -d= -f2-)"

  if [[ -z "${_svm_ip}" || -z "${_svm_provider}" ]]; then
    error "Provision state file is incomplete — missing VM_IP or ACTIVE_PROVIDER."
    error "Delete ${_PROVISION_STATE_FILE} and run ./provision.sh to start fresh."
    return 1
  fi

  VM_NAME="${_svm_name}"
  VM_IP="${_svm_ip}"
  VM_SSH_USER="${_svm_user:-ubuntu}"
  VM_SSH_PORT="${_svm_port:-22}"
  ACTIVE_PROVIDER="${_svm_provider}"
  VM_SSH_KEY="${_svm_key:-${HOME}/.ssh/dev-env}"

  export VM_NAME VM_IP VM_SSH_USER VM_SSH_PORT ACTIVE_PROVIDER VM_SSH_KEY

  success "Loaded provision state: ${ACTIVE_PROVIDER} / ${VM_SSH_USER}@${VM_IP}:${VM_SSH_PORT}"
  return 0
}