#!/usr/bin/env bash
# Entry point: one command to bootstrap a new engineer workstation.
#
#   curl -sSL https://<repo>/setup.sh | bash
#   or, from a clone:
#   ./setup.sh
#
# Detects the OS (macOS or Fedora), then runs each install stage.
# Every stage is idempotent: safe to re-run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

detect_os() {
  if [[ "${OSTYPE:-}" == darwin* ]]; then
    echo "mac"
  elif [[ "${OSTYPE:-}" == linux-gnu* ]] && [[ -f /etc/fedora-release ]]; then
    echo "fedora"
  else
    echo "unsupported"
  fi
}

export OS_FAMILY
OS_FAMILY="$(detect_os)"

if [[ "$OS_FAMILY" == "unsupported" ]]; then
  echo "Error: this script supports macOS and Fedora only. Detected OSTYPE=${OSTYPE:-unknown}." >&2
  exit 1
fi

echo "==> Detected OS family: $OS_FAMILY"

if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
  cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
  echo "==> Created .env from .env.example (edit it to change default credentials)"
fi

if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
  cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
  echo "==> Created .env from .env.example (edit it to change default credentials)"
fi

echo "==> Stage 1/4: core system tools"
"$SCRIPT_DIR/scripts/install-core.sh"

echo "==> Stage 2/4: language runtimes"
"$SCRIPT_DIR/scripts/install-runtimes.sh"

echo "==> Stage 3/4: desktop apps (best-effort, non-blocking)"
"$SCRIPT_DIR/scripts/install-desktop-apps.sh" || echo "warning: some desktop apps may have failed to install, continuing"

echo "==> Stage 4/4: verification"
"$SCRIPT_DIR/scripts/verify.sh"

cat <<'EOF'

==> Host bootstrap complete.

Next steps (manual, see README.md#manual-steps-not-automated):
  - Sign in to work Google account, set up 2FA, share Google Photos.
  - Generate an SSH key: ssh-keygen -C "$(hostname)"
  - Grant screen/audio recording permissions (macOS only).
  - Install FortiToken Mobile on your phone.

For project-local databases/services (MySQL, MongoDB, Cassandra, RabbitMQ,
Neo4j, nginx, Consul), run:
  docker compose up -d

See docs/classification.md and docs/architecture.md for the full rationale.
EOF
