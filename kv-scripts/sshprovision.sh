#!/usr/bin/env bash
# =============================================================================
# kv-scripts/sshprovision.sh — Provision kv-backend services inside the VM
#
# Automates all manual setup steps from the Confluence doc.
#
# Flow:
#   1. Load preload Docker images from tarball
#   2. Start infra containers only (mysql, cassandra, rabbitmq, solr, memcached)
#   3. Apply local config patches (rabbitmq.xml, db-scripts)
#   4. Build WAR files via Maven  ← needs infra containers for db-scripts
#   5. Start portal + sidekiq containers (mounts the now-existing WARs)
#   6. Run database initialization scripts (quick-setup.sh)
#   7. Verify services are running
#
# Error handling:
#   Each step runs independently — a failure is recorded but execution continues.
#   At the end all failed steps are retried once.
#   Only after the retry pass does the script exit non-zero if anything is still broken.
#
# Usage:
#   bash sshprovision.sh [--ci]
# =============================================================================
set -uo pipefail

KV_DIR="${HOME}/workspace/repos/kv-backend"
PRELOAD_DIR="${KV_DIR}/preload-docker-compose"
IMAGE_PATH="${IMAGE_PATH:-${HOME}/dev-environment/assets/preload_kv.tar.gz}"

_info()    { echo "[sshprovision] INFO  $*"; }
_success() { echo "[sshprovision] OK    $*"; }
_warn()    { echo "[sshprovision] WARN  $*"; }
_error()   { echo "[sshprovision] ERROR $*" >&2; }

CI_MODE=false
[[ "${1:-}" == "--ci" ]] && CI_MODE=true

FAILED_STEPS=()

_run_step() {
  local name="$1"
  local func="$2"
  echo ""
  echo "── Step: ${name} ──────────────────────────────────────────"
  if ${func}; then
    _success "${name} completed"
  else
    _error "${name} FAILED — will retry at end of run"
    FAILED_STEPS+=("${name}:${func}")
  fi
}

if [[ ! -d "${KV_DIR}" ]]; then
  _error "kv-backend not found at ${KV_DIR}"
  exit 1
fi
if [[ ! -d "${PRELOAD_DIR}" ]]; then
  _error "preload-docker-compose not found at ${PRELOAD_DIR}"
  exit 1
fi

# --------------------------------------------------------------------------- #
# Step 1: Load preload Docker images from tarball
# --------------------------------------------------------------------------- #
_load_preload_images() {
  if [[ ! -f "${IMAGE_PATH}" ]]; then
    _warn "Preload tarball not found at ${IMAGE_PATH} — Docker will pull images from Hub"
    return 0
  fi

  if ! file "${IMAGE_PATH}" | grep -qE 'gzip|tar archive'; then
    _warn "Tarball at ${IMAGE_PATH} is not valid gzip/tar — skipping image load"
    return 0
  fi

  _info "Loading images from ${IMAGE_PATH} (this may take several minutes ~750MB)..."
  gunzip -c "${IMAGE_PATH}" | docker load
}

# --------------------------------------------------------------------------- #
# Step 2: Start infra containers only (no portal/sidekiq which need WAR files)
# The Maven build's db-scripts phase needs MySQL/Cassandra/RabbitMQ/ Solr
# running, but portal can't start until WARs exist.
# --------------------------------------------------------------------------- #
_start_infra_containers() {
  cd "${PRELOAD_DIR}"

  _info "Starting infra containers (mysql, cassandra, rabbitmq, solr, memcached)..."
  docker compose up -d mysql-8 cassandra rabbitmq solr memcached 2>&1

  # Brief wait for databases to accept connections
  _info "Waiting for MySQL to be ready..."
  local attempt=0
  while [[ ${attempt} -lt 30 ]]; do
    if docker compose exec -T mysql-8 mysql -uroot -proot -e "SELECT 1" >/dev/null 2>&1; then
      _success "MySQL is ready"
      break
    fi
    attempt=$(( attempt + 1 ))
    sleep 2
  done

  _info "Waiting for Cassandra to be ready..."
  attempt=0
  while [[ ${attempt} -lt 30 ]]; do
    if docker compose exec -T cassandra nodetool status >/dev/null 2>&1; then
      _success "Cassandra is ready"
      return 0
    fi
    attempt=$(( attempt + 1 ))
    sleep 2
  done

  _warn "Cassandra did not become ready within 60s — continuing anyway"
  return 0
}

# --------------------------------------------------------------------------- #
# Step 3: Apply local config patches (do not commit these changes)
# --------------------------------------------------------------------------- #
_apply_config_patches() {
  local rc=0

  local rabbitmq_xml="${KV_DIR}/portal/src/main/resources/spring/rabbitmq/rabbitmq.xml"
  if [[ -f "${rabbitmq_xml}" ]]; then
    if grep -q 'addresses="\${rabbitmq.addresses}"' "${rabbitmq_xml}"; then
      sed -i 's/addresses="\${rabbitmq.addresses}"/addresses="${rabbitmq.host}"/g' "${rabbitmq_xml}"
      _success "rabbitmq.xml: patched addresses property"
    else
      _info "rabbitmq.xml: already patched — skipping"
    fi
  else
    _warn "rabbitmq.xml not found at ${rabbitmq_xml}"
  fi

  local db_migration="${KV_DIR}/db-scripts/db-scripts-kv-mysql/src/main/resources/db/migration/V1.0.0.22__location_id_size_update.sql"
  if [[ -f "${db_migration}" ]]; then
    if ! head -1 "${db_migration}" | grep -q "SET FOREIGN_KEY_CHECKS"; then
      sed -i '1i SET FOREIGN_KEY_CHECKS = 0;' "${db_migration}"
      _success "db-scripts: SET FOREIGN_KEY_CHECKS = 0 prepended to migration"
    else
      _info "db-scripts: migration already patched — skipping"
    fi
  else
    _warn "Migration file not found: ${db_migration}"
  fi

  return ${rc}
}

# --------------------------------------------------------------------------- #
# Step 4: Build WAR files via Maven
#
# Infra containers must already be running (db-scripts needs MySQL).
# Portal and sidekiq must NOT be running — they hold a lock on the WAR file
# which prevents mvn clean from deleting it.
# --------------------------------------------------------------------------- #
_build_war_files() {
  if [[ ! -f "${HOME}/.m2/settings.xml" ]]; then
    _warn "~/.m2/settings.xml missing — Nexus artifacts may fail to resolve"
  elif grep -q 'USERNAME\|PASSWORD' "${HOME}/.m2/settings.xml" 2>/dev/null; then
    _error "~/.m2/settings.xml still has placeholder USERNAME/PASSWORD."
    _error "Set NEXUS_USERNAME and NEXUS_PASSWORD in config.env on the host and re-provision."
    return 1
  fi

  cd "${KV_DIR}"

  # Stop portal container if running — it locks the WAR file and blocks mvn clean
  if cd "${PRELOAD_DIR}" 2>/dev/null; then
    if docker compose ps -q portal 2>/dev/null | grep -q .; then
      _info "Stopping portal container to release WAR file lock..."
      docker compose stop portal 2>/dev/null || true
    fi
    cd "${KV_DIR}"
  fi

  # Skip rebuild if WARs exist and are recent (< 1 hour old)
  local portal_war
  portal_war=$(ls "${KV_DIR}/portal/target/"portal-*.war 2>/dev/null | head -1 || true)
  local backend_war
  backend_war=$(ls "${KV_DIR}/kv-backend/target/"kv-backend-*.war 2>/dev/null | head -1 || true)

  if [[ -n "${portal_war}" && -n "${backend_war}" ]]; then
    local age=$(( $(date +%s) - $(stat -c %Y "${portal_war}") ))
    if [[ ${age} -lt 3600 ]]; then
      _success "WAR files already built and recent (${age}s old) — skipping rebuild"
      return 0
    fi
  fi

  _info "Building WAR files (this may take 10-15 minutes on first run)..."
  mvn clean package -T 4 -am -pl portal,kv-backend -Dmaven.test.skip -Denforcer.skip=true
}

# --------------------------------------------------------------------------- #
# Step 5: Start portal + sidekiq (now that WARs exist)
# --------------------------------------------------------------------------- #
_start_app_containers() {
  cd "${PRELOAD_DIR}"

  # Verify WAR files exist before starting portal
  local portal_war
  portal_war=$(ls "${KV_DIR}/portal/target/"portal-*.war 2>/dev/null | head -1 || true)
  local backend_war
  backend_war=$(ls "${KV_DIR}/kv-backend/target/"kv-backend-*.war 2>/dev/null | head -1 || true)

  if [[ -z "${portal_war}" ]]; then
    _error "portal WAR not found — cannot start portal container"
    return 1
  fi
  if [[ -z "${backend_war}" ]]; then
    _error "kv-backend WAR not found — cannot start portal container (BACKEND.war mount)"
    return 1
  fi

  _info "Starting portal + sidekiq containers..."
  docker compose up -d portal sidekiq 2>&1

  _info "Waiting for portal container to come up (up to 150s)..."
  local attempt=0
  while [[ ${attempt} -lt 30 ]]; do
    if docker compose ps 2>/dev/null | grep -E 'portal.*(Up|running)' >/dev/null 2>&1; then
      _success "Portal container is up"
      return 0
    fi
    attempt=$(( attempt + 1 ))
    sleep 5
  done

  _warn "Portal container did not become ready within 150s"
  docker compose ps
  return 1
}

# --------------------------------------------------------------------------- #
# Step 6: Run database initialization (quick-setup.sh)
# Uses 'docker exec' for mysql commands instead of requiring a host mysql client.
# --------------------------------------------------------------------------- #
_run_db_scripts() {
  cd "${PRELOAD_DIR}"

  # Run quick-setup.sh if it exists
  if [[ -f "quick-setup.sh" ]]; then
    _info "Running quick-setup.sh..."
    # quick-setup.sh calls 'mysql' directly which isn't on the host PATH.
    # Wrap it: add a function that routes `mysql` calls through docker exec.
    bash -c '
      mysql() {
        docker exec -i kv_mysql_88 mysql "$@"
      }
      source quick-setup.sh
    ' 2>&1 || _warn "quick-setup.sh had errors — database may already be initialized"
    return 0
  fi

  # Fallback: run the post-scripts directly via docker exec
  local post_dir="${PRELOAD_DIR}/mysql/post-scripts"
  if [[ -d "${post_dir}" ]]; then
    _info "Running MySQL post-scripts via docker exec..."
    for sql_file in "${post_dir}"/*.sql; do
      if [[ -f "${sql_file}" ]]; then
        _info "  $(basename "${sql_file}")"
        docker exec -i kv_mysql_88 mysql -ukv -pkv kv < "${sql_file}" 2>/dev/null || true
      fi
    done
  else
    _warn "No post-scripts directory found — skipping DB initialization"
  fi

  return 0
}

# --------------------------------------------------------------------------- #
# Step 7: Verify services are running
# --------------------------------------------------------------------------- #
_verify_services() {
  cd "${PRELOAD_DIR}"

  echo ""
  _info "Container status:"
  docker compose ps

  local all_ok=true

  _check() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then
      _success "${name} is responding"
    else
      _warn "${name} not yet responding"
      all_ok=false
    fi
  }

  _check "MySQL"     docker compose exec -T mysql-8   mysql -uroot -proot -e "SELECT 1"
  _check "RabbitMQ"  docker compose exec -T rabbitmq  rabbitmq-diagnostics -q ping
  _check "Cassandra" docker compose exec -T cassandra nodetool status
  _check "Solr"      curl -sf http://localhost:58983/solr/admin/cores
  _check "Portal"    curl -sf http://localhost:8080/admin/login.html

  if [[ "${all_ok}" == "true" ]]; then
    _success "All services healthy"
  else
    _warn "Some services not yet responding — they may still be starting up"
    _info "Tail logs: docker compose logs -f"
    return 1
  fi
}

# --------------------------------------------------------------------------- #
# Retry pass
# --------------------------------------------------------------------------- #
_retry_failed() {
  if [[ ${#FAILED_STEPS[@]} -eq 0 ]]; then
    return 0
  fi

  echo ""
  echo "══════════════════════════════════════════════════════════"
  echo "  Retrying ${#FAILED_STEPS[@]} failed step(s)..."
  echo "══════════════════════════════════════════════════════════"

  local still_failed=()
  for entry in "${FAILED_STEPS[@]}"; do
    local name="${entry%%:*}"
    local func="${entry##*:}"
    echo ""
    echo "── Retry: ${name} ─────────────────────────────────────────"
    if ${func}; then
      _success "${name} succeeded on retry"
    else
      _error "${name} failed again"
      still_failed+=("${name}")
    fi
  done

  if [[ ${#still_failed[@]} -gt 0 ]]; then
    echo ""
    _error "The following steps failed after retry:"
    for s in "${still_failed[@]}"; do
      _error "  - ${s}"
    done
    return 1
  fi
}

# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
main() {
  echo ""
  echo "╔════════════════════════════════════════════════════════╗"
  echo "║  kv-backend Local Provisioning                         ║"
  echo "╚════════════════════════════════════════════════════════╝"
  echo ""

  _run_step "Load Docker images"                _load_preload_images
  _run_step "Start infra containers"            _start_infra_containers
  _run_step "Apply config patches"              _apply_config_patches
  _run_step "Build WAR files (Maven)"           _build_war_files
  _run_step "Start app containers (portal)"     _start_app_containers
  _run_step "Database initialization"           _run_db_scripts
  _run_step "Verify services"                   _verify_services

  _retry_failed
  local retry_rc=$?

  echo ""
  if [[ ${retry_rc} -eq 0 && ${#FAILED_STEPS[@]} -eq 0 ]]; then
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║  ✔ Provisioning Complete                               ║"
    echo "╚════════════════════════════════════════════════════════╝"
  else
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║  ⚠  Provisioning finished with errors — see above      ║"
    echo "╚════════════════════════════════════════════════════════╝"
  fi

  echo ""
  echo "  URL:      http://localhost:8080/admin/login.html"
  echo "  Username: system_2"
  echo "  Password: admin"
  echo ""
  echo "  View logs:    docker compose -f ${PRELOAD_DIR}/docker-compose.yml logs -f"
  echo "  Restart:      docker compose -f ${PRELOAD_DIR}/docker-compose.yml restart"
  echo ""

  return ${retry_rc}
}

main
