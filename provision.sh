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
#   --user   NAME   Developer username   (default: current $USER)
#   --provider NAME Force provider       (multipass | libvirt | incus)
#   --skip-ansible  Boot VM only, skip Ansible provisioning
#   --destroy       Destroy existing VM first, then reprovision
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

# --------------------------------------------------------------------------- #
# Defaults
# --------------------------------------------------------------------------- #
VM_NAME="dev-env"
VM_CPU=4
VM_RAM=8192
VM_DISK_GB=40
DEV_USER="${USER}"
SKIP_ANSIBLE=false
DESTROY_FIRST=false
FORCE_PROVIDER=""

ANSIBLE_DIR="${REPO_ROOT}/ansible"
LOG_FILE="${REPO_ROOT}/provision.log"

# Provider probe order — edit to restrict or reorder.
# Overridden by --provider flag or FORCE_PROVIDER env var.
PROVIDER_PRIORITY=("multipass" "libvirt" "incus")

ACTIVE_PROVIDER=""
SELECTED_PROVIDER=""
AVAILABLE_PROVIDERS=()

export VM_NAME VM_CPU VM_RAM VM_DISK_GB DEV_USER SKIP_ANSIBLE
export ANSIBLE_DIR LOG_FILE REPO_ROOT
export PROVIDER_PRIORITY ACTIVE_PROVIDER SELECTED_PROVIDER AVAILABLE_PROVIDERS
export UBUNTU_CLOUD_IMAGE_URL UBUNTU_CLOUD_IMAGE_URL_ARM

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
      --user)         DEV_USER="$2";        shift 2 ;;
      --provider)     FORCE_PROVIDER="$2";  shift 2 ;;
      --skip-ansible) SKIP_ANSIBLE=true;    shift ;;
      --destroy)      DESTROY_FIRST=true;   shift ;;
      -h|--help)      _usage; exit 0 ;;
      *) error "Unknown option: $1"; _usage; exit 1 ;;
    esac
  done
  export VM_NAME VM_CPU VM_RAM VM_DISK_GB DEV_USER SKIP_ANSIBLE
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

  step 1 7 "Detecting host OS"
  detect_host_os

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

  step 5 7 "Waiting for SSH"
  wait_for_ssh

  step 6 7 "SSH key setup"
  setup_ssh_key

  step 7 7 "Provisioning VM"
  run_ansible
  clone_kv_backend
  start_kv_services

  run_verify

  _print_success
}

main "$@"
