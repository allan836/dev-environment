#!/usr/bin/env bash
# =============================================================================
# lib/providers/libvirt.sh — KVM/libvirt + cloud-init provider
#
# Boots an Ubuntu 24.04 VM directly via libvirt (virt-install).
# Uses the system QEMU driver (qemu:///system) exclusively.
# Uses a cloud image + cloud-init ISO for first-boot configuration.
#
# After a successful boot, exports:
#   ACTIVE_PROVIDER  = "libvirt"
#   VM_IP            = <IPv4 address of the VM>
#   VM_SSH_USER      = "ubuntu"
#   VM_SSH_PORT      = 22
#
# VM_SSH_KEY is set by ensure_host_ssh_key() in lib/vm.sh before boot.
#
# Requires: lib/log.sh, lib/dependencies.sh (ensure_libvirt) sourced.
#           VM_NAME, VM_CPU, VM_RAM, VM_DISK_GB, UBUNTU_CLOUD_IMAGE_URL,
#           HOST_ARCH, VM_SSH_KEY, LOG_FILE, REPO_ROOT exported.
# =============================================================================

# Always use the system QEMU driver — never the session driver.
readonly _LIBVIRT_URI="qemu:///system"

# Libvirt storage pool and directory used for all VM images.
readonly _LIBVIRT_POOL="default"
readonly _LIBVIRT_POOL_DIR="/var/lib/libvirt/images"

# Module-level output variables (set by their respective functions).
_LIBVIRT_DISK_PATH=""
_LIBVIRT_SEED_ISO_PATH=""
_LIBVIRT_SEED_DIR=""      # path to tmpdir holding user-data/meta-data/seed.iso
_LIBVIRT_VM_IP=""

# Convenience wrapper: all virsh calls go through qemu:///system.
_virsh() {
  virsh -c "${_LIBVIRT_URI}" "$@"
}

# --------------------------------------------------------------------------- #
# _debug_cmd CMD [ARGS...]
# When DEBUG=true, prints the full shell-quoted command to stderr.
# --------------------------------------------------------------------------- #
_debug_cmd() {
  if [[ "${DEBUG:-false}" == "true" ]]; then
    printf '[DEBUG]' >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
  fi
}

# --------------------------------------------------------------------------- #
# _run_cmd CMD [ARGS...]
# Runs a command, logging it and its exit code.
# On failure prints the command, its stderr, and dies.
# --------------------------------------------------------------------------- #
_run_cmd() {
  local cmd_str
  cmd_str="$(printf '%q ' "$@")"

  printf '\nRunning:\n  %s\n' "${cmd_str}" >> "${LOG_FILE}"
  _debug_cmd "$@"

  local tmp_err
  tmp_err="$(mktemp /tmp/libvirt-err-XXXXXX)"

  local rc=0
  "$@" >> "${LOG_FILE}" 2>"${tmp_err}" || rc=$?

  cat "${tmp_err}" >> "${LOG_FILE}"

  printf 'Exit code: %d\n' "${rc}" >> "${LOG_FILE}"

  if [[ ${rc} -ne 0 ]]; then
    error "Command failed (exit ${rc}):"
    error "  ${cmd_str}"
    if [[ -s "${tmp_err}" ]]; then
      error "stderr:"
      while IFS= read -r line; do error "  ${line}"; done < "${tmp_err}"
    fi
    rm -f "${tmp_err}"
    die "Aborting. See ${LOG_FILE} for full output."
  fi

  rm -f "${tmp_err}"
  return 0
}

# --------------------------------------------------------------------------- #
# _libvirt_vm_exists
# Returns 0 if the named domain exists in qemu:///system.
# --------------------------------------------------------------------------- #
_libvirt_vm_exists() {
  _virsh dominfo "${VM_NAME}" &>/dev/null
}

# --------------------------------------------------------------------------- #
# _libvirt_validate_host
# Checks that the host is KVM-capable and that every required tool is present.
# Runs virt-host-validate; stops immediately on any failure.
# --------------------------------------------------------------------------- #
_libvirt_validate_host() {
  info "Validating host for KVM/libvirt..."

  local missing=()
  for tool in virsh virt-install qemu-img; do
    has "${tool}" || missing+=("${tool}")
  done

  # Require at least one ISO-creation tool.
  if ! has cloud-localds && ! has genisoimage && ! has xorriso; then
    missing+=("cloud-localds or genisoimage or xorriso")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Missing required tools: ${missing[*]}"
    error "Re-run provision.sh — it will install them, or install manually:"
    error "  sudo dnf install -y @virtualization virt-install cloud-utils genisoimage"
    die "Host validation failed: missing tools."
  fi

  # virt-host-validate checks KVM, IOMMU, etc.
  if has virt-host-validate; then
    info "Running virt-host-validate..."
    local vhv_out vhv_rc
    vhv_out="$(virt-host-validate qemu 2>&1)" || true
    vhv_rc=$?
    printf '%s\n' "${vhv_out}" >> "${LOG_FILE}"

    # A non-zero exit means at least one hard FAIL (not just WARN).
    if printf '%s\n' "${vhv_out}" | grep -q 'FAIL'; then
      error "virt-host-validate reported failures:"
      printf '%s\n' "${vhv_out}" | grep 'FAIL' | while IFS= read -r l; do error "  ${l}"; done
      die "Host does not meet KVM requirements. Check ${LOG_FILE}."
    fi
    success "virt-host-validate: OK (warnings, if any, are non-fatal)."
  else
    # Minimal manual KVM check if virt-host-validate is absent.
    if [[ ! -e /dev/kvm ]]; then
      die "KVM not available (/dev/kvm missing). Enable hardware virtualisation in BIOS/UEFI."
    fi
    info "virt-host-validate not found — /dev/kvm present, continuing."
  fi

  # Verify the system QEMU driver is reachable.
  if ! _virsh list --all &>/dev/null; then
    error "Cannot connect to ${_LIBVIRT_URI}."
    error "Is libvirtd running?  sudo systemctl status libvirtd"
    die "libvirt connection failed."
  fi

  success "Host validation passed."
}

# --------------------------------------------------------------------------- #
# _libvirt_ensure_default_network
# Creates, starts, and autoruns the standard NAT network if it is missing.
# --------------------------------------------------------------------------- #
_libvirt_ensure_default_network() {
  if _virsh net-info default &>/dev/null; then
    local net_active
    net_active="$(_virsh net-info default 2>/dev/null | awk '/^Active:/{print $2}')"
    if [[ "${net_active}" != "yes" ]]; then
      info "Starting libvirt default network..."
      _run_cmd virsh -c "${_LIBVIRT_URI}" net-start default
    fi
    _virsh net-autostart default &>/dev/null || true
    info "libvirt default network: active."
    return 0
  fi

  info "Default libvirt network not found — creating standard NAT network..."

  local net_xml
  net_xml="$(mktemp /tmp/libvirt-net-XXXXXX.xml)"
  cat > "${net_xml}" <<'EOF'
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <mac address='52:54:00:00:00:01'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF

  _run_cmd virsh -c "${_LIBVIRT_URI}" net-define  "${net_xml}"
  _run_cmd virsh -c "${_LIBVIRT_URI}" net-start    default
  _run_cmd virsh -c "${_LIBVIRT_URI}" net-autostart default
  rm -f "${net_xml}"
  success "Default NAT network created and started."
}

# --------------------------------------------------------------------------- #
# _libvirt_ensure_default_pool
# Creates and starts the default storage pool if it is missing.
# --------------------------------------------------------------------------- #
_libvirt_ensure_default_pool() {
  if _virsh pool-info "${_LIBVIRT_POOL}" &>/dev/null; then
    local pool_active
    pool_active="$(_virsh pool-info "${_LIBVIRT_POOL}" 2>/dev/null | awk '/^State:/{print $2}')"
    if [[ "${pool_active}" != "running" ]]; then
      info "Starting libvirt storage pool '${_LIBVIRT_POOL}'..."
      _run_cmd virsh -c "${_LIBVIRT_URI}" pool-start "${_LIBVIRT_POOL}"
    fi
    _virsh pool-autostart "${_LIBVIRT_POOL}" &>/dev/null || true
    info "libvirt storage pool '${_LIBVIRT_POOL}': active."
    return 0
  fi

  info "Storage pool '${_LIBVIRT_POOL}' not found — creating at ${_LIBVIRT_POOL_DIR}..."
  sudo mkdir -p "${_LIBVIRT_POOL_DIR}"
  sudo chown root:root "${_LIBVIRT_POOL_DIR}"
  sudo chmod 0711 "${_LIBVIRT_POOL_DIR}"

  _run_cmd virsh -c "${_LIBVIRT_URI}" pool-define-as \
    "${_LIBVIRT_POOL}" dir --target "${_LIBVIRT_POOL_DIR}"
  _run_cmd virsh -c "${_LIBVIRT_URI}" pool-build     "${_LIBVIRT_POOL}"
  _run_cmd virsh -c "${_LIBVIRT_URI}" pool-start      "${_LIBVIRT_POOL}"
  _run_cmd virsh -c "${_LIBVIRT_URI}" pool-autostart  "${_LIBVIRT_POOL}"
  success "Storage pool '${_LIBVIRT_POOL}' created at ${_LIBVIRT_POOL_DIR}."
}

# --------------------------------------------------------------------------- #
# _libvirt_base_image_path  (stdout = path, no other output)
# --------------------------------------------------------------------------- #
_libvirt_base_image_path() {
  echo "${_LIBVIRT_POOL_DIR}/noble-server-cloudimg-${HOST_ARCH}.img"
}

# --------------------------------------------------------------------------- #
# _libvirt_download_base_image
# Downloads the Ubuntu 24.04 cloud image into the system pool if not cached.
#
# /var/lib/libvirt/images is owned by root (0711) so curl must write to a
# user-writable temp file in /tmp first; we then sudo-move it into the pool.
#
# Each URL is tried up to _LIBVIRT_DOWNLOAD_RETRIES times with exponential
# backoff before falling through to the next candidate.
# --------------------------------------------------------------------------- #
_libvirt_download_base_image() {
  local dest
  dest="$(_libvirt_base_image_path)"

  if [[ -f "${dest}" ]]; then
    info "Ubuntu 24.04 cloud image already cached: ${dest}"
    return 0
  fi

  sudo mkdir -p "${_LIBVIRT_POOL_DIR}"

  local primary_url mirror_url
  if [[ "${HOST_ARCH}" == "arm64" ]]; then
    primary_url="${UBUNTU_CLOUD_IMAGE_URL_ARM}"
    mirror_url="https://mirrors.edge.kernel.org/ubuntu-cloud-images/noble/current/noble-server-cloudimg-arm64.img"
  else
    primary_url="${UBUNTU_CLOUD_IMAGE_URL}"
    mirror_url="https://mirrors.edge.kernel.org/ubuntu-cloud-images/noble/current/noble-server-cloudimg-amd64.img"
  fi

  # Download into /tmp — the pool directory is root-owned (0711) and the
  # current user cannot write there directly.
  local tmp_dest
  tmp_dest="$(mktemp /tmp/noble-cloudimg-XXXXXX.img)"

  local -r _LIBVIRT_DOWNLOAD_RETRIES=3
  local url attempt rc wait_sec

  for url in "${primary_url}" "${mirror_url}"; do
    for attempt in $(seq 1 "${_LIBVIRT_DOWNLOAD_RETRIES}"); do
      info "Downloading cloud image (attempt ${attempt}/${_LIBVIRT_DOWNLOAD_RETRIES}): ${url}"
      printf 'Downloading: %s  (attempt %d/%d)\n' \
        "${url}" "${attempt}" "${_LIBVIRT_DOWNLOAD_RETRIES}" >> "${LOG_FILE}"

      rc=0
      curl -fL \
        --max-time 600 \
        --retry 0 \
        --progress-bar \
        "${url}" -o "${tmp_dest}" 2>>"${LOG_FILE}" || rc=$?

      printf 'curl exit code: %d\n' "${rc}" >> "${LOG_FILE}"

      if [[ ${rc} -eq 0 && -s "${tmp_dest}" ]]; then
        info "Download complete — moving to pool: ${dest}"
        sudo mv "${tmp_dest}" "${dest}"
        sudo chmod 660 "${dest}" 2>/dev/null || true
        success "Cloud image ready: ${dest}"
        return 0
      fi

      # Diagnose the most common failure before retrying.
      case "${rc}" in
        23) warn "  curl exit 23 (write error) — output path not writable? Tmp: ${tmp_dest}" ;;
        22) warn "  curl exit 22 (HTTP error / 404) — URL may be wrong or server is down." ;;
        28) warn "  curl exit 28 (timeout) — slow connection; will retry." ;;
        6)  warn "  curl exit 6 (could not resolve host) — check network connectivity." ;;
        *)  warn "  curl exit ${rc}." ;;
      esac

      rm -f "${tmp_dest}"
      tmp_dest="$(mktemp /tmp/noble-cloudimg-XXXXXX.img)"

      if [[ ${attempt} -lt ${_LIBVIRT_DOWNLOAD_RETRIES} ]]; then
        wait_sec=$(( attempt * 5 ))
        warn "  Retrying in ${wait_sec}s..."
        sleep "${wait_sec}"
      fi
    done

    warn "All ${_LIBVIRT_DOWNLOAD_RETRIES} attempts failed for: ${url}"
    printf 'All retries exhausted for %s\n' "${url}" >> "${LOG_FILE}"
  done

  rm -f "${tmp_dest}"
  error "Cloud image download failed for all candidates."
  error "URLs tried:"
  error "  ${primary_url}"
  error "  ${mirror_url}"
  error "Full curl output is in: ${LOG_FILE}"
  error "To download manually and place it in the pool:"
  error "  curl -L '${primary_url}' -o /tmp/noble.img"
  error "  sudo mv /tmp/noble.img '${dest}'"
  die "Aborting: could not download Ubuntu cloud image."
}

# --------------------------------------------------------------------------- #
# _libvirt_create_disk
# Creates a qcow2 disk in the system pool backed by the base image.
# Sets _LIBVIRT_DISK_PATH (no stdout pollution).
# --------------------------------------------------------------------------- #
_libvirt_create_disk() {
  local base
  base="$(_libvirt_base_image_path)"
  _LIBVIRT_DISK_PATH="${_LIBVIRT_POOL_DIR}/${VM_NAME}.qcow2"

  if [[ -f "${_LIBVIRT_DISK_PATH}" ]]; then
    info "VM disk already exists: ${_LIBVIRT_DISK_PATH}"
    return 0
  fi

  info "Creating VM disk (${VM_DISK_GB}G overlay): ${_LIBVIRT_DISK_PATH}"
  _run_cmd sudo qemu-img create \
    -b "${base}" -f qcow2 -F qcow2 \
    "${_LIBVIRT_DISK_PATH}" "${VM_DISK_GB}G"

  sudo chmod 660 "${_LIBVIRT_DISK_PATH}" 2>/dev/null || true
  success "VM disk created."
}

# _libvirt_create_seed_iso
# Writes cloud-init nocloud ISO into the system pool.
# Sets _LIBVIRT_SEED_ISO_PATH and _LIBVIRT_SEED_DIR.
#
# Steps performed:
#   1. Verify SSH public key exists, is valid, and is not a placeholder
#   2. Print key fingerprint to log and stderr
#   3. Render user-data from template (sed substitution)
#   4. Verify placeholder was replaced; verify key prefix is present
#   5. If DEV_MODE=true: inject ssh_pwauth + chpasswd block, print password
#   6. Validate YAML with python3 and cloud-init devel schema (if available)
#   7. Write meta-data
#   8. Create ISO from seed dir
#   9. If DEBUG=true: keep seed dir and print artifact paths;
#      otherwise clean up seed dir
# --------------------------------------------------------------------------- #
_libvirt_create_seed_iso() {
  _LIBVIRT_SEED_ISO_PATH="${_LIBVIRT_POOL_DIR}/${VM_NAME}-seed.iso"

  # ------------------------------------------------------------------ #
  # 1. Verify SSH public key
  # ------------------------------------------------------------------ #
  local pub_key_file="${VM_SSH_KEY}.pub"

  info "Verifying SSH public key: ${pub_key_file}"
  printf 'SSH key file: %s\n' "${pub_key_file}" >> "${LOG_FILE}"

  if [[ ! -f "${pub_key_file}" ]]; then
    die "SSH public key not found: ${pub_key_file}. ensure_host_ssh_key() must run before boot_libvirt()."
  fi

  local pub_key
  pub_key="$(tr -d '\n\r' < "${pub_key_file}")"

  if [[ -z "${pub_key}" ]]; then
    die "SSH public key file is empty: ${pub_key_file}"
  fi

  if [[ "${pub_key}" == *"SSH_AUTHORIZED_KEY"* ]]; then
    die "SSH public key file contains the literal placeholder 'SSH_AUTHORIZED_KEY' — file is corrupt: ${pub_key_file}"
  fi

  if ! [[ "${pub_key}" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com) ]]; then
    error "SSH public key does not start with a recognised key type."
    error "  File  : ${pub_key_file}"
    error "  Start : ${pub_key:0:80}"
    die "Invalid SSH public key — cannot create seed ISO."
  fi

  local fingerprint
  fingerprint="$(ssh-keygen -lf "${pub_key_file}" 2>&1 || echo 'FAILED')"
  info "SSH key fingerprint: ${fingerprint}"
  printf 'SSH key fingerprint: %s\n' "${fingerprint}" >> "${LOG_FILE}"

  # ------------------------------------------------------------------ #
  # 2. Create seed working directory
  # ------------------------------------------------------------------ #
  local seed_dir
  seed_dir="$(mktemp -d /tmp/seed-XXXXXX)"
  _LIBVIRT_SEED_DIR="${seed_dir}"

  info "Seed working directory: ${seed_dir}"
  printf 'Seed dir: %s\n' "${seed_dir}" >> "${LOG_FILE}"

  # ------------------------------------------------------------------ #
  # 3. Render user-data (key substitution)
  # ------------------------------------------------------------------ #
  info "Rendering cloud-init user-data from template..."
  printf 'Template: %s/vm/cloud-init/user-data\n' "${REPO_ROOT}" >> "${LOG_FILE}"

  sed "s|SSH_AUTHORIZED_KEY|${pub_key}|g" \
    "${REPO_ROOT}/vm/cloud-init/user-data" > "${seed_dir}/user-data"

  # ------------------------------------------------------------------ #
  # 4. Verify substitution succeeded
  # ------------------------------------------------------------------ #
  if grep -qF 'SSH_AUTHORIZED_KEY' "${seed_dir}/user-data"; then
    error "Placeholder 'SSH_AUTHORIZED_KEY' is still present after substitution!"
    error "  Template : ${REPO_ROOT}/vm/cloud-init/user-data"
    error "  Rendered : ${seed_dir}/user-data"
    error "  Key file : ${pub_key_file}"
    [[ "${DEBUG:-false}" != "true" ]] && rm -rf "${seed_dir}" && _LIBVIRT_SEED_DIR=""
    die "SSH key substitution failed — aborting to prevent a locked-out VM."
  fi

  local key_prefix="${pub_key:0:20}"
  if ! grep -qF "${key_prefix}" "${seed_dir}/user-data"; then
    error "Rendered user-data does not contain the expected key prefix."
    error "  Expected prefix : ${key_prefix}"
    error "  Key file        : ${pub_key_file}"
    [[ "${DEBUG:-false}" != "true" ]] && rm -rf "${seed_dir}" && _LIBVIRT_SEED_DIR=""
    die "SSH key not found in rendered user-data — aborting."
  fi

  success "SSH key successfully embedded in user-data."
  printf 'Rendered user-data:\n%s\n' "$(cat "${seed_dir}/user-data")" >> "${LOG_FILE}"

  # ------------------------------------------------------------------ #
  # 5. Dev-mode: inject password authentication (DEVELOPMENT ONLY)
  # ------------------------------------------------------------------ #
  if [[ "${DEV_MODE:-false}" == "true" ]]; then
    warn "================================================================"
    warn "  *** DEV MODE ENABLED — password authentication will be injected"
    warn "  *** THIS IS FOR DEVELOPMENT/TESTING ONLY — NOT FOR PRODUCTION"
    warn "================================================================"

    local dev_password
    dev_password="$(openssl rand -hex 12)"

    info "[DEV MODE] Injecting ssh_pwauth + chpasswd block into user-data..."

    local py_inject
    py_inject="$(mktemp /tmp/devmode-inject-XXXXXX.py)"
    cat > "${py_inject}" << 'PYEOF'
import sys

path = sys.argv[1]
password = sys.argv[2]

dev_block = (
    "\n"
    "# ---- [DEV MODE] Password authentication (DEVELOPMENT ONLY) ----\n"
    "ssh_pwauth: true\n"
    "\n"
    "chpasswd:\n"
    "  expire: false\n"
    "  users:\n"
    "    - name: ubuntu\n"
    "      password: \"" + password + "\"\n"
    "      type: text\n"
    "    - name: developer\n"
    "      password: \"" + password + "\"\n"
    "      type: text\n"
)

with open(path, 'a') as f:
    f.write(dev_block)

print("[DEV MODE] dev-mode block injected successfully")
PYEOF

    local inject_rc=0
    python3 "${py_inject}" "${seed_dir}/user-data" "${dev_password}" \
      >> "${LOG_FILE}" 2>&1 || inject_rc=$?
    rm -f "${py_inject}"

    if [[ ${inject_rc} -ne 0 ]]; then
      [[ "${DEBUG:-false}" != "true" ]] && rm -rf "${seed_dir}" && _LIBVIRT_SEED_DIR=""
      die "[DEV MODE] Failed to inject password block into user-data (exit ${inject_rc}). See ${LOG_FILE}."
    fi

    printf 'DEV MODE password stored in log (see provision.log)\n' >> "${LOG_FILE}"
    printf 'DEV MODE password: %s\n' "${dev_password}" >> "${LOG_FILE}"

    warn ""
    warn "  [DEV MODE] ┌─────────────────────────────────────────────┐"
    warn "  [DEV MODE] │  VM login: ubuntu / developer               │"
    warn "  [DEV MODE] │  Password: ${dev_password}     │"
    warn "  [DEV MODE] │  SSH password auth: ENABLED                 │"
    warn "  [DEV MODE] │  NEVER deploy this configuration to production│"
    warn "  [DEV MODE] └─────────────────────────────────────────────┘"
    warn ""
  fi

  # ------------------------------------------------------------------ #
  # 6. Validate YAML
  # ------------------------------------------------------------------ #
  info "Validating cloud-init user-data YAML..."

  local py_validate
  py_validate="$(mktemp /tmp/yaml-validate-XXXXXX.py)"
  cat > "${py_validate}" << 'PYEOF'
import sys, os

path = sys.argv[1]

try:
    import yaml
except ImportError:
    print("WARNING: PyYAML not available — skipping YAML validation.", file=sys.stderr)
    sys.exit(0)

with open(path, 'r') as f:
    content = f.read()

# Strip the #cloud-config directive line before parsing
lines = content.splitlines()
yaml_lines = [l for l in lines if not l.strip().startswith('#cloud-config')]
yaml_text = '\n'.join(yaml_lines)

try:
    yaml.safe_load(yaml_text)
    print("YAML validation passed.")
except yaml.YAMLError as e:
    print(f"YAML validation FAILED: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

  local validate_rc=0
  python3 "${py_validate}" "${seed_dir}/user-data" >> "${LOG_FILE}" 2>&1 || validate_rc=$?
  rm -f "${py_validate}"

  if [[ ${validate_rc} -ne 0 ]]; then
    error "cloud-init user-data YAML validation failed!"
    error "  Rendered file: ${seed_dir}/user-data"
    error "  See ${LOG_FILE} for the parser error."
    [[ "${DEBUG:-false}" != "true" ]] && rm -rf "${seed_dir}" && _LIBVIRT_SEED_DIR=""
    die "Aborting: malformed cloud-init YAML would produce a broken VM."
  fi

  success "YAML validation passed."

  if has cloud-init; then
    info "Running cloud-init schema validation..."
    local schema_rc=0
    cloud-init devel schema --config-file "${seed_dir}/user-data" \
      >> "${LOG_FILE}" 2>&1 || schema_rc=$?
    if [[ ${schema_rc} -ne 0 ]]; then
      warn "cloud-init schema check reported issues (exit ${schema_rc}) — see ${LOG_FILE}."
      warn "Continuing: schema warnings are non-fatal."
    else
      success "cloud-init schema validation passed."
    fi
  fi

  # ------------------------------------------------------------------ #
  # 7. Write meta-data
  # ------------------------------------------------------------------ #
  printf 'instance-id: %s\nlocal-hostname: %s\n' \
    "${VM_NAME}" "${VM_NAME}" > "${seed_dir}/meta-data"
  printf 'Rendered meta-data:\n%s\n' "$(cat "${seed_dir}/meta-data")" >> "${LOG_FILE}"

  # ------------------------------------------------------------------ #
  # 8. Create ISO
  # ------------------------------------------------------------------ #
  info "Creating cloud-init seed ISO: ${_LIBVIRT_SEED_ISO_PATH}"
  printf 'ISO tool selection:\n' >> "${LOG_FILE}"

  local tmp_iso="${seed_dir}/seed.iso"
  local iso_rc=0

  if has cloud-localds; then
    printf '  Using: cloud-localds\n' >> "${LOG_FILE}"
    _debug_cmd cloud-localds "${tmp_iso}" "${seed_dir}/user-data" "${seed_dir}/meta-data"
    cloud-localds "${tmp_iso}" "${seed_dir}/user-data" "${seed_dir}/meta-data" \
      >> "${LOG_FILE}" 2>&1 || iso_rc=$?
  elif has genisoimage; then
    printf '  Using: genisoimage\n' >> "${LOG_FILE}"
    _debug_cmd genisoimage -output "${tmp_iso}" -volid cidata \
      -joliet -rock "${seed_dir}/user-data" "${seed_dir}/meta-data"
    genisoimage -output "${tmp_iso}" -volid cidata \
      -joliet -rock "${seed_dir}/user-data" "${seed_dir}/meta-data" \
      >> "${LOG_FILE}" 2>&1 || iso_rc=$?
  elif has xorriso; then
    printf '  Using: xorriso\n' >> "${LOG_FILE}"
    _debug_cmd xorriso -as mkisofs -output "${tmp_iso}" \
      -volid cidata -joliet -rock "${seed_dir}/user-data" "${seed_dir}/meta-data"
    xorriso -as mkisofs -output "${tmp_iso}" \
      -volid cidata -joliet -rock "${seed_dir}/user-data" "${seed_dir}/meta-data" \
      >> "${LOG_FILE}" 2>&1 || iso_rc=$?
  else
    [[ "${DEBUG:-false}" != "true" ]] && rm -rf "${seed_dir}" && _LIBVIRT_SEED_DIR=""
    die "No ISO-creation tool found. Install cloud-image-utils, genisoimage, or xorriso."
  fi

  if [[ ${iso_rc} -ne 0 || ! -f "${tmp_iso}" ]]; then
    error "Seed ISO creation failed (exit ${iso_rc})."
    [[ "${DEBUG:-false}" != "true" ]] && rm -rf "${seed_dir}" && _LIBVIRT_SEED_DIR=""
    die "cloud-init seed ISO creation failed. See ${LOG_FILE}."
  fi

  sudo cp "${tmp_iso}" "${_LIBVIRT_SEED_ISO_PATH}"
  sudo chmod 660 "${_LIBVIRT_SEED_ISO_PATH}" 2>/dev/null || true

  printf 'Seed ISO copied to pool: %s\n' "${_LIBVIRT_SEED_ISO_PATH}" >> "${LOG_FILE}"

  # ------------------------------------------------------------------ #
  # 9. Debug mode: preserve artifacts; otherwise clean up
  # ------------------------------------------------------------------ #
  if [[ "${DEBUG:-false}" == "true" ]]; then
    info "[DEBUG] Seed artifacts preserved for inspection:"
    info "[DEBUG]   user-data : ${seed_dir}/user-data"
    info "[DEBUG]   meta-data : ${seed_dir}/meta-data"
    info "[DEBUG]   seed ISO  : ${seed_dir}/seed.iso"
    info "[DEBUG]   pool ISO  : ${_LIBVIRT_SEED_ISO_PATH}"
    printf '[DEBUG] Seed dir preserved: %s\n' "${seed_dir}" >> "${LOG_FILE}"
  else
    rm -rf "${seed_dir}"
    _LIBVIRT_SEED_DIR=""
  fi

  success "cloud-init seed ISO created: ${_LIBVIRT_SEED_ISO_PATH}"
}
# _libvirt_get_ip
# Polls for the VM's IPv4 address up to max_wait seconds.
# Sets _LIBVIRT_VM_IP on success; leaves it empty on timeout.
# Prints diagnostics to stderr if nothing found.
# --------------------------------------------------------------------------- #
_libvirt_get_ip() {
  local max_wait="${1:-180}"
  local elapsed=0
  local ipv4_re='^([0-9]{1,3}[.]){3}[0-9]{1,3}$'
  _LIBVIRT_VM_IP=""

  info "Waiting for VM IP (up to ${max_wait}s)..."

  while [[ ${elapsed} -lt ${max_wait} ]]; do
    local candidate=""

    # Method 1: domifaddr default (lease)
    candidate="$(_virsh domifaddr "${VM_NAME}" 2>/dev/null \
      | grep -oP '\d+\.\d+\.\d+\.\d+(?=/)' \
      | grep -v '^127\.' | head -n1 || true)"

    # Method 2: QEMU guest agent
    if [[ -z "${candidate}" ]]; then
      candidate="$(_virsh domifaddr "${VM_NAME}" --source agent 2>/dev/null \
        | grep -oP '\d+\.\d+\.\d+\.\d+(?=/)' \
        | grep -v '^127\.' | head -n1 || true)"
    fi

    # Method 3: lease source explicit
    if [[ -z "${candidate}" ]]; then
      candidate="$(_virsh domifaddr "${VM_NAME}" --source lease 2>/dev/null \
        | grep -oP '\d+\.\d+\.\d+\.\d+(?=/)' \
        | grep -v '^127\.' | head -n1 || true)"
    fi

    # Method 4: ARP cache
    if [[ -z "${candidate}" ]]; then
      candidate="$(_virsh domifaddr "${VM_NAME}" --source arp 2>/dev/null \
        | grep -oP '\d+\.\d+\.\d+\.\d+(?=/)' \
        | grep -v '^127\.' | head -n1 || true)"
    fi

    # Method 5: DHCP lease table on the default network
    if [[ -z "${candidate}" ]]; then
      candidate="$(_virsh net-dhcp-leases default 2>/dev/null \
        | grep -oP '\d+\.\d+\.\d+\.\d+(?=/)' \
        | grep -v '^127\.' | head -n1 || true)"
    fi

    # Validate it is a proper IPv4 address
    if [[ -n "${candidate}" && "${candidate}" =~ ${ipv4_re} ]]; then
      _LIBVIRT_VM_IP="${candidate}"
      printf '\n' >&2
      success "VM IP address: ${_LIBVIRT_VM_IP}"
      return 0
    fi

    # Every 15 seconds show VM state and DHCP lease status so the user can
    # see what the guest is doing rather than watching a featureless spinner.
    if (( elapsed > 0 && elapsed % 15 == 0 )); then
      local vm_state
      vm_state="$(_virsh domstate "${VM_NAME}" 2>/dev/null | tr -d '[:space:]' || echo "unknown")"
      local dhcp_info
      dhcp_info="$(_virsh net-dhcp-leases default 2>/dev/null \
        | grep -oP '\d+\.\d+\.\d+\.\d+/\d+' | head -n1 || true)"
      printf '\n  VM state: %s | DHCP lease: %s (%ds elapsed)\n' \
        "${vm_state}" "${dhcp_info:-none yet}" "${elapsed}" >&2
    else
      printf '.' >&2
    fi

    sleep 5
    elapsed=$(( elapsed + 5 ))
  done

  printf '\n' >&2

  # Timeout — print diagnostics automatically
  error "No IP found for '${VM_NAME}' after ${max_wait}s."
  error ""
  error "Diagnostic output follows (also in ${LOG_FILE}):"
  {
    echo "--- virsh list --all ---"
    _virsh list --all 2>&1 || true
    echo "--- virsh dominfo ${VM_NAME} ---"
    _virsh dominfo "${VM_NAME}" 2>&1 || true
    echo "--- virsh domiflist ${VM_NAME} ---"
    _virsh domiflist "${VM_NAME}" 2>&1 || true
    echo "--- virsh domifaddr ${VM_NAME} --source arp ---"
    _virsh domifaddr "${VM_NAME}" --source arp 2>&1 || true
    echo "--- virsh net-list --all ---"
    _virsh net-list --all 2>&1 || true
    echo "--- virsh net-dhcp-leases default ---"
    _virsh net-dhcp-leases default 2>&1 || true
    echo "--- journalctl virtqemud (last 50 lines) ---"
    journalctl -u virtqemud --no-pager -n 50 2>&1 || true
  } | tee -a "${LOG_FILE}" >&2

  return 1
}

# --------------------------------------------------------------------------- #
# destroy_libvirt
# --------------------------------------------------------------------------- #
destroy_libvirt() {
  if _libvirt_vm_exists; then
    info "Destroying libvirt VM '${VM_NAME}'..."
    _virsh destroy "${VM_NAME}" 2>/dev/null || true
    # Try --nvram first (required for UEFI/q35 VMs); fall back without it.
    if ! _virsh undefine "${VM_NAME}" --nvram 2>/dev/null; then
      _virsh undefine "${VM_NAME}" 2>/dev/null || true
    fi
    sudo rm -f \
      "${_LIBVIRT_POOL_DIR}/${VM_NAME}.qcow2" \
      "${_LIBVIRT_POOL_DIR}/${VM_NAME}-seed.iso"
    success "libvirt VM '${VM_NAME}' destroyed."
  else
    info "libvirt VM '${VM_NAME}' does not exist — nothing to destroy."
  fi
}

# --------------------------------------------------------------------------- #
# boot_libvirt
# Full lifecycle: validate → prepare resources → boot → verify → IP → export.
# --------------------------------------------------------------------------- #
boot_libvirt() {
  info "Provider: KVM/libvirt  (${_LIBVIRT_URI})"

  # Warm up sudo credentials once before any long-running operations
  # (the cloud image download can take several minutes).
  if ! sudo -n true 2>/dev/null; then
    info "This provisioner needs sudo for pool/image operations — please authenticate:"
    sudo true || die "sudo authentication failed."
  fi

  ensure_libvirt
  _libvirt_validate_host
  _libvirt_ensure_default_network
  _libvirt_ensure_default_pool

  if _libvirt_vm_exists; then
    local state
    state="$(_virsh domstate "${VM_NAME}" 2>/dev/null | tr -d '[:space:]' || echo "unknown")"
    if [[ "${state}" == "running" ]]; then
      info "VM '${VM_NAME}' already running."
    else
      info "VM '${VM_NAME}' exists (state: ${state}) — starting..."
      _run_cmd virsh -c "${_LIBVIRT_URI}" start "${VM_NAME}"
    fi
  else
    _libvirt_download_base_image

    _libvirt_create_disk
    local disk_path="${_LIBVIRT_DISK_PATH}"

    _libvirt_create_seed_iso
    local seed_path="${_LIBVIRT_SEED_ISO_PATH}"

    info "Launching VM: ${VM_NAME}  (${VM_CPU} vCPU / ${VM_RAM} MB RAM / ${VM_DISK_GB} GB disk)"

    local vi_cmd=(
      virt-install
      --connect    "${_LIBVIRT_URI}"
      --name       "${VM_NAME}"
      --memory     "${VM_RAM}"
      --vcpus      "${VM_CPU}"
      --cpu        host-passthrough
      --machine    q35
      --disk       "path=${disk_path},format=qcow2,bus=virtio"
      --disk       "path=${seed_path},device=cdrom"
      --os-variant ubuntu24.04
      --network    "network=default,model=virtio"
      --graphics   none
      --console    pty,target_type=serial
      --import
      --noautoconsole
    )

    _run_cmd "${vi_cmd[@]}"

    if ! _libvirt_vm_exists; then
      error "virt-install completed but domain '${VM_NAME}' is not registered."
      error "Check ${LOG_FILE} for the full virt-install output."
      die "VM creation verification failed."
    fi
    success "VM '${VM_NAME}' registered in libvirt."
  fi

  local state
  state="$(_virsh domstate "${VM_NAME}" 2>/dev/null | tr -d '[:space:]' || echo "unknown")"
  if [[ "${state}" != "running" ]]; then
    error "VM '${VM_NAME}' is in state '${state}' — expected 'running'."
    _virsh dominfo "${VM_NAME}" >> "${LOG_FILE}" 2>&1 || true
    die "VM did not start. See ${LOG_FILE}."
  fi

  _libvirt_get_ip 180 || die "Aborting: no IP address found for VM '${VM_NAME}'."

  if [[ ! "${_LIBVIRT_VM_IP}" =~ ^([0-9]{1,3}[.]){3}[0-9]{1,3}$ ]]; then
    die "IP detection returned an invalid value: '${_LIBVIRT_VM_IP}'."
  fi

  VM_IP="${_LIBVIRT_VM_IP}"
  VM_SSH_USER="ubuntu"
  VM_SSH_PORT=22
  ACTIVE_PROVIDER="libvirt"
  export VM_IP VM_SSH_USER VM_SSH_PORT ACTIVE_PROVIDER

  success "libvirt VM '${VM_NAME}' is up.  IP: ${VM_IP}"
}