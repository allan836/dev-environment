#!/usr/bin/env bash
# =============================================================================
# verify.sh — Verify all required tools are installed
#
# Checks every tool and prints a structured pass/fail summary.
# Never blocks the overall bootstrap on a single missing optional tool.
# Exits 1 if any REQUIRED tool is missing.
# =============================================================================
set -uo pipefail

PASS=0
FAIL=0
FAILURES=()

_GREEN='\033[0;32m'
_RED='\033[0;31m'
_YELLOW='\033[0;33m'
_BOLD='\033[1m'
_RESET='\033[0m'

ok()   { echo -e "  ${_GREEN}✔${_RESET}  $*"; PASS=$(( PASS + 1 )); }
fail() { echo -e "  ${_RED}✘${_RESET}  $*"; FAIL=$(( FAIL + 1 )); FAILURES+=("$*"); }
skip() { echo -e "  ${_YELLOW}–${_RESET}  $* (optional)"; }

check_cmd() {
  local label="$1" cmd="$2" required="${3:-true}"
  if command -v "$cmd" >/dev/null 2>&1; then
    local ver; ver=$("$cmd" --version 2>&1 | head -n1)
    ok "${label}: ${ver}"
  else
    if [[ "$required" == "true" ]]; then
      fail "${label} — not found (command: ${cmd})"
    else
      skip "${label}"
    fi
  fi
}

# Source version managers if present
if [[ -f "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.sdkman/bin/sdkman-init.sh" 2>/dev/null || true
fi
if [[ -f "$HOME/.nvm/nvm.sh" ]]; then
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1090
  source "$NVM_DIR/nvm.sh" 2>/dev/null || true
fi
if [[ -d "$HOME/.pyenv/bin" ]]; then
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)" 2>/dev/null || true
fi

echo ""
echo -e "${_BOLD}==> Core tools${_RESET}"
check_cmd "Git"       git
check_cmd "Docker"    docker
check_cmd "GitHub CLI" gh  "false"
check_cmd "Terraform" terraform
check_cmd "kubectl"   kubectl

echo ""
echo -e "${_BOLD}==> Cloud CLIs${_RESET}"
check_cmd "AWS CLI"      aws   "false"
check_cmd "Azure CLI"    az    "false"
check_cmd "Google Cloud" gcloud "false"

echo ""
echo -e "${_BOLD}==> Language runtimes${_RESET}"
check_cmd "Node.js"   node
check_cmd "pnpm"      pnpm "false"
check_cmd "Python 3"  python3
check_cmd "pip"       pip3 "false"
check_cmd "uv"        uv   "false"
check_cmd "Maven"     mvn

echo ""
echo -e "${_BOLD}==> Java (kv-backend CRITICAL — must have 8 AND 17)${_RESET}"

# Check Java 8
JAVA8_FOUND=false
if update-alternatives --list java 2>/dev/null | grep -qE "java-8|jdk1\.8|jdk-8"; then
  ok "Java 8 available (update-alternatives)"
  JAVA8_FOUND=true
elif [[ -d /usr/lib/jvm/java-8-openjdk-amd64 ]] || [[ -d /usr/lib/jvm/java-8-openjdk-arm64 ]]; then
  ok "Java 8 available (OpenJDK 8 directory exists)"
  JAVA8_FOUND=true
elif has sdk && sdk list java 2>/dev/null | grep -q "8.*installed"; then
  ok "Java 8 available (SDKMAN)"
  JAVA8_FOUND=true
fi
if ! $JAVA8_FOUND; then
  fail "Java 8 — not found (required for kv-backend compatibility)"
fi

# Check Java 17
JAVA17_FOUND=false
if update-alternatives --list java 2>/dev/null | grep -qE "java-17|jdk-17"; then
  ok "Java 17 available (update-alternatives)"
  JAVA17_FOUND=true
elif [[ -d /usr/lib/jvm/java-17-openjdk-amd64 ]] || [[ -d /usr/lib/jvm/java-17-openjdk-arm64 ]]; then
  ok "Java 17 available (OpenJDK 17 directory exists)"
  JAVA17_FOUND=true
elif has sdk && sdk list java 2>/dev/null | grep -q "17.*installed"; then
  ok "Java 17 available (SDKMAN)"
  JAVA17_FOUND=true
fi
if ! $JAVA17_FOUND; then
  fail "Java 17 — not found (required for kv-backend compatibility)"
fi

# Check default Java
if has java; then
  JAVA_VER=$(java -version 2>&1 | head -n1)
  ok "Default Java: ${JAVA_VER}"
  if echo "$JAVA_VER" | grep -qE '"(11|21|22|23)\.'; then
    fail "Default Java is a prohibited version (${JAVA_VER}). Switch: sudo update-alternatives --config java"
  fi
fi

echo ""
echo -e "${_BOLD}==> Tomcat (kv-backend CRITICAL)${_RESET}"
TOMCAT_FOUND=false
if systemctl is-active --quiet tomcat9 2>/dev/null; then
  ok "Tomcat 9 service running"
  TOMCAT_FOUND=true
elif [[ -d /opt/tomcat9 && -f /opt/tomcat9/bin/catalina.sh ]]; then
  ok "Tomcat 9 installed at /opt/tomcat9"
  TOMCAT_FOUND=true
elif [[ -d /opt/tomcat && -f /opt/tomcat/bin/catalina.sh ]]; then
  ok "Tomcat installed at /opt/tomcat"
  TOMCAT_FOUND=true
fi
if ! $TOMCAT_FOUND; then
  fail "Tomcat 9 — not found (required for kv-backend)"
fi

echo ""
echo -e "${_BOLD}==> Docker services${_RESET}"
if has docker && docker info &>/dev/null; then
  ok "Docker daemon is running"
  echo ""
  docker ps --format '  container: {{.Names}} — {{.Status}}' 2>/dev/null \
    || echo "  (no containers running — run: make kv-up)"
else
  fail "Docker daemon is not running (try: sudo systemctl start docker)"
fi

echo ""
echo "──────────────────────────────────────────────"
echo -e "  ${_GREEN}Passed${_RESET}: ${PASS}   ${_RED}Failed${_RESET}: ${FAIL}"
echo "──────────────────────────────────────────────"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
  echo ""
  echo -e "${_BOLD}Failed checks:${_RESET}"
  for f in "${FAILURES[@]}"; do
    echo -e "  ${_RED}✘${_RESET}  ${f}"
  done
  echo ""
  echo "Run the relevant install script to repair, or re-run ./setup.sh"
  exit 1
fi

echo ""
echo -e "${_GREEN}${_BOLD}All checks passed. Environment is ready.${_RESET}"
echo ""

# kv-backend services (best-effort, non-blocking)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "$SCRIPT_DIR/kv-backend.sh" ]]; then
  echo -e "${_BOLD}==> kv-backend services${_RESET}"
  "$SCRIPT_DIR/kv-backend.sh" verify || true
fi
