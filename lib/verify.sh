#!/usr/bin/env bash
# =============================================================================
# lib/verify.sh — Post-provisioning verification
#
# Copies the verification script into the VM and runs it over SSH.
# Produces a structured pass/fail summary; exits non-zero if any required
# check fails.
#
# Requires: lib/log.sh, lib/vm.sh (vm_exec, vm_push) sourced.
#           VM_IP, VM_SSH_USER, VM_SSH_KEY, VM_SSH_PORT, LOG_FILE exported.
# =============================================================================

# --------------------------------------------------------------------------- #
# run_verify
# --------------------------------------------------------------------------- #
run_verify() {
  banner "Verification"

  local remote_script="/tmp/_verify_inside_vm.sh"

  info "Copying verification script to VM..."
  vm_push "${REPO_ROOT}/lib/_verify_inside_vm.sh" "${remote_script}"

  info "Running verification checks inside VM..."
  vm_exec "bash ${remote_script}" 2>&1 | tee -a "$LOG_FILE"

  local rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    error "Verification found missing or failed components."
    error "Review the summary above and re-run ./provision.sh to attempt repair."
    return 1
  fi

  success "All verification checks passed."
}
