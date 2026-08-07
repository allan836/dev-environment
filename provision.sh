#!/usr/bin/env bash
# =============================================================================
# provision.sh — Developer Environment Provisioner
#
# USAGE:
#   ./provision.sh [OPTIONS]
#
# OPTIONS:
#   --name   NAME   VM name              (default: dev-env)
#   --cpu    N      vCPU count           (default: 4)
#   --ram    N      RAM in MB            (default: 8192)
#   --disk   N      Disk in GB           (default: 40)
#   --provider NAME Force provider       (multipass | libvirt | incus)
#   --skip-ansible  Boot VM only, skip Ansible provisioning
#   --clean         Nuke the existing VM and all its artifacts, then start a
#                   completely fresh provision run.  Equivalent to manually
#                   running virsh destroy / undefine / rm qcow2 / rm seed.iso
#                   followed by ./provision.sh.  Use this when testing changes.
#   --destroy       Destroy existing VM first, then reprovision
#   --resume        Skip VM creation; re-use a running VM from a previous run.
#                   Reads connection details from .provision-state (written
#                   automatically after a successful boot).  Use this after
#                   SSH recovery to complete provisioning without recreating
#                   the VM.
#   --debug         Print every virt-install/virsh/cloud-init command before execution
#   --dev-mode      [DEVELOPMENT ONLY] Inject password SSH auth into VM; prints
#                   the one-time password to stdout. Never use in production.
#   -h, --help      Show this help
#
# PREREQUISITES:
#   - git (you already have it — you cloned this repo)
#   - curl
#   - Internet access
#   Everything else (Multipass / libvirt / Incus, Ansible) is installed
#   automatically.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --------------------------------------------------------------------------- #
# SSH rescue: when the script dies after SSH is up, drop the user into an
# interactive SSH session on the VM so they can inspect / debug / retry.
# _SSH_READY is flipped true once wait_for_ssh succeeds; the trap is a no-op
# before that point because the VM is not yet reachable.
# --------------------------------------------------------------------------- #
_SSH_READY=false
_SSH_FAILED_STEP=""

_drop_to_ssh() {
  if [[ "${_SSH_READY}" != "true" ]]; then
    return
  fi

  # If SSH variables are missing (edge case), try loading saved state.
  if [[ -z "${VM_IP:-}" || -z "${VM_SSH_KEY:-}" ]]; then
    load_provision_state 2>/dev/null || return
  fi

  echo ""
  echo -e "${_RED}${_BOLD}  ──── Provision failed ────${_RESET}"
  if [[ -n "${_SSH_FAILED_STEP}" ]]; then
    echo -e "  Step : ${_SSH_FAILED_STEP}"
  fi
  echo -e "  VM is reachable at ${_CYAN}${VM_SSH_USER:-ubuntu}@${VM_IP}${_RESET}"
  echo ""
  echo -e "${_BOLD}  Drop into the VM to debug? [Y/n]${_RESET} "
  read -r _answer
  case "${_answer,,}" in
    n|no)
      echo "  Exiting. To SSH in manually:"
      echo "    ssh -i ${VM_SSH_KEY:-~/.ssh/dev-env} ${VM_SSH_USER:-ubuntu}@${VM_IP}"
      ;;
    *)
      echo ""
      echo -e "${_CYAN}  Opening SSH session — type 'exit' to return.${_RESET}"
      echo ""
      ssh \
        -i "${VM_SSH_KEY}" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p "${VM_SSH_PORT:-22}" \
        "${VM_SSH_USER}@${VM_IP}"
      ;;
  esac
}

trap '_drop_to_ssh' ERR

# --------------------------------------------------------------------------- #
# Load configuration and library modules
# --------------------------------------------------------------------------- #
# shellcheck source=config.env
source "${REPO_ROOT}/config.env"
# shellcheck source=lib/log.sh
source "${REPO_ROOT}/lib/log.sh"
# shellcheck source=lib/detect.sh
source "${REPO_ROOT}/lib/detect.sh"
# shellcheck source=lib/dependencies.sh
source "${REPO_ROOT}/lib/dependencies.sh"
# shellcheck source=lib/providers/multipass.sh
source "${REPO_ROOT}/lib/providers/multipass.sh"
# shellcheck source=lib/providers/libvirt.sh
source "${REPO_ROOT}/lib/providers/libvirt.sh"
# shellcheck source=lib/providers/incus.sh
source "${REPO_ROOT}/lib/providers/incus.sh"
# shellcheck source=lib/vm.sh
source "${REPO_ROOT}/lib/vm.sh"
# shellcheck source=lib/ansible_runner.sh
source "${REPO_ROOT}/lib/ansible_runner.sh"
# shellcheck source=lib/verify.sh
source "${REPO_ROOT}/lib/verify.sh"
# shellcheck source=lib/recovery.sh
source "${REPO_ROOT}/lib/recovery.sh"

# --------------------------------------------------------------------------- #
# Defaults
# --------------------------------------------------------------------------- #
VM_NAME="dev-env"
VM_CPU=4
VM_RAM=8192
VM_DISK_GB=40
# VM_USER is the SSH user inside the Ubuntu cloud image — always "ubuntu".
# It is a VM-side constant and must NEVER be derived from the host environment
# (USER, whoami, HOME, etc.).  Host usernames must not leak into guest provisioning.
VM_USER="ubuntu"
SKIP_ANSIBLE=false
CLEAN_FIRST=false
DESTROY_FIRST=false
RESUME=false
FORCE_PROVIDER=""
DEBUG=false
DEV_MODE=false

ANSIBLE_DIR="${REPO_ROOT}/ansible"
LOG_FILE="${REPO_ROOT}/provision.log"

# Provider probe order — edit to restrict or reorder.
# Overridden by --provider flag or FORCE_PROVIDER env var.
PROVIDER_PRIORITY=("multipass" "libvirt" "incus")

ACTIVE_PROVIDER=""
SELECTED_PROVIDER=""
AVAILABLE_PROVIDERS=()

export VM_NAME VM_CPU VM_RAM VM_DISK_GB VM_USER SKIP_ANSIBLE DEV_MODE RESUME
export ANSIBLE_DIR LOG_FILE REPO_ROOT DEBUG
export PROVIDER_PRIORITY ACTIVE_PROVIDER SELECTED_PROVIDER AVAILABLE_PROVIDERS
export UBUNTU_CLOUD_IMAGE_URL UBUNTU_CLOUD_IMAGE_URL_ARM
export KV_BACKEND_REPO KV_BACKEND_TARBALL_URL
export DEV_ENV_REPO

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #
_usage() {
  awk '/^#!/{next} /^# ===/{found=1} found && /^set /{exit} found{sub(/^# ?/,""); print}' "$0"
}

_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)         VM_NAME="$2";         shift 2 ;;
      --cpu)          VM_CPU="$2";          shift 2 ;;
      --ram)          VM_RAM="$2";          shift 2 ;;
      --disk)         VM_DISK_GB="$2";      shift 2 ;;
      --provider)     FORCE_PROVIDER="$2";  shift 2 ;;
      --skip-ansible) SKIP_ANSIBLE=true;    shift ;;
      --clean)        CLEAN_FIRST=true;     shift ;;
      --destroy)      DESTROY_FIRST=true;   shift ;;
      --resume)       RESUME=true;          shift ;;
      --debug)        DEBUG=true;           shift ;;
      --dev-mode)     DEV_MODE=true;        shift ;;
      -h|--help)      _usage; exit 0 ;;
      *) error "Unknown option: $1"; _usage; exit 1 ;;
    esac
  done
  export VM_NAME VM_CPU VM_RAM VM_DISK_GB VM_USER SKIP_ANSIBLE DEBUG DEV_MODE RESUME
}

# --------------------------------------------------------------------------- #
# _clean_vm
# Wipes the named VM and every artifact it left behind so provision.sh can
# start from an absolutely blank slate.  Matches the manual steps:
#
#   virsh domblklist dev-env --details        (discover disks)
#   virsh destroy dev-env                     (force-stop)
#   virsh undefine dev-env --nvram            (remove definition + NVRAM)
#   rm -f <disk> <seed-iso>                   (delete images)
#   rm -f .provision-state                    (clear saved state)
#   rm -f provision.log                       (fresh log)
#
# Safe to run even when no VM exists.
# --------------------------------------------------------------------------- #
_clean_vm() {
  local pool_dir="/var/lib/libvirt/images"
  local disk="${pool_dir}/${VM_NAME}.qcow2"
  local seed="${pool_dir}/${VM_NAME}-seed.iso"
  local state_file="${REPO_ROOT}/.provision-state"

  echo ""
  echo -e "${_YELLOW}${_BOLD}  ──── Clean wipe: ${VM_NAME} ────${_RESET}"
  echo ""

  # ── 1. Discover disk paths from libvirt before undefining ──────────── #
  local extra_disks=()
  if virsh -c qemu:///system dominfo "${VM_NAME}" &>/dev/null; then
    while IFS= read -r path; do
      [[ -n "${path}" && "${path}" != "-" ]] && extra_disks+=("${path}")
    done < <(sudo virsh domblklist "${VM_NAME}" --details 2>/dev/null \
      | awk '/file/{print $4}')
    info "  Disks reported by libvirt: ${extra_disks[*]:-none}"

    # ── 2. Force-stop ───────────────────────────────────────────────── #
    info "  Stopping VM '${VM_NAME}'..."
    sudo virsh destroy "${VM_NAME}" 2>/dev/null && \
      success "  VM stopped." || info "  VM was already stopped."

    # ── 3. Undefine (try --nvram first for UEFI VMs, fall back without) #
    info "  Removing VM definition..."
    if sudo virsh undefine "${VM_NAME}" --nvram 2>/dev/null; then
      success "  VM undefined (--nvram)."
    elif sudo virsh undefine "${VM_NAME}" 2>/dev/null; then
      success "  VM undefined."
    else
      warn "  VM definition not found — already gone."
    fi
  else
    info "  VM '${VM_NAME}' not registered in libvirt — skipping virsh steps."
  fi

  # ── 4. Delete all disk images ──────────────────────────────────────── #
  local all_images=("${disk}" "${seed}")
  for d in "${extra_disks[@]:-}"; do
    [[ -n "${d}" ]] && all_images+=("${d}")
  done

  local deleted_any=false
  for img in "${all_images[@]}"; do
    # De-duplicate
    [[ -z "${img}" ]] && continue
    if sudo test -f "${img}" 2>/dev/null; then
      sudo rm -f "${img}"
      success "  Deleted: ${img}"
      deleted_any=true
    fi
  done
  [[ "${deleted_any}" == "false" ]] && info "  No image files to remove."

  # ── 5. Clear host-side state so --resume cannot re-use stale data ─── #
  if [[ -f "${state_file}" ]]; then
    rm -f "${state_file}"
    success "  Deleted: ${state_file}"
  fi

  # ── 6. Fresh log for the upcoming run ─────────────────────────────── #
  : > "${LOG_FILE}"
  success "  Log cleared: ${LOG_FILE}"

  echo ""
  success "Clean wipe complete.  Starting fresh provision run..."
  echo ""
}

# --------------------------------------------------------------------------- #
# Final success banner
# --------------------------------------------------------------------------- #
_print_success() {
  echo ""
  echo -e "${_GREEN}${_BOLD}"
  echo "  ╔══════════════════════════════════════════════════════╗"
  echo "  ║                                                      ║"
  echo "  ║   ✔  Developer workstation ready.                    ║"
  echo "  ║                                                      ║"
  printf "  ║   Provider  : %-38s║\n" "${ACTIVE_PROVIDER}"
  printf "  ║   VM Name   : %-38s║\n" "${VM_NAME}"
  printf "  ║   VM IP     : %-38s║\n" "${VM_IP}"
  printf "  ║   CPU / RAM : %-38s║\n" "${VM_CPU} vCPU / ${VM_RAM} MB"
  echo "  ║                                                      ║"
  echo "  ║   SSH into VM:                                       ║"
  printf "  ║     ssh -i ~/.ssh/dev-env ubuntu@%-20s║\n" "${VM_IP}"
  echo "  ║                                                      ║"
  echo "  ║   Destroy VM  :  ./provision.sh --destroy            ║"
  echo "  ║   Re-provision:  ./provision.sh                      ║"
  echo "  ║   Re-run stack:  ssh -i ~/.ssh/dev-env               ║"
  echo "  ║     ubuntu@<VM_IP> 'cd ~/workspace/repos/kv-backend/ ║"
  echo "  ║     preload-docker-compose && ./sshprovision.sh'     ║"
  echo "  ║                                                      ║"
  echo "  ╚══════════════════════════════════════════════════════╝"
  echo -e "${_RESET}"
}

# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
main() {
  _parse_args "$@"

  banner "Developer Environment Provisioner"
  info "Log file: ${LOG_FILE}"
  : > "${LOG_FILE}"

  if [[ "${RESUME:-false}" == "true" ]]; then
    # ── Resume path ──────────────────────────────────────────────────── #
    # The VM is already running from a previous ./provision.sh invocation.
    # Load saved connection details and skip directly to SSH + Ansible.
    info "--resume: loading saved VM state and skipping boot phase."
    load_provision_state || exit 1
  else
    # ── Full provision path ───────────────────────────────────────────── #
    step 1 7 "Detecting host OS"
    detect_host_os

    # --clean: wipe everything before detection so the next steps start
    # from an absolutely blank slate.  Runs early (right after OS detection)
    # so VM_NAME is known but no provider state has been touched yet.
    if [[ "${CLEAN_FIRST}" == "true" ]]; then
      _clean_vm
    fi

    # On Fedora/RHEL, libvirt is the native path and requires the fewest
    # additional dependencies (dnf install @virtualization vs. snap + multipass).
    # Reorder the priority unless the caller forced a provider explicitly.
    if [[ -z "${FORCE_PROVIDER}" ]]; then
      case "$HOST_OS" in
        fedora|rhel) PROVIDER_PRIORITY=("libvirt" "multipass" "incus") ;;
      esac
    fi

    step 2 7 "Detecting virtualization providers"
    detect_providers

    # --provider flag overrides auto-detection
    if [[ -n "${FORCE_PROVIDER}" ]]; then
      SELECTED_PROVIDER="${FORCE_PROVIDER}"
      AVAILABLE_PROVIDERS=("${FORCE_PROVIDER}")
      info "Provider forced via --provider flag: ${SELECTED_PROVIDER}"
    else
      select_provider
    fi

    step 3 7 "Installing provider tools"
    ensure_provider

    if [[ "${DESTROY_FIRST}" == "true" ]]; then
      destroy_vm
    fi

    step 4 7 "Creating VM"
    boot_vm

    # Persist VM connection details so --resume can skip the boot phase
    # if provisioning is interrupted after this point.
    save_provision_state
  fi

  step 5 7 "Waiting for SSH"
  if ! wait_for_ssh; then
    # SSH key auth timed out — attempt automatic recovery before giving up.
    # ssh_recovery() will either restore SSH and return 0, or die() with
    # instructions for the user to follow and retry via --resume.
    ssh_recovery
  fi

  # From this point onward the VM is reachable over SSH.
  # The ERR trap will offer an interactive SSH session on failure.
  _SSH_READY=true

  # Wait for cloud-init to finish its first-boot work before handing off to
  # Ansible.  Without this gate, package installation and user setup may still
  # be in progress, causing Ansible tasks to fail on the first run even though
  # a second run immediately afterwards always succeeds.
  wait_for_cloud_init

  echo ""
  echo -e "${_BOLD}  Boot timeline:${_RESET}"
  echo -e "  [${_GREEN}✓${_RESET}] VM created  — ${ACTIVE_PROVIDER}  |  VM_USER: ${VM_USER}"
  echo -e "  [${_GREEN}✓${_RESET}] Guest running  |  IP: ${VM_IP}"
  echo -e "  [${_GREEN}✓${_RESET}] SSH available  |  ${VM_SSH_USER}@${VM_IP}:${VM_SSH_PORT:-22}"
  echo -e "  [${_GREEN}✓${_RESET}] Cloud-init first boot complete"
  echo -e "  [ ] Provisioning with Ansible (starting now)"
  echo ""

  _SSH_FAILED_STEP="GitHub SSH key setup"
  step 6 7 "GitHub SSH key setup"
  setup_ssh_key

  # Clone kv-backend and download the Docker image tarball immediately after
  # the GitHub connection is confirmed — before Ansible runs, so the
  # kv_backend Ansible role finds the repo already in place and the tarball
  # is ready for 'docker load'.
  _SSH_FAILED_STEP="clone kv-backend"
  clone_kv_backend
  _SSH_FAILED_STEP="download kv-backend assets"
  download_kv_assets

  # Install all tools first via Ansible before applying config or starting services.
  _SSH_FAILED_STEP="Provisioning VM (Ansible)"
  step 7 7 "Provisioning VM"
  run_ansible

  # Prompt for Nexus credentials if not already set in config.env.
  prompt_nexus_credentials

  # Apply kv-backend config after Ansible has installed all dependencies (Maven, Java, etc.)
  _SSH_FAILED_STEP="apply kv-backend local config"
  apply_kv_config

  _SSH_FAILED_STEP="start kv-backend services"
  start_kv_services

  _SSH_FAILED_STEP="verification"
  run_verify

  # All steps succeeded — clear the trap so it doesn't fire on exit.
  trap - ERR
  _SSH_FAILED_STEP=""

  _print_success
}

main "$@"