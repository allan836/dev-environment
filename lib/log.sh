#!/usr/bin/env bash
# =============================================================================
# lib/log.sh — Structured logging helpers
#
# Source this file; do not execute it directly.
# Provides: info, success, warn, error, banner, step, die
#
# Usage:
#   source "$(dirname "$0")/lib/log.sh"
# =============================================================================

# Detect whether the terminal supports colour.
if [[ -t 1 ]] && [[ "${NO_COLOR:-}" != "1" ]]; then
  _RED='\033[0;31m'
  _GREEN='\033[0;32m'
  _YELLOW='\033[0;33m'
  _CYAN='\033[0;36m'
  _BOLD='\033[1m'
  _RESET='\033[0m'
else
  _RED='' _GREEN='' _YELLOW='' _CYAN='' _BOLD='' _RESET=''
fi

# info MSG — informational step header
info() {
  echo -e "${_CYAN}==>${_RESET} $*"
}

# success MSG — operation succeeded
success() {
  echo -e "${_GREEN}✔${_RESET}  $*"
}

# warn MSG — non-fatal warning
warn() {
  echo -e "${_YELLOW}⚠${_RESET}   $*"
}

# error MSG — error message (does NOT exit; call die for that)
error() {
  echo -e "${_RED}✘${_RESET}  $*" >&2
}

# banner TITLE — section header
banner() {
  echo ""
  echo -e "${_BOLD}${_CYAN}==> $*${_RESET}"
  echo ""
}

# step N TOTAL MSG — numbered progress step
step() {
  local n="$1" total="$2"; shift 2
  echo -e "${_BOLD}[${n}/${total}]${_RESET} $*"
}

# die MSG [EXIT_CODE] — print error and exit
die() {
  local msg="$1"
  local code="${2:-1}"
  error "$msg"
  exit "$code"
}

# has CMD — returns 0 if command exists on PATH
has() {
  command -v "$1" >/dev/null 2>&1
}

# timeline_item DONE MSG — prints one line of the boot timeline.
# DONE: "true"  → green ✓ (completed)
#       anything else → space (pending)
timeline_item() {
  local done="$1"; shift
  if [[ "${done}" == "true" ]]; then
    echo -e "  [${_GREEN}✓${_RESET}] $*"
  else
    echo -e "  [ ] $*"
  fi
}

# _prompt_reboot REASON
# Tells the user why a reboot is needed, asks to confirm, and either
# reboots (printing resume instructions first) or exits cleanly so the
# user can reboot manually before re-running ./provision.sh.
_prompt_reboot() {
  local reason="${1:-A newly installed component requires a reboot to take effect.}"
  local resume_cmd="cd ${REPO_ROOT:-$(pwd)} && ./provision.sh"

  echo ""
  echo -e "${_YELLOW}${_BOLD}  ⚠  Reboot required${_RESET}"
  echo -e "${_YELLOW}  Reason : ${reason}${_RESET}"
  echo ""
  echo -e "${_BOLD}  After the reboot, resume provisioning with:${_RESET}"
  echo -e "    ${_CYAN}${resume_cmd}${_RESET}"
  echo ""
  read -rp "  Reboot now? [y/N]: " _reboot_answer
  echo ""

  case "${_reboot_answer,,}" in
    y|yes)
      echo -e "${_BOLD}  Rebooting in 5 seconds … (Ctrl-C to cancel)${_RESET}"
      echo -e "  After reboot, run:  ${_CYAN}${resume_cmd}${_RESET}"
      sleep 5
      sudo reboot
      ;;
    *)
      warn "Reboot skipped. Please reboot manually, then run:"
      warn "  ${resume_cmd}"
      exit 0
      ;;
  esac
}
