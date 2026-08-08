#!/usr/bin/env bash
# =============================================================================
# lib/vpn.sh — FortiVPN (openfortivpn) setup and connect helper
#
# Manages the lifecycle of an openfortivpn tunnel inside the VM so that
# Docker can reach private registries (kv_cassandra, etc.) during provisioning.
#
# Behaviour:
#   First run  — prompts for password (saved to ~/.config/openfortivpn/config
#                in the VM) + OTP.  Certificate fingerprint is auto-discovered
#                if VPN_TRUSTED_CERT is not set in config.env.
#   Later runs — config file already has the password; only OTP is prompted.
#
# Requires:
#   lib/log.sh, lib/vm.sh sourced
#   VM_IP, VM_SSH_USER, VM_SSH_KEY, VM_SSH_PORT, VM_USER exported
#   VPN_HOST, VPN_PORT, VPN_USERNAME, VPN_TRUSTED_CERT exported (config.env)
# =============================================================================

# --------------------------------------------------------------------------- #
# _vpn_discover_cert
# Runs openfortivpn inside the VM without a trusted-cert to extract the
# gateway's SHA-256 fingerprint from the error output.
# Prints the fingerprint string (e.g. "sha256:abcdef...") to stdout.
# Returns 1 if fingerprint could not be parsed.
# --------------------------------------------------------------------------- #
_vpn_discover_cert() {
  local vpn_user="$1" vpn_pass="$2"

  local raw_output
  raw_output=$(vm_exec "
    sudo timeout 12 openfortivpn \
      '${VPN_HOST}:${VPN_PORT:-10443}' \
      --username='${vpn_user}' \
      --password='${vpn_pass}' \
      2>&1 || true
  " 2>/dev/null || true)

  # openfortivpn prints the fingerprint in one of these forms:
  #   sha256:<hex>
  #   trusted-cert = <hex>
  #   Fingerprint: <hex:colon:separated>
  local fp=""
  fp=$(printf '%s\n' "${raw_output}" \
    | grep -oP 'sha256:[a-f0-9]+' | head -1 || true)
  if [[ -z "${fp}" ]]; then
    fp=$(printf '%s\n' "${raw_output}" \
      | grep -oP '(?<=trusted-cert = )[a-f0-9:]+' | head -1 || true)
  fi
  if [[ -z "${fp}" ]]; then
    fp=$(printf '%s\n' "${raw_output}" \
      | grep -oP '(?<=Fingerprint: )[a-f0-9:]+' | head -1 || true)
  fi

  [[ -z "${fp}" ]] && return 1
  printf '%s' "${fp}"
}

# --------------------------------------------------------------------------- #
# _vpn_write_config
# Writes ~/.config/openfortivpn/config inside the VM (chmod 600).
# --------------------------------------------------------------------------- #
_vpn_write_config() {
  local vpn_config="$1"
  local vpn_pass="$2"
  local trusted_cert="$3"

  local cert_line=""
  [[ -n "${trusted_cert}" ]] && cert_line="trusted-cert = ${trusted_cert}"

  vm_exec "
    mkdir -p \"\$(dirname ${vpn_config})\"
    cat > ${vpn_config} << 'EOVPNCFG'
host = ${VPN_HOST}
port = ${VPN_PORT:-10443}
username = ${VPN_USERNAME}
password = ${vpn_pass}
${cert_line}
EOVPNCFG
    chmod 600 ${vpn_config}
    echo 'VPN config saved'
  " 2>&1 | tee -a "${LOG_FILE}"
}

# --------------------------------------------------------------------------- #
# _vpn_first_time_setup
# Interactive: prompts for password, discovers/confirms trusted cert, writes
# the config file to the VM.
# --------------------------------------------------------------------------- #
_vpn_first_time_setup() {
  local vpn_config="$1"

  echo ""
  echo -e "${_BOLD}  ┌─────────────────────────────────────────────────────────┐${_RESET}"
  echo -e "${_BOLD}  │           FortiVPN — First-Time Setup                    │${_RESET}"
  echo -e "${_BOLD}  └─────────────────────────────────────────────────────────┘${_RESET}"
  echo ""
  echo -e "  Host    : ${_CYAN}${VPN_HOST}:${VPN_PORT:-10443}${_RESET}"
  echo -e "  User    : ${VPN_USERNAME}"
  echo -e "  Config  : ${vpn_config}  (inside VM)"
  echo ""
  echo -e "  Your password is saved once.  On subsequent runs only an OTP is needed."
  echo ""

  local _pass=""
  read -rsp "  VPN password: " _pass
  echo ""

  # ── Cert fingerprint ─────────────────────────────────────────────────── #
  local _cert="${VPN_TRUSTED_CERT:-}"

  if [[ -z "${_cert}" ]]; then
    info "Discovering VPN server certificate fingerprint..."
    _cert=$(_vpn_discover_cert "${VPN_USERNAME}" "${_pass}") || true

    if [[ -n "${_cert}" ]]; then
      echo ""
      echo -e "  Server certificate fingerprint: ${_CYAN}${_cert}${_RESET}"
      echo -e "  Verify this matches your organisation's VPN gateway (ask IT if unsure)."
      echo ""
      read -rp "  Trust this certificate and continue? [Y/n] " _answer
      case "${_answer,,}" in
        n|no)
          error "VPN setup cancelled by user."
          unset _pass
          return 1
          ;;
      esac
    else
      warn "Could not auto-discover certificate fingerprint."
      warn "Set VPN_TRUSTED_CERT in config.env if connection fails with a cert error."
    fi
  fi

  _vpn_write_config "${vpn_config}" "${_pass}" "${_cert}"
  unset _pass

  success "VPN config written."
  info "On future runs, only your OTP is needed."
}

# --------------------------------------------------------------------------- #
# connect_vpn_in_vm
# Public entry point called from provision.sh.
# Skips silently when VPN_HOST is not set.
# --------------------------------------------------------------------------- #
connect_vpn_in_vm() {
  if [[ -z "${VPN_HOST:-}" ]]; then
    info "VPN_HOST not set in config.env — skipping VPN setup."
    info "Set VPN_HOST, VPN_PORT, and VPN_USERNAME to enable automatic VPN connection."
    return 0
  fi

  banner "FortiVPN"

  # ── Already connected? ───────────────────────────────────────────────── #
  local ppp_up
  ppp_up=$(vm_exec "ip link show ppp0 >/dev/null 2>&1 && echo yes || echo no" 2>/dev/null || echo no)
  if [[ "${ppp_up}" == "yes" ]]; then
    success "VPN already connected (ppp0 interface up)"
    return 0
  fi

  local vpn_config="/home/${VM_USER}/.config/openfortivpn/config"

  # ── First-time setup if no config yet ───────────────────────────────── #
  local has_config
  has_config=$(vm_exec "test -f ${vpn_config} && echo yes || echo no" 2>/dev/null || echo no)

  if [[ "${has_config}" != "yes" ]]; then
    _vpn_first_time_setup "${vpn_config}" || return 1
  fi

  # ── Prompt for OTP ──────────────────────────────────────────────────── #
  echo ""
  echo -e "${_BOLD}  ┌─────────────────────────────────────────────────────────┐${_RESET}"
  echo -e "${_BOLD}  │           FortiVPN — Connect                             │${_RESET}"
  echo -e "${_BOLD}  └─────────────────────────────────────────────────────────┘${_RESET}"
  echo ""
  echo -e "  Host: ${_CYAN}${VPN_HOST}:${VPN_PORT:-10443}${_RESET}   User: ${VPN_USERNAME}"
  echo ""
  local _otp=""
  read -rp "  OTP (from FortiToken / authenticator app): " _otp
  echo ""

  info "Starting VPN tunnel in VM..."

  local connect_rc=0
  vm_exec "
    set -euo pipefail

    # Kill any stale instance
    sudo pkill -f openfortivpn 2>/dev/null || true
    sleep 1

    # Launch in background; stdout/stderr go to log
    sudo nohup openfortivpn \
      --config '${vpn_config}' \
      --otp='${_otp}' \
      > /tmp/openfortivpn.log 2>&1 &
    echo \"openfortivpn PID: \$!\"

    # Poll for ppp0 up to 30 s
    for i in \$(seq 1 15); do
      sleep 2
      if ip link show ppp0 >/dev/null 2>&1; then
        echo 'VPN tunnel up — ppp0 active'
        exit 0
      fi
      printf 'Waiting for VPN tunnel... (%d/15)\n' \"\${i}\"
    done

    echo 'Timed out waiting for VPN tunnel. Log:'
    cat /tmp/openfortivpn.log 2>/dev/null || true
    exit 1
  " 2>&1 | tee -a "${LOG_FILE}" || connect_rc=$?

  unset _otp

  if [[ ${connect_rc} -ne 0 ]]; then
    error "VPN connection failed."
    error "  VM log  : /tmp/openfortivpn.log (inside VM)"
    error "  Config  : ${vpn_config} (inside VM)"
    error "  Manual  : ssh into VM then run:"
    error "    sudo openfortivpn --config ~/.config/openfortivpn/config"
    return 1
  fi

  success "VPN connected to ${VPN_HOST}."
}
