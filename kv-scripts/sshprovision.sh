#!/usr/bin/env bash
# =============================================================================
# kv-scripts/sshprovision.sh — Provision kv-backend services inside the VM
#
# Automates all manual setup steps from the Confluence doc.
#
# Flow:
#   1. Load preload Docker images from tarball
#   2. Apply local config patches (rabbitmq.xml, db-scripts)
#   3. Build WAR files via Maven  ← MUST happen before docker-compose mounts them
#   4. Start docker-compose services
#   5. Run database initialization scripts (quick-setup.sh)
#   6. Verify services are running
#
# Error handling:
#   Each step runs independently — a failure is recorded but execution continues.
#   At the end all failed steps are retried once.
#   Only after the retry pass does the script exit non-zero if anything is still broken.
#
# Usage:
#   bash sshprovision.sh [--ci]
# =============================================================================
set -uo pipefail   # note: no -e so each step can fail without stopping the script

KV_DIR="${HOME}/workspace/repos/kv-backend"
PRELOAD_DIR="${KV_DIR}/preload-docker-compose"
IMAGE_PATH="${IMAGE_PATH:-${HOME}/dev-environment/assets/preload_kv.tar.gz}"

_info()    { echo "[sshprovision] INFO  $*"; }
_success() { echo "[sshprovision] OK    $*"; }
_warn()    { echo "[sshprovision] WARN  $*"; }
_error()   { echo "[sshprovision] ERROR $*" >&2; }

CI_MODE=false
[[ "${1:-}" == "--ci" ]] && CI_MODE=true

# Track failed step names so we can retry them
FAILED_STEPS=()

# --------------------------------------------------------------------------- #
# _run_step <name> <function>
# Runs a function, records it in FAILED_STEPS if it fails.
# --------------------------------------------------------------------------- #
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

# --------------------------------------------------------------------------- #
# Guard: kv-backend must be cloned
# --------------------------------------------------------------------------- #
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
# Step 2: Apply local config patches (do not commit these changes)
# --------------------------------------------------------------------------- #
_apply_config_patches() {
  local rc=0

  # rabbitmq.xml: addresses="${rabbitmq.addresses}" → addresses="${rabbitmq.host}"
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

  # db-scripts: prepend SET FOREIGN_KEY_CHECKS = 0; to migration file
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
# Step 3: Build WAR files via Maven
#
# Must happen BEFORE docker-compose starts. The compose file mounts WAR paths:
#   kv-backend/target/kv-backend-*.war → /usr/local/tomcat/webapps/BACKEND.war
# If the file doesn't exist docker will fail with "not a directory" error.
# --------------------------------------------------------------------------- #
_build_war_files() {
  # Diagnose common Maven failures before starting
  if [[ ! -f "${HOME}/.m2/settings.xml" ]]; then
    _warn "~/.m2/settings.xml missing — Nexus artifacts may fail to resolve"
  elif grep -q 'USERNAME\|PASSWORD' "${HOME}/.m2/settings.xml" 2>/dev/null; then
    _error "~/.m2/settings.xml still has placeholder USERNAME/PASSWORD."
    _error "Set NEXUS_USERNAME and NEXUS_PASSWORD in config.env on the host and re-provision."
    return 1
  fi

  cd "${KV_DIR}"

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
# Step 4: Start docker-compose services
# --------------------------------------------------------------------------- #
_start_docker_compose() {
  cd "${PRELOAD_DIR}"

  _info "Starting docker-compose services..."
  docker compose up -d

  _info "Waiting for portal container to come up (up to 150s)..."
  local attempt=0
  while [[ ${attempt} -lt 30 ]]; do
    if docker compose ps --format json 2>/dev/null | grep -q '"portal"' || \
       docker compose ps 2>/dev/null | grep -E 'portal.*(Up|running)' >/dev/null 2>&1; then
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
# Step 5: Run database initialization (quick-setup.sh)
# --------------------------------------------------------------------------- #
_run_db_scripts() {
  cd "${PRELOAD_DIR}"

  if [[ ! -f "quick-setup.sh" ]]; then
    _warn "quick-setup.sh not found in ${PRELOAD_DIR} — skipping DB init"
    return 0
  fi

  _info "Running quick-setup.sh..."
  bash quick-setup.sh
}

# --------------------------------------------------------------------------- #
# Step 6: Verify services are running
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

  _check "MySQL"    docker compose exec -T mysql-8   mysql -uroot -proot -e "SELECT 1"
  _check "RabbitMQ" docker compose exec -T rabbitmq  rabbitmq-diagnostics -q ping
  _check "Cassandra" docker compose exec -T cassandra nodetool status
  _check "Solr"     curl -sf http://localhost:58983/solr/admin/cores
  _check "Portal"   curl -sf http://localhost:8080/admin/login.html

  if [[ "${all_ok}" == "true" ]]; then
    _success "All services healthy"
  else
    _warn "Some services not yet responding — they may still be starting up"
    _info "Tail logs: docker compose logs -f"
    return 1
  fi
}

# --------------------------------------------------------------------------- #
# Retry pass — run any failed steps once more
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

  _run_step "Load Docker images"        _load_preload_images
  _run_step "Apply config patches"      _apply_config_patches
  _run_step "Build WAR files (Maven)"   _build_war_files
  _run_step "Start docker-compose"      _start_docker_compose
  _run_step "Database initialization"   _run_db_scripts
  _run_step "Verify services"           _verify_services

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
