#!/usr/bin/env bash
# Verifies core tooling is installed and prints versions.
# Never fails the whole bootstrap on a single missing tool; reports gaps.
set -uo pipefail

check() {
  local name="$1" cmd="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf "  [ok] %-12s %s\n" "$name" "$("$cmd" --version 2>&1 | head -n1)"
  else
    printf "  [MISSING] %-12s\n" "$name"
  fi
}

echo "==> Core tools"
check git git
check docker docker
check gh gh
check terraform terraform
check aws aws
check kubectl kubectl
check code code

echo "==> Runtimes"
check node node
check pnpm pnpm
check python3 python3
check pipenv pipenv
check uv uv
check java java
check mvn mvn

echo "Verification complete. Re-run individual install scripts under scripts/ for anything marked MISSING."
echo ""
echo "==> kv-backend services (run 'make kv-up' first if these are all MISSING)"
"$(dirname "${BASH_SOURCE[0]}")/kv-backend.sh" verify
