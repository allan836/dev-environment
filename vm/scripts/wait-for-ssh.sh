#!/usr/bin/env bash
# wait-for-ssh.sh — Poll until a host:port accepts TCP connections.
#
# USAGE:
#   ./wait-for-ssh.sh HOST PORT [MAX_WAIT_SECONDS]
#
# Used by provision.sh when NOT using Vagrant (raw VBoxManage path).
# Vagrant's own SSH readiness check covers the Vagrant path.
set -euo pipefail

HOST="${1:?HOST required}"
PORT="${2:?PORT required}"
MAX_WAIT="${3:-300}"   # 5 minutes default

has_nc()  { command -v nc      >/dev/null 2>&1; }
has_ncat(){ command -v ncat    >/dev/null 2>&1; }
has_bash_tcp() { (echo "" > /dev/tcp/localhost/1) 2>/dev/null; }

tcp_check() {
  if has_nc; then
    nc -z -w2 "$HOST" "$PORT" 2>/dev/null
  elif has_ncat; then
    ncat -z -w2 "$HOST" "$PORT" 2>/dev/null
  else
    # Pure bash TCP fallback
    (echo "" > /dev/tcp/"$HOST"/"$PORT") 2>/dev/null
  fi
}

echo "Waiting for $HOST:$PORT to accept connections (timeout: ${MAX_WAIT}s)..."
elapsed=0
while ! tcp_check; do
  if [[ $elapsed -ge $MAX_WAIT ]]; then
    echo "Timeout: $HOST:$PORT did not open within ${MAX_WAIT}s." >&2
    exit 1
  fi
  printf "."
  sleep 5
  elapsed=$(( elapsed + 5 ))
done

echo ""
echo "OK: $HOST:$PORT is accepting connections."
