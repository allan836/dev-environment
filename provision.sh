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
#   --disk   N      Disk in GB           (default: 60)
#   --user   NAME   Developer username   (default: current $USER)
#   --skip-ansible  Boot VM only, skip Ansible provisioning
#   --destroy       Destroy existing VM first, then reprovision
#   -h, --help      Show this help
#
# WHAT THIS SCRIPT DOES — IN ORDER:
#   1. Detects the host OS (Linux/macOS).
#   2. Installs Vagrant on the host (via apt/dnf/brew or direct download).
#      WHY Vagrant: Vagrant is a single, stable CLI that abstracts every
#      hypervisor (VirtualBox, KVM/libvirt, VMware) behind one interface.
#      provision.sh installs Vagrant itself so developers never need to
#      manually install or learn the hypervisor CLI. Vagrant becomes the
#      single command language; the hypervisor is just a backend detail.
#   3. Tries hypervisor backends IN ORDER until one works:
#        a. VirtualBox  — free, cross-platform, most common.
#        b. KVM/libvirt — Linux-native, faster on Linux hosts.
#        c. VMware      — enterprise standard; requires a licensed binary.
#      Each attempt: installs the backend → installs the Vagrant provider
#      plugin → runs `vagrant up`. On failure the VM is destroyed and the
#      next backend is tried. The first successful boot wins.
#   4. Waits for SSH to be available inside the VM.
#   5. Runs the Ansible playbook to install all developer tools inside the VM.
#   6. Clones kv-backend (prompts for SSH key setup if needed).
#   7. Starts Docker services, runs kv-init.
#   8. Verifies all services.
#   9. Prints "Developer workstation ready."
#
# PREREQUISITES ON THE HOST MACHINE (the laptop running this script):
#   - git  (already present: you cloned this repo with it)
#   - curl or wget
#   - Internet access
#   Everything else — Vagrant, the hypervisor, Ubuntu, tools — is automatic.
# =============================================================================
set -euo pipefail

# --------------------------------------------------------------------------- #
# Defaults (override via flags)
# --------------------------------------------------------------------------- #
VM_NAME="dev-env"
VM_CPU=4
VM_RAM=8192
VM_DISK=60
DEV_USER="${USER}"
SKIP_ANSIBLE=false
DESTROY_FIRST=false

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_DIR="$REPO_ROOT/vm"
ANSIBLE_DIR="$REPO_ROOT/ansible"
LOG_FILE="$REPO_ROOT/provision.log"

# Backends to try, in order.  Comment out any you never want attempted.
BACKENDS=("virtualbox" "libvirt" "vmware_desktop")

# --------------------------------------------------------------------------- #
# Colour helpers
# --------------------------------------------------------------------------- #
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}==>${RESET} $*"; }
success() { echo -e "${GREEN}✔${RESET}  $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET}   $*"; }
error()   { echo -e "${RED}✘${RESET}  $*" >&2; }
banner()  { echo -e "\n${BOLD}${CYAN}$*${RESET}\n"; }
has()     { command -v "$1" >/dev/null 2>&1; }

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)         VM_NAME="$2";      shift 2 ;;
      --cpu)          VM_CPU="$2";       shift 2 ;;
      --ram)          VM_RAM="$2";       shift 2 ;;
      --disk)         VM_DISK="$2";      shift 2 ;;
      --user)         DEV_USER="$2";     shift 2 ;;
      --skip-ansible) SKIP_ANSIBLE=true; shift ;;
      --destroy)      DESTROY_FIRST=true; shift ;;
      -h|--help)      usage; exit 0 ;;
      *) error "Unknown option: $1"; usage; exit 1 ;;
    esac
  done
}

usage() {
  grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,1\}//'
}

# --------------------------------------------------------------------------- #
# Host OS detection
# --------------------------------------------------------------------------- #
detect_host_os() {
  if [[ "${OSTYPE:-}" == darwin* ]]; then
    HOST_OS="mac"
  elif [[ -f /etc/fedora-release ]]; then
    HOST_OS="fedora"
  elif [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}:${ID_LIKE:-}" in
      ubuntu:*|*:*ubuntu*) HOST_OS="ubuntu" ;;
      debian:*|*:*debian*) HOST_OS="debian" ;;
      *) HOST_OS="linux_generic" ;;
    esac
  else
    HOST_OS="unknown"
  fi
  info "Host OS detected: $HOST_OS"
}

# --------------------------------------------------------------------------- #
# Install Vagrant on the host
#
# WHY provision.sh installs Vagrant itself:
#   Vagrant is just a package — no different from installing git or curl.
#   A developer who has just git-cloned this repo has internet access and a
#   terminal. That is enough to fetch and install Vagrant via the system
#   package manager (apt/dnf/brew) or directly from HashiCorp's releases.
#   Once Vagrant is on the PATH, provision.sh uses it as a unified interface
#   to whichever hypervisor is available. The developer never needs to know
#   whether VirtualBox, KVM, or VMware is running underneath — Vagrant
#   abstracts that away. Installing Vagrant inside provision.sh means the
#   developer does not need to read any documentation before running the
#   script; the script acquires its own dependencies.
# --------------------------------------------------------------------------- #
install_vagrant() {
  if has vagrant; then
    success "Vagrant already installed: $(vagrant --version)"
    return 0
  fi

  info "Installing Vagrant on host ($HOST_OS)..."

  case "$HOST_OS" in
    mac)
      if ! has brew; then
        error "Homebrew is required on macOS. Install it from https://brew.sh then re-run."
        exit 1
      fi
      brew install --cask vagrant
      ;;
    ubuntu|debian)
      sudo apt-get update -qq
      sudo apt-get install -y vagrant
      # Fallback: if apt version is very old, download from HashiCorp directly
      if ! vagrant --version &>/dev/null; then
        _install_vagrant_from_hashicorp
      fi
      ;;
    fedora)
      sudo dnf install -y vagrant
      ;;
    linux_generic)
      _install_vagrant_from_hashicorp
      ;;
    *)
      warn "Cannot auto-install Vagrant on $HOST_OS."
      warn "Download from https://www.vagrantup.com/downloads and re-run."
      exit 1
      ;;
  esac

  if has vagrant; then
    success "Vagrant installed: $(vagrant --version)"
  else
    error "Vagrant installation failed. Check $LOG_FILE for details."
    exit 1
  fi
}

_install_vagrant_from_hashicorp() {
  local arch; arch="$(uname -m)"
  local pkg_arch="amd64"
  [[ "$arch" == "aarch64" || "$arch" == "arm64" ]] && pkg_arch="arm64"
  local vagrant_version="2.4.1"
  local deb_url="https://releases.hashicorp.com/vagrant/${vagrant_version}/vagrant_${vagrant_version}-1_${pkg_arch}.deb"
  local tmp_deb="/tmp/vagrant_${vagrant_version}.deb"
  info "Downloading Vagrant ${vagrant_version} from HashiCorp..."
  curl -fsSL "$deb_url" -o "$tmp_deb"
  sudo dpkg -i "$tmp_deb"
  rm -f "$tmp_deb"
}

# --------------------------------------------------------------------------- #
# Backend: VirtualBox
# --------------------------------------------------------------------------- #
install_virtualbox() {
  if has vboxmanage; then
    success "VirtualBox already installed: $(vboxmanage --version)"
    return 0
  fi
  info "Installing VirtualBox..."
  case "$HOST_OS" in
    mac)      brew install --cask virtualbox ;;
    ubuntu|debian)
      sudo apt-get update -qq
      sudo apt-get install -y virtualbox virtualbox-ext-pack || \
        sudo apt-get install -y virtualbox
      ;;
    fedora)
      sudo dnf install -y VirtualBox
      ;;
    *)
      warn "Cannot auto-install VirtualBox on $HOST_OS."
      return 1
      ;;
  esac
  has vboxmanage || { warn "VirtualBox install failed."; return 1; }
  success "VirtualBox installed: $(vboxmanage --version)"
}

try_virtualbox() {
  info "Trying backend: VirtualBox"
  install_virtualbox || return 1
  cd "$VM_DIR"
  if vagrant up --provider=virtualbox 2>&1 | tee -a "$LOG_FILE"; then
    ACTIVE_BACKEND="virtualbox"
    return 0
  fi
  warn "VirtualBox boot failed. Destroying and trying next backend..."
  vagrant destroy -f 2>/dev/null || true
  return 1
}

# --------------------------------------------------------------------------- #
# Backend: KVM / libvirt (Linux only)
# --------------------------------------------------------------------------- #
install_kvm() {
  if has virsh; then
    success "KVM/libvirt already installed"
    return 0
  fi
  if [[ "$HOST_OS" == "mac" ]]; then
    warn "KVM is Linux-only. Skipping on macOS."
    return 1
  fi
  info "Installing KVM/libvirt..."
  case "$HOST_OS" in
    ubuntu|debian)
      sudo apt-get update -qq
      sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients \
        bridge-utils virt-manager cpu-checker
      sudo adduser "$USER" libvirt
      sudo adduser "$USER" kvm
      sudo systemctl enable --now libvirtd
      ;;
    fedora)
      sudo dnf install -y @virtualization
      sudo systemctl enable --now libvirtd
      sudo usermod -aG libvirt "$USER"
      sudo usermod -aG kvm "$USER"
      ;;
    *)
      warn "Cannot auto-install KVM on $HOST_OS."
      return 1
      ;;
  esac
  has virsh || { warn "KVM install failed."; return 1; }
  success "KVM/libvirt installed"
}

install_vagrant_libvirt_plugin() {
  if vagrant plugin list 2>/dev/null | grep -q vagrant-libvirt; then
    success "vagrant-libvirt plugin already installed"
    return 0
  fi
  info "Installing vagrant-libvirt plugin..."
  # libvirt plugin needs build dependencies on the host
  case "$HOST_OS" in
    ubuntu|debian)
      sudo apt-get install -y libvirt-dev ruby-dev build-essential
      ;;
    fedora)
      sudo dnf install -y libvirt-devel ruby-devel gcc make
      ;;
  esac
  vagrant plugin install vagrant-libvirt
}

try_kvm() {
  info "Trying backend: KVM/libvirt"
  [[ "$HOST_OS" == "mac" ]] && { warn "KVM unavailable on macOS."; return 1; }
  install_kvm || return 1
  install_vagrant_libvirt_plugin || return 1
  cd "$VM_DIR"
  if vagrant up --provider=libvirt 2>&1 | tee -a "$LOG_FILE"; then
    ACTIVE_BACKEND="libvirt"
    return 0
  fi
  warn "KVM/libvirt boot failed. Destroying and trying next backend..."
  vagrant destroy -f 2>/dev/null || true
  return 1
}

# --------------------------------------------------------------------------- #
# Backend: VMware (Workstation on Linux, Fusion on macOS)
# --------------------------------------------------------------------------- #
install_vmware() {
  if has vmware || has vmrun; then
    success "VMware already installed"
    return 0
  fi
  warn "VMware Workstation/Fusion requires a paid licence and cannot be"
  warn "downloaded automatically. Please:"
  warn "  Linux: install VMware Workstation from https://www.vmware.com/products/desktop-hypervisor.html"
  warn "  macOS: install VMware Fusion from https://www.vmware.com/products/fusion.html"
  warn "After installing, re-run ./provision.sh"
  # Non-fatal: user may have it but not on PATH yet
  read -rp "VMware is installed and licensed — press Enter to continue, or Ctrl-C to abort: "
  has vmware || has vmrun || return 1
}

install_vagrant_vmware_plugin() {
  if vagrant plugin list 2>/dev/null | grep -q vagrant-vmware-desktop; then
    success "vagrant-vmware-desktop plugin already installed"
    return 0
  fi
  info "Installing vagrant-vmware-desktop plugin..."
  vagrant plugin install vagrant-vmware-desktop
  # Install the Vagrant VMware Utility (required by the plugin)
  local util_url="https://releases.hashicorp.com/vagrant-vmware-utility/1.0.22"
  local arch; arch="$(uname -m)"
  local pkg_arch="amd64"
  [[ "$arch" == "aarch64" || "$arch" == "arm64" ]] && pkg_arch="arm64"
  case "$HOST_OS" in
    ubuntu|debian)
      local deb="vagrant-vmware-utility_1.0.22-1_${pkg_arch}.deb"
      curl -fsSL "${util_url}/${deb}" -o "/tmp/${deb}"
      sudo dpkg -i "/tmp/${deb}"
      ;;
    fedora)
      local rpm="vagrant-vmware-utility_1.0.22_${pkg_arch}.rpm"
      curl -fsSL "${util_url}/${rpm}" -o "/tmp/${rpm}"
      sudo rpm -i "/tmp/${rpm}"
      ;;
    mac)
      local dmg="vagrant-vmware-utility_1.0.22_darwin_${pkg_arch}.dmg"
      curl -fsSL "${util_url}/${dmg}" -o "/tmp/${dmg}"
      warn "Please mount /tmp/${dmg} and run the installer manually, then press Enter."
      read -rp ""
      ;;
  esac
  sudo systemctl enable --now vagrant-vmware-utility 2>/dev/null || true
}

try_vmware() {
  info "Trying backend: VMware"
  install_vmware || return 1
  install_vagrant_vmware_plugin || return 1
  cd "$VM_DIR"
  if vagrant up --provider=vmware_desktop 2>&1 | tee -a "$LOG_FILE"; then
    ACTIVE_BACKEND="vmware_desktop"
    return 0
  fi
  warn "VMware boot failed. Destroying..."
  vagrant destroy -f 2>/dev/null || true
  return 1
}

# --------------------------------------------------------------------------- #
# Backend dispatcher — tries each backend in BACKENDS order until one works
# --------------------------------------------------------------------------- #
ACTIVE_BACKEND=""

provision_vm() {
  if [[ "$DESTROY_FIRST" == "true" ]]; then
    info "Destroying existing VM (--destroy flag set)..."
    cd "$VM_DIR" && vagrant destroy -f 2>/dev/null || true
  fi

  # Write the VM name into the Vagrantfile environment
  export VAGRANT_VM_NAME="$VM_NAME"
  export VAGRANT_VM_CPU="$VM_CPU"
  export VAGRANT_VM_RAM="$VM_RAM"

  for backend in "${BACKENDS[@]}"; do
    echo ""
    banner "[ Backend attempt: $backend ]"
    case "$backend" in
      virtualbox)   try_virtualbox  && break ;;
      libvirt)      try_kvm         && break ;;
      vmware_desktop) try_vmware    && break ;;
      *)            warn "Unknown backend '$backend', skipping." ;;
    esac
  done

  if [[ -z "$ACTIVE_BACKEND" ]]; then
    error "All hypervisor backends failed. Check $LOG_FILE for details."
    error "Tried: ${BACKENDS[*]}"
    error "Ensure at least one of VirtualBox, KVM, or VMware is available."
    exit 1
  fi

  success "VM booted via backend: $ACTIVE_BACKEND"
}

# --------------------------------------------------------------------------- #
# SSH readiness — wait until the VM accepts SSH connections
# --------------------------------------------------------------------------- #
wait_for_ssh() {
  info "Waiting for VM SSH to become available..."
  cd "$VM_DIR"
  local max_attempts=60
  local attempt=0
  while ! vagrant ssh -c "echo ssh-ready" &>/dev/null; do
    attempt=$(( attempt + 1 ))
    if [[ $attempt -ge $max_attempts ]]; then
      error "VM SSH did not become available after ${max_attempts} attempts."
      exit 1
    fi
    printf "."
    sleep 5
  done
  echo ""
  success "SSH is ready."
}

# --------------------------------------------------------------------------- #
# SSH key setup — generate + display public key; wait for GitHub auth
# --------------------------------------------------------------------------- #
setup_ssh_key() {
  banner "SSH Key Setup"
  info "Generating SSH key inside VM (if not already present)..."
  cd "$VM_DIR"
  vagrant ssh -c "
    if [[ ! -f ~/.ssh/id_ed25519 ]]; then
      ssh-keygen -t ed25519 -C '${DEV_USER}@dev-env' -N '' -f ~/.ssh/id_ed25519
    fi
    echo ''
    echo '======================================================'
    echo '  Add the following public key to your GitHub account  '
    echo '  Settings → SSH and GPG keys → New SSH key            '
    echo '======================================================'
    cat ~/.ssh/id_ed25519.pub
    echo '======================================================'
  "
  echo ""
  warn "ACTION REQUIRED: Copy the public key above into GitHub before continuing."
  warn "This is the only manual step that cannot be automated — GitHub requires"
  warn "you to authenticate as yourself. Once you have added the key:"
  read -rp "  Press Enter to continue... "
}

# --------------------------------------------------------------------------- #
# Ansible provisioning — runs the playbook inside the VM over vagrant SSH
# --------------------------------------------------------------------------- #
run_ansible() {
  if [[ "$SKIP_ANSIBLE" == "true" ]]; then
    warn "--skip-ansible set. Skipping Ansible provisioning."
    return 0
  fi

  banner "Ansible Provisioning"
  info "Installing Ansible inside the VM..."
  cd "$VM_DIR"
  vagrant ssh -c "
    sudo apt-get update -qq
    sudo apt-get install -y ansible 2>&1
  "

  info "Copying Ansible playbook into VM..."
  vagrant ssh -c "mkdir -p ~/dev-environment/ansible"
  vagrant upload "$ANSIBLE_DIR" /home/vagrant/dev-environment/ansible

  info "Running Ansible playbook (this installs all developer tools)..."
  vagrant ssh -c "
    cd ~/dev-environment/ansible
    ansible-playbook playbook.yml \
      -i inventory/hosts.yml \
      --extra-vars 'dev_user=${DEV_USER}' \
      -v 2>&1
  " | tee -a "$LOG_FILE"

  success "Ansible provisioning complete."
}

# --------------------------------------------------------------------------- #
# kv-backend clone
# --------------------------------------------------------------------------- #
clone_kv_backend() {
  banner "Cloning kv-backend"
  cd "$VM_DIR"
  vagrant ssh -c "
    KV_DIR=\$HOME/workspace/repos/kv-backend
    if [[ -d \"\$KV_DIR\" ]]; then
      echo 'kv-backend already cloned at '\$KV_DIR
    else
      mkdir -p \$HOME/workspace/repos
      git clone git@github.com:knowledgevault/kv-backend.git \"\$KV_DIR\" && \
        echo 'kv-backend cloned successfully.' || \
        echo 'WARNING: kv-backend clone failed (check SSH key is added to GitHub).'
    fi
  "
}

# --------------------------------------------------------------------------- #
# Start kv-backend Docker services
# --------------------------------------------------------------------------- #
start_kv_services() {
  banner "Starting kv-backend Services"
  cd "$VM_DIR"
  vagrant ssh -c "
    KV_BOOTSTRAP=\$HOME/workspace/repos/dev-environment/workstation-bootstrap
    if [[ -d \"\$KV_BOOTSTRAP\" ]]; then
      cd \"\$KV_BOOTSTRAP\"
      make kv-up  2>&1 || echo 'WARNING: kv-up failed. Run make kv-up manually after checking kv-backend clone.'
    else
      echo 'workstation-bootstrap not found inside VM — skipping kv-up.'
    fi
  "
}

# --------------------------------------------------------------------------- #
# Verification
# --------------------------------------------------------------------------- #
verify() {
  banner "Verification"
  cd "$VM_DIR"
  vagrant ssh -c "
    check() {
      local name=\$1 cmd=\$2
      if command -v \"\$cmd\" >/dev/null 2>&1; then
        printf '  [\033[0;32mok\033[0m] %-14s %s\n' \"\$name\" \"\$(\$cmd --version 2>&1 | head -n1)\"
      else
        printf '  [\033[0;31mMISSING\033[0m] %-14s\n' \"\$name\"
      fi
    }
    echo ''
    echo '=== Core tools ==='
    check git       git
    check docker    docker
    check ansible   ansible
    check terraform terraform
    check kubectl   kubectl
    echo ''
    echo '=== Runtimes ==='
    check node   node
    check python3 python3
    check java   java
    check mvn    mvn
    check pnpm   pnpm
    echo ''
    echo '=== Docker services ==='
    docker ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null || echo '  (run: make kv-up)'
  "
}

# --------------------------------------------------------------------------- #
# Final success banner
# --------------------------------------------------------------------------- #
print_success() {
  echo ""
  echo -e "${GREEN}${BOLD}"
  echo "  ╔══════════════════════════════════════════════════╗"
  echo "  ║                                                  ║"
  echo "  ║      ✔  Developer workstation ready.             ║"
  echo "  ║                                                  ║"
  echo "  ║  Hypervisor : $ACTIVE_BACKEND"
  echo "  ║  VM Name    : $VM_NAME"
  echo "  ║  CPU / RAM  : ${VM_CPU} vCPU / ${VM_RAM} MB"
  echo "  ║                                                  ║"
  echo "  ║  SSH into VM  :  cd vm && vagrant ssh            ║"
  echo "  ║  Suspend VM   :  cd vm && vagrant suspend        ║"
  echo "  ║  Destroy VM   :  ./provision.sh --destroy        ║"
  echo "  ║                                                  ║"
  echo "  ╚══════════════════════════════════════════════════╝"
  echo -e "${RESET}"
}

# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
main() {
  parse_args "$@"

  banner "Developer Environment Provisioner"
  info "Log file: $LOG_FILE"
  : > "$LOG_FILE"

  detect_host_os
  install_vagrant
  provision_vm
  wait_for_ssh
  setup_ssh_key
  run_ansible
  clone_kv_backend
  start_kv_services
  verify
  print_success
}

main "$@"
