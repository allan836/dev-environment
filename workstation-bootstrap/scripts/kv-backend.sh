#!/usr/bin/env bash
# Drives kv-backend's OWN local dev environment
# (<kv-backend>/preload-docker-compose) from the workstation-bootstrap repo.
#
# This script never modifies anything inside the kv-backend repo. It only
# `cd`s into it and calls commands/scripts that already exist there
# (docker compose, mvn, quick-setup.sh).
#
# Usage:
#   scripts/kv-backend.sh load-images  # docker load the preload images (auto-run by 'up' if missing)
#   scripts/kv-backend.sh up           # load images (if needed) + build WARs (if needed) + docker compose up -d
#   scripts/kv-backend.sh init         # first-time only: run kv-backend's quick-setup.sh
#   scripts/kv-backend.sh verify       # check containers + ports are reachable
#   scripts/kv-backend.sh down         # docker compose down
#   scripts/kv-backend.sh status       # docker compose ps
#
# Configure the kv-backend clone location via KV_BACKEND_DIR (see .env /
# .env.example). Defaults to $HOME/workspace/repos/kv-backend.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
[[ -f "$ENV_FILE" ]] && set -a && source "$ENV_FILE" && set +a

KV_BACKEND_DIR="${KV_BACKEND_DIR:-$HOME/workspace/repos/kv-backend}"
COMPOSE_DIR="$KV_BACKEND_DIR/preload-docker-compose"
PRELOAD_TAR="${KV_PRELOAD_TAR:-$REPO_ROOT/assets/preload_kv.tar.gz}"
PRELOAD_IMAGES=(kv_rabbitmq:preload_v1 kv_cassandra:preload_v1 kv_portal:preload_v1)

has() { command -v "$1" >/dev/null 2>&1; }

require_repo() {
  if [[ ! -d "$COMPOSE_DIR" ]]; then
    echo "Error: kv-backend not found at $KV_BACKEND_DIR" >&2
    echo "Set KV_BACKEND_DIR in workstation-bootstrap/.env, or clone it:" >&2
    echo "  git clone <kv-backend-repo-url> $KV_BACKEND_DIR" >&2
    exit 1
  fi
}

images_missing() {
  local img
  for img in "${PRELOAD_IMAGES[@]}"; do
    docker image inspect "$img" >/dev/null 2>&1 || return 0
  done
  return 1
}

cmd_load_images() {
  if ! images_missing; then
    echo "==> Preload images already loaded, skipping."
    return 0
  fi
  if [[ ! -f "$PRELOAD_TAR" ]]; then
    echo "Error: preload tarball not found at $PRELOAD_TAR" >&2
    echo "Place the downloaded tarball at assets/preload_kv.tar.gz (or set KV_PRELOAD_TAR)." >&2
    exit 1
  fi
  echo "==> Loading preload images from $PRELOAD_TAR (this can take several minutes, ~750MB)"
  # Validate the tarball before attempting to load.
  if ! file "$PRELOAD_TAR" | grep -qE 'gzip|tar archive'; then
    echo "Error: $PRELOAD_TAR is not a valid tar/gzip file." >&2
    echo "       Run: file $PRELOAD_TAR   to inspect, and re-download if it is an HTML page." >&2
    exit 1
  fi
  if file "$PRELOAD_TAR" | grep -q 'gzip'; then
    gunzip -c "$PRELOAD_TAR" | docker load
  else
    docker load -i "$PRELOAD_TAR"
  fi
  if images_missing; then
    echo "Error: docker load completed but expected images are still missing:" >&2
    for img in "${PRELOAD_IMAGES[@]}"; do
      docker image inspect "$img" >/dev/null 2>&1 || echo "  [MISSING] $img" >&2
    done
    exit 1
  fi
  echo "==> Preload images loaded: ${PRELOAD_IMAGES[*]}"
}

require_preload_images() {
  if images_missing; then
    cmd_load_images
  fi
}

build_wars() {
  echo "==> Building kv-backend WAR files (mvn package install)"
  if ! has mvn; then
    echo "Error: mvn not found. Run ./setup.sh first to install runtimes." >&2
    exit 1
  fi
  (cd "$KV_BACKEND_DIR" && mvn package install -DskipTests=true -Denforcer.skip=true)
}

cmd_up() {
  require_repo
  require_preload_images
  if ! ls "$KV_BACKEND_DIR"/portal/target/portal-*.war >/dev/null 2>&1; then
    build_wars
  else
    echo "==> WAR files already built, skipping mvn build (delete portal/target to force a rebuild)"
  fi
  echo "==> docker compose up -d (from $COMPOSE_DIR)"
  (cd "$COMPOSE_DIR" && docker compose up -d)
  cat <<EOF

==> kv-backend services starting. First boot can take several minutes.
    Run 'scripts/kv-backend.sh status' or 'scripts/kv-backend.sh verify' to check.
    If this is the FIRST time standing this up, also run:
      scripts/kv-backend.sh init
EOF
}

cmd_init() {
  require_repo
  echo "==> Running kv-backend's own quick-setup.sh (DB/Cassandra/Solr init)"
  echo "    This is destructive to existing local data — first-time setup only."
  (cd "$COMPOSE_DIR" && bash quick-setup.sh)
}

cmd_down() {
  require_repo
  (cd "$COMPOSE_DIR" && docker compose down)
}

cmd_status() {
  require_repo
  (cd "$COMPOSE_DIR" && docker compose ps)
}

check_port() {
  local name="$1" host="$2" port="$3"
  if (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null; then
    exec 3<&- 3>&-
    printf "  [ok] %-10s %s:%s\n" "$name" "$host" "$port"
  else
    printf "  [MISSING] %-10s %s:%s\n" "$name" "$host" "$port"
  fi
}

cmd_verify() {
  echo "==> kv-backend service reachability"
  check_port mysql     127.0.0.1 43306
  check_port rabbitmq   127.0.0.1 35672
  check_port rabbitmq-ui 127.0.0.1 45672
  check_port cassandra  127.0.0.1 59042
  check_port solr       127.0.0.1 58983
  check_port memcached  127.0.0.1 41211
  check_port portal     127.0.0.1 8080
  echo ""
  echo "Portal (once up): http://localhost:8080/portal  (username: system_2, password: admin)"
}

case "${1:-}" in
  load-images) cmd_load_images ;;
  up)          cmd_up ;;
  init)        cmd_init ;;
  down)        cmd_down ;;
  status)      cmd_status ;;
  verify)      cmd_verify ;;
  *)
    echo "Usage: $0 {load-images|up|init|down|status|verify}" >&2
    exit 1
    ;;
esac
