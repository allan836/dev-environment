#!/usr/bin/env bash
# kv-clean-slate.sh — Wipe and rebuild the local KV dev environment from scratch.
#
# Operates entirely on the kv-backend repo at KV_BACKEND_DIR (set in .env,
# defaults to $HOME/workspace/repos/kv-backend). Never modifies that repo.
#
# Usage (from workstation-bootstrap/):
#   scripts/kv-clean-slate.sh           # wipe + rebuild using bundled seed
#   scripts/kv-clean-slate.sh --remote  # wipe + rebuild pulling seed from DEV_SEED_HOST
#
# Remote seed setup (Uniserver):
#   In workstation-bootstrap/.env set:
#     DEV_SEED_HOST=<host>
#     DEV_SEED_PORT=3306
#     DEV_SEED_USER=<user>
#     DEV_SEED_PASSWORD=<password>
#     DEV_SEED_SCHEMA=kv
#   .env is git-ignored so credentials never reach the remote.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
[[ -f "$ENV_FILE" ]] && set -a && source "$ENV_FILE" && set +a

KV_BACKEND_DIR="${KV_BACKEND_DIR:-$HOME/workspace/repos/kv-backend}"
COMPOSE_DIR="$KV_BACKEND_DIR/preload-docker-compose"
MYSQL_ROOT_PASSWORD=root
MYSQL_LOCAL_PORT=43306
CASSANDRA_LOCAL_PORT=59042

DEV_SEED_HOST="${DEV_SEED_HOST:-}"
DEV_SEED_PORT="${DEV_SEED_PORT:-3306}"
DEV_SEED_USER="${DEV_SEED_USER:-}"
DEV_SEED_PASSWORD="${DEV_SEED_PASSWORD:-}"
DEV_SEED_SCHEMA="${DEV_SEED_SCHEMA:-kv}"

USE_REMOTE=false
[[ "${1:-}" == "--remote" ]] && USE_REMOTE=true

GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; NC="\033[0m"
info()  { echo -e "${GREEN}>>>${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
error() { echo -e "${RED}[error]${NC} $*" >&2; }

require_repo() {
  if [[ ! -d "$COMPOSE_DIR" ]]; then
    error "kv-backend not found at $KV_BACKEND_DIR"
    error "Set KV_BACKEND_DIR in workstation-bootstrap/.env, or clone it first."
    exit 1
  fi
}

wait_for_mysql() {
  info "Waiting for MySQL to accept connections ..."
  local i=0
  until docker exec kv_mysql_88 mysqladmin ping -uroot "-p${MYSQL_ROOT_PASSWORD}" --silent 2>/dev/null; do
    i=$((i + 1))
    if [[ $i -ge 90 ]]; then error "MySQL not ready after 90s"; exit 1; fi
    sleep 1
  done
  info "MySQL is ready"
}

wait_for_cassandra() {
  info "Waiting for Cassandra (:${CASSANDRA_LOCAL_PORT}) ..."
  local i=0
  while ! (exec 3<>/dev/tcp/127.0.0.1/$CASSANDRA_LOCAL_PORT) 2>/dev/null; do
    exec 3<&- 3>&- 2>/dev/null || true
    i=$((i + 1))
    if [[ $i -ge 120 ]]; then error "Cassandra not ready after 120s"; exit 1; fi
    sleep 1
  done
  exec 3<&- 3>&- 2>/dev/null || true
  info "Cassandra is ready"
}

require_repo

echo ""
echo -e "${RED}WARNING:${NC} This will destroy all local KV database data and rebuild from scratch."
echo "Press Ctrl+C within 5 seconds to abort."
sleep 5

# Step 1: tear down
info "Tearing down containers ..."
cd "$COMPOSE_DIR"
docker compose down --remove-orphans 2>&1 || true

info "Removing MySQL and Cassandra volumes ..."
docker volume rm preload-docker-compose_kv_mysql8_data 2>/dev/null \
  && info "  removed kv_mysql8_data" \
  || warn "  kv_mysql8_data not found, skipping"
docker volume rm preload-docker-compose_kv_cassandra_data 2>/dev/null \
  && info "  removed kv_cassandra_data" \
  || warn "  kv_cassandra_data not found, skipping"

# Step 2: start infrastructure only (no portal yet)
info "Starting infrastructure services (mysql, cassandra, rabbitmq, solr, memcached, mailhog) ..."
docker compose up -d mysql-8 cassandra rabbitmq solr memcached mailhog

# Step 3: wait for readiness
wait_for_mysql
wait_for_cassandra

# Step 4: Flyway migrations — creates full schema
info "Running Flyway DB migrations ..."
cd "$KV_BACKEND_DIR"
bash db-scripts.sh
info "Flyway migrations complete"

# Step 5: seed data
cd "$COMPOSE_DIR"
if [[ "$USE_REMOTE" == "true" ]]; then
  if [[ -z "$DEV_SEED_HOST" ]]; then
    error "--remote flag set but DEV_SEED_HOST is not configured in .env"
    exit 1
  fi
  info "Pulling data-only seed from remote MySQL at ${DEV_SEED_HOST}:${DEV_SEED_PORT} ..."
  SEED_DUMP="/tmp/kv_dev_seed_$(date +%Y%m%d%H%M%S).sql"
  mysqldump \
    -h "$DEV_SEED_HOST" \
    -P "$DEV_SEED_PORT" \
    -u "$DEV_SEED_USER" \
    "-p${DEV_SEED_PASSWORD}" \
    --no-create-info \
    --skip-triggers \
    --single-transaction \
    --set-gtid-purged=OFF \
    "$DEV_SEED_SCHEMA" > "$SEED_DUMP"
  info "Importing remote seed into local kv database ..."
  mysql -uroot "-p${MYSQL_ROOT_PASSWORD}" -h 127.0.0.1 -P "$MYSQL_LOCAL_PORT" kv < "$SEED_DUMP"
  rm -f "$SEED_DUMP"
  info "Remote seed import complete"
else
  info "Importing bundled seed (mysql/db-init/02-kv_local.sql) ..."
  mysql -uroot "-p${MYSQL_ROOT_PASSWORD}" -h 127.0.0.1 -P "$MYSQL_LOCAL_PORT" kv \
    < "$COMPOSE_DIR/mysql/db-init/02-kv_local.sql"
  info "Bundled seed import complete"
fi

# Step 6: post-migration SQL scripts
info "Running post-migration SQL scripts ..."
for sql_file in "$COMPOSE_DIR"/mysql/post-scripts/*.sql; do
  info "  $(basename "$sql_file")"
  mysql -uroot "-p${MYSQL_ROOT_PASSWORD}" -h 127.0.0.1 -P "$MYSQL_LOCAL_PORT" kv < "$sql_file"
done

# Step 7: Cassandra init
info "Initialising Cassandra schema ..."
docker exec kv_cassandra bash /docker-entrypoint-initdb.d/cas-init.sh
info "  cas-init done"
docker exec kv_cassandra bash -c "cqlsh -k kv < /docker-entrypoint-initdb.d/cassandra.sql"
info "  cassandra.sql done"
docker exec kv_cassandra bash -c "cqlsh -k kv < /docker-entrypoint-initdb.d/cassandra-test-data.cql"
info "  cassandra-test-data done"
docker exec kv_cassandra nodetool enablethrift
info "  thrift enabled"

# Step 8: start portal
info "Starting portal ..."
docker compose up -d portal
docker compose up -d sidekiq || warn "sidekiq failed to start, continuing"

echo ""
info "Clean-slate rebuild complete."
echo -e "${YELLOW}  Wait ~3 minutes for the portal to fully start.${NC}"
echo "  URL:      http://localhost:8080/portal"
echo "  Username: system_2"
echo "  Password: admin"
echo ""
