#!/usr/bin/env bash
# =============================================================================
# lib/_verify_inside_vm.sh — Verification checks (runs INSIDE the VM)
#
# Called by lib/verify.sh over vagrant ssh.
# Checks every required tool and prints a structured pass/fail table.
# Exits 1 if any REQUIRED check fails.
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
skip() { echo -e "  ${_YELLOW}–${_RESET}  $* (optional — skipped)"; }

check_cmd() {
  local label="$1" cmd="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    local ver; ver=$("$cmd" --version 2>&1 | head -n1)
    ok "${label}: ${ver}"
  else
    fail "${label} — not found (command: ${cmd})"
  fi
}

check_service() {
  local label="$1" svc="$2"
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    ok "${label} service running"
  else
    fail "${label} service not running (systemctl status ${svc})"
  fi
}

# ---- Source SDKMAN if present (for java/mvn on PATH) ----------------------
if [[ -f "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.sdkman/bin/sdkman-init.sh" 2>/dev/null || true
fi

# ---- Source nvm if present (for node on PATH) ------------------------------
if [[ -f "$HOME/.nvm/nvm.sh" ]]; then
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1090
  source "$NVM_DIR/nvm.sh" 2>/dev/null || true
fi

echo ""
echo -e "${_BOLD}==> Core tools${_RESET}"
check_cmd "Git"       git
check_cmd "Docker"    docker
# Ansible runs on the HOST (not in the VM) — skip inside-VM check.
skip "Ansible (host-side tool — not installed in VM)"
check_cmd "Terraform" terraform
# kubectl uses --client flag for version, not --version
if command -v kubectl >/dev/null 2>&1; then
  ver="$(kubectl version --client --output=json 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('clientVersion',{}).get('gitVersion','unknown'))" \
    2>/dev/null || kubectl version --client 2>&1 | head -n1)"
  ok "kubectl: ${ver}"
else
  fail "kubectl — not found (command: kubectl)"
fi

echo ""
echo -e "${_BOLD}==> Language runtimes${_RESET}"
check_cmd "Node.js"  node
check_cmd "Python 3" python3
check_cmd "Maven"    mvn

echo ""
echo -e "${_BOLD}==> Java (kv-backend critical)${_RESET}"
# Java 8
if update-alternatives --list java 2>/dev/null | grep -q "java-8\|jdk-8\|jdk1.8"; then
  ok "Java 8 available (via update-alternatives)"
elif [[ -d /usr/lib/jvm/java-8-openjdk-amd64 ]] || [[ -d /usr/lib/jvm/java-8-openjdk-arm64 ]]; then
  ok "Java 8 available (OpenJDK 8 installed)"
elif command -v java >/dev/null 2>&1 && java -version 2>&1 | grep -q '"1\.8'; then
  ok "Java 8 is active: $(java -version 2>&1 | head -n1)"
else
  fail "Java 8 — not found (required for kv-backend compatibility)"
fi

# Java 17
if update-alternatives --list java 2>/dev/null | grep -q "java-17\|jdk-17"; then
  ok "Java 17 available (via update-alternatives)"
elif [[ -d /usr/lib/jvm/java-17-openjdk-amd64 ]] || [[ -d /usr/lib/jvm/java-17-openjdk-arm64 ]]; then
  ok "Java 17 available (OpenJDK 17 installed)"
elif command -v java >/dev/null 2>&1 && java -version 2>&1 | grep -q '"17\.'; then
  ok "Java 17 is active: $(java -version 2>&1 | head -n1)"
else
  fail "Java 17 — not found (required for kv-backend compatibility)"
fi

# Default Java version
if command -v java >/dev/null 2>&1; then
  JAVA_VER=$(java -version 2>&1 | head -n1)
  ok "Default Java: ${JAVA_VER}"
  if echo "$JAVA_VER" | grep -qE '"(11|21|22|23)\.'; then
    fail "Default Java is a prohibited version (11/21/22/23). Switch to Java 17: sudo update-alternatives --config java"
  fi
fi

echo ""
echo -e "${_BOLD}==> Tomcat (kv-backend critical)${_RESET}"
if systemctl is-active --quiet tomcat9 2>/dev/null; then
  ok "Tomcat 9 service running"
elif [[ -d /opt/tomcat9 ]]; then
  ok "Tomcat 9 installed at /opt/tomcat9"
elif command -v catalina.sh >/dev/null 2>&1; then
  ok "Tomcat available (catalina.sh found)"
else
  fail "Tomcat 9 — not found (required for kv-backend)"
fi

echo ""
echo -e "${_BOLD}==> Cloud CLIs${_RESET}"
check_cmd "AWS CLI"    aws
check_cmd "Azure CLI"  az
check_cmd "Google Cloud CLI" gcloud

echo ""
echo -e "${_BOLD}==> Docker services${_RESET}"
check_service "Docker" docker
if command -v docker >/dev/null 2>&1; then
  echo ""
  docker ps --format '  container: {{.Names}} — {{.Status}}' 2>/dev/null \
    || echo "  (no containers running — run: make kv-up)"
fi

echo ""
echo "────────────────────────────────────────────"
echo -e "  ${_GREEN}Passed${_RESET}: ${PASS}   ${_RED}Failed${_RESET}: ${FAIL}"
echo "────────────────────────────────────────────"

if [[ ${#FAILURES[@]} -gt 0 ]]; then
  echo ""
  echo -e "${_BOLD}Failed checks:${_RESET}"
  for f in "${FAILURES[@]}"; do
    echo -e "  ${_RED}✘${_RESET}  ${f}"
  done
  echo ""
  echo "Re-run ./provision.sh to attempt repair, or run Ansible manually from the host:"
  echo "  ansible-playbook -i 'ubuntu@<VM_IP>,' --private-key ~/.ssh/dev-env \\"
  echo "    --extra-vars 'dev_user=ubuntu' ansible/playbook.yml"
  exit 1
fi

echo ""
exit 0
