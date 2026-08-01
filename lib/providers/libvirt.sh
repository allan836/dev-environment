#!/usr/bin/env bash
# =============================================================================
# lib/providers/libvirt.sh — KVM/libvirt + cloud-init provider
#
# Boots an Ubuntu 24.04 VM directly via libvirt (virt-install) without Vagrant.
# Uses a cloud image + cloud-init ISO for first-boot configuration.
#
# After a successful boot, exports:
#   ACTIVE_PROVIDER  = "libvirt"
#   VM_IP            = <IP address of the VM>
#   VM_SSH_USER      = "ubuntu"
#   VM_SSH_PORT      = 22
#
# VM_SSH_KEY is set by ensure_host_ssh_key() in lib/vm.sh before boot.
#
# Requires: lib/log.sh, lib/dependencies.sh (ensure_libvirt) sourced.
#           VM_NAME, VM_CPU, VM_RAM, VM_DISK_GB, UBUNTU_CLOUD_IMAGE_URL,
#           HOST_ARCH, VM_SSH_KEY exported.
# =============================================================================

# VM storage directory — all libvirt disk images live here
_LIBVIRT_VM_DIR="${HOME}/.local/share/dev-env-libvirt"

# --------------------------------------------------------------------------- #
# _libvirt_vm_exists
# --------------------------------------------------------------------------- #
_libvirt_vm_exists() {
  virsh dominfo "${VM_NAME}" &>/dev/null
}

# --------------------------------------------------------------------------- #
# _libvirt_base_image_path
# Returns the path where the Ubuntu cloud base image is cached.
# --------------------------------------------------------------------------- #
_libvirt_base_image_path() {
  local img_url
  [[ "$HOST_ARCH" == "arm64" ]] \
    && img_url="${UBUNTU_CLOUD_IMAGE_URL_ARM}" \
    || img_url="${UBUNTU_CLOUD_IMAGE_URL}"
  echo "${_LIBVIRT_VM_DIR}/noble-server-cloudimg-${HOST_ARCH}.img"
}

# --------------------------------------------------------------------------- #
# _libvirt_download_base_image
# Downloads the Ubuntu 24.04 cloud image if not already cached.
# Tries the primary URL then mirrors.
# --------------------------------------------------------------------------- #
_libvirt_download_base_image() {
  local dest; dest="$(_libvirt_base_image_path)"
  if [[ -f "$dest" ]]; then
    info "Ubuntu 24.04 cloud image already cached at ${dest}."
    return 0
  fi

  mkdir -p "$(dirname "$dest")"

  local primary_url mirror_url
  if [[ "$HOST_ARCH" == "arm64" ]]; then
    primary_url="${UBUNTU_CLOUD_IMAGE_URL_ARM}"
    mirror_url="https://mirrors.edge.kernel.org/ubuntu-cloud-images/noble/current/noble-server-cloudimg-arm64.img"
  else
    primary_url="${UBUNTU_CLOUD_IMAGE_URL}"
    mirror_url="https://mirrors.edge.kernel.org/ubuntu-cloud-images/noble/current/noble-server-cloudimg-amd64.img"
  fi

  local candidates=("$primary_url" "$mirror_url")
  for url in "${candidates[@]}"; do
    info "  Trying cloud image → ${url}"
    if curl -fL --max-time 600 --progress-bar "$url" -o "$dest" 2>>"$LOG_FILE"; then
      success "Cloud image downloaded."
      return 0
    fi
    warn "  ✘ Download failed from ${url}. Trying next mirror..."
    rm -f "$dest"
  done

  die "All Ubuntu cloud image download candidates failed. Check ${LOG_FILE}."
}

# --------------------------------------------------------------------------- #
# _libvirt_create_disk
# Creates a qcow2 overlay disk from the base image for this VM.
# --------------------------------------------------------------------------- #
_libvirt_create_disk() {
  local base; base="$(_libvirt_base_image_path)"
  local disk="${_LIBVIRT_VM_DIR}/${VM_NAME}.qcow2"

  if [[ -f "$disk" ]]; then
    info "Disk image already exists at ${disk}."
  else
    info "Creating VM disk (${VM_DISK_GB}G overlay of base image)..."
    qemu-img create -b "$base" -f qcow2 -F qcow2 "$disk" "${VM_DISK_GB}G" \
      2>&1 | tee -a "$LOG_FILE"
  fi

  echo "$disk"
}

# --------------------------------------------------------------------------- #
# _libvirt_create_seed_iso
# Creates the cloud-init nocloud ISO (user-data + meta-data).
# --------------------------------------------------------------------------- #
_libvirt_create_seed_iso() {
  local pub_key; pub_key="$(cat "${VM_SSH_KEY}.pub")"
  local seed_dir; seed_dir="$(mktemp -d /tmp/seed-XXXXXX)"
  local iso="${_LIBVIRT_VM_DIR}/${VM_NAME}-seed.iso"

  sed "s|SSH_AUTHORIZED_KEY|${pub_key}|g" \
    "${REPO_ROOT}/vm/cloud-init/user-data" > "${seed_dir}/user-data"

  cat > "${seed_dir}/meta-data" <<EOF
instance-id: ${VM_NAME}
local-hostname: ${VM_NAME}
EOF

  # Try cloud-localds first (cloud-image-utils), fall back to genisoimage
  if has cloud-localds; then
    cloud-localds "$iso" "${seed_dir}/user-data" "${seed_dir}/meta-data" \
      2>&1 | tee -a "$LOG_FILE"
  elif has genisoimage; then
    genisoimage -output "$iso" -volid cidata -joliet -rock \
      "${seed_dir}/user-data" "${seed_dir}/meta-data" \
      2>&1 | tee -a "$LOG_FILE"
  else
    die "Neither cloud-localds nor genisoimage found. Run: sudo apt install cloud-image-utils"
  fi

  rm -rf "$seed_dir"
  echo "$iso"
}

# --------------------------------------------------------------------------- #
# _libvirt_get_ip
# Waits for libvirt to assign an IP to the VM (up to max_wait seconds).
# --------------------------------------------------------------------------- #
_libvirt_get_ip() {
  local max_wait="${1:-120}" elapsed=0 ip=""
  while [[ -z "$ip" && $elapsed -lt $max_wait ]]; do
    ip=$(virsh domifaddr "${VM_NAME}" 2>/dev/null \
      | grep -oP '\d+\.\d+\.\d+\.\d+' | head -n1 || true)
    if [[ -z "$ip" ]]; then
      sleep 5
      elapsed=$(( elapsed + 5 ))
      printf "."
    fi
  done
  echo "$ip"
}

# --------------------------------------------------------------------------- #
# destroy_libvirt
# --------------------------------------------------------------------------- #
destroy_libvirt() {
  if _libvirt_vm_exists; then
    info "Destroying libvirt VM '${VM_NAME}'..."
    virsh destroy "${VM_NAME}" 2>/dev/null || true
    virsh undefine "${VM_NAME}" --remove-all-storage 2>/dev/null || true
    rm -f "${_LIBVIRT_VM_DIR}/${VM_NAME}.qcow2" \
          "${_LIBVIRT_VM_DIR}/${VM_NAME}-seed.iso"
    success "libvirt VM '${VM_NAME}' destroyed."
  else
    info "libvirt VM '${VM_NAME}' does not exist — nothing to destroy."
  fi
}

# --------------------------------------------------------------------------- #
# boot_libvirt
# --------------------------------------------------------------------------- #
boot_libvirt() {
  info "Provider: KVM/libvirt (native cloud-init)"
  ensure_libvirt

  mkdir -p "${_LIBVIRT_VM_DIR}"

  if _libvirt_vm_exists; then
    local state
    state=$(virsh domstate "${VM_NAME}" 2>/dev/null | tr -d '[:space:]' || echo "unknown")
    if [[ "$state" == "running" ]]; then
      info "VM '${VM_NAME}' already running."
    else
      info "VM '${VM_NAME}' exists (state: ${state}). Starting..."
      virsh start "${VM_NAME}" 2>&1 | tee -a "$LOG_FILE"
    fi
  else
    _libvirt_download_base_image

    local disk seed_iso
    disk="$(_libvirt_create_disk)"
    info "Creating cloud-init seed ISO..."
    seed_iso="$(_libvirt_create_seed_iso)"

    info "Launching VM with virt-install (${VM_CPU} vCPU, ${VM_RAM} MB RAM)..."
    virt-install \
      --name "${VM_NAME}" \
      --memory "${VM_RAM}" \
      --vcpus "${VM_CPU}" \
      --cpu host-passthrough \
      --machine q35 \
      --disk "${disk},format=qcow2,bus=virtio" \
      --disk "${seed_iso},device=cdrom" \
      --os-variant ubuntu24.04 \
      --network network=default,model=virtio \
      --graphics none \
      --console pty,target_type=serial \
      --import \
      --noautoconsole \
      2>&1 | tee -a "$LOG_FILE"
  fi

  info "Waiting for VM to obtain an IP address..."
  local ip
  ip="$(_libvirt_get_ip 180)"
  echo ""

  if [[ -z "$ip" ]]; then
    error "Could not determine VM IP after 180 s."
    error "Try: virsh domifaddr ${VM_NAME}"
    return 1
  fi

  VM_IP="$ip"
  VM_SSH_USER="ubuntu"
  VM_SSH_PORT=22
  ACTIVE_PROVIDER="libvirt"
  export VM_IP VM_SSH_USER VM_SSH_PORT ACTIVE_PROVIDER

  success "libvirt VM '${VM_NAME}' is up. IP: ${VM_IP}"
}
