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
#   --user   NAME   Developer username   (default: current $USER)
#   --skip-ansible  Boot VM only, skip Ansible provisioning
#   --destroy       Destroy existing VM first, then reprovision
#   -h, --help      Show this help
#
# PREREQUISITES:
#   - git (you already have it — you cloned this repo)
#   - curl or wget
#   - Internet access
#   Everything else is installed automatically.
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
# shellcheck source=lib/providers/virtualbox.sh
source "${REPO_ROOT}/lib/providers/virtualbox.sh"
# shellcheck source=lib/providers/libvirt.sh
source "${REPO_ROOT}/lib/providers/libvirt.sh"
# shellcheck source=lib/providers/vmware.sh
source "${REPO_ROOT}/lib/providers/vmware.sh"
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
DEV_USER="${USER}"
SKIP_ANSIBLE=false
DESTROY_FIRST=false

VM_DIR="${REPO_ROOT}/vm"
ANSIBLE_DIR="${REPO_ROOT}/ansible"
LOG_FILE="${REPO_ROOT}/provision.log"

# Provider probe order — edit this to restrict or reorder providers.
PROVIDER_PRIORITY=("virtualbox" "libvirt" "vmware_desktop")

ACTIVE_PROVIDER=""
SELECTED_PROVIDER=""
AVAILABLE_PROVIDERS=()

export VM_DIR ANSIBLE_DIR LOG_FILE DEV_USER VM_NAME VM_CPU VM_RAM

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #
_usage() {
  # Print only the header comment block (lines between the shebang and the first blank line after the header)
  sed -n '/^# ===/,/^# ===/p' "$0" | head -1 >/dev/null
  awk '/^#!/{next} /^# ===/{found=1} found && /^set /{exit} found{sub(/^# ?/,""); print}' "$0"
}

_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)         VM_NAME="$2";       shift 2 ;;
      --cpu)          VM_CPU="$2";        shift 2 ;;
      --ram)          VM_RAM="$2";        shift 2 ;;
      --user)         DEV_USER="$2";      shift 2 ;;
      --skip-ansible) SKIP_ANSIBLE=true;  shift ;;
      --destroy)      DESTROY_FIRST=true; shift ;;
      -h|--help)      _usage; exit 0 ;;
      *) error "Unknown option: $1"; _usage; exit 1 ;;
    esac
  done
  export VM_NAME VM_CPU VM_RAM DEV_USER SKIP_ANSIBLE
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
  printf "  ║   CPU / RAM : %-38s║\n" "${VM_CPU} vCPU / ${VM_RAM} MB"
  echo "  ║                                                      ║"
  echo "  ║   SSH into VM  :  cd vm && vagrant ssh               ║"
  echo "  ║   Suspend VM   :  cd vm && vagrant suspend           ║"
  echo "  ║   Destroy VM   :  ./provision.sh --destroy           ║"
  echo "  ║   Re-provision :  ./provision.sh                     ║"
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

  step 2 7 "Installing host dependencies (Vagrant)"
  ensure_vagrant

  step 3 7 "Detecting virtualization providers"
  detect_providers
  select_provider

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
