#!/usr/bin/env bash
# =============================================================================
# lib/verify.sh — Post-provisioning verification
#
# Runs inside the VM and checks that every required tool is installed.
# Produces a structured pass/fail summary.
# Exits 0 only if ALL required checks pass.
#
# Requires: lib/log.sh sourced, VM_DIR exported.
# =============================================================================

# --------------------------------------------------------------------------- #
# run_verify
# SSH into the VM and run the verification checks.
# --------------------------------------------------------------------------- #
run_verify() {
  banner "Verification"
  cd "$VM_DIR"

  # Run the full verification script inside the VM.
  # The script is sourced from the shared mount (dev-environment is mounted
  # at ~/dev-environment inside the VM via the Vagrantfile synced_folder).
  vagrant ssh -c "bash ~/dev-environment/lib/_verify_inside_vm.sh" 2>&1 \
    | tee -a "$LOG_FILE"

  local rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    error "Verification found missing or failed components."
    error "Review the summary above and re-run ./provision.sh to attempt repair."
    return 1
  fi

  success "All verification checks passed."
}
