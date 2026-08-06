#!/usr/bin/env bash
# =============================================================================
# kv-scripts/sshprovision.sh — Provision kv-backend services inside the VM
#
# Automates all manual setup steps from the Confluence doc:
# https://confluence.dtg.nl/display/KV/KV-Backend+Local+Dockerized+Setup
#
# Flow:
#   1. Load preload Docker images from tarball
#   2. Apply local config patches (rabbitmq.xml, db-scripts)
#   3. Build WAR files via Maven (CRITICAL: before docker-compose mounts them)
#   4. Start docker-compose services
#   5. Run database initialization scripts
#   6. Verify services are running
#
# Usage:
#   bash sshprovision.sh [--ci]
#
# --ci flag: non-interactive mode (used by provision.sh)
# =============================================================================
set -euo pipefail

KV_DIR="${HOME}/workspace/repos/kv-backend"
PRELOAD_DIR="${KV_DIR}/preload-docker-compose"
IMAGE_PATH="${IMAGE_PATH:-${HOME}/dev-environment/assets/preload_kv.tar.gz}"

_info()    { echo "[sshprovision] INFO  $*"; }
_success() { echo "[sshprovision] OK    $*"; }
_warn()    { echo "[sshprovision] WARN  $*"; }
_die()     { echo "[sshprovision] ERROR $*" >&2; exit 1; }

CI_MODE=false
[[ "${1:-}" == "--ci" ]] && CI_MODE=true

# --------------------------------------------------------------------------- #
# Guard: kv-backend must be cloned
# --------------------------------------------------------------------------- #
if [[ ! -d "${KV_DIR}" ]]; then
  _die "kv-backend not found at ${KV_DIR}"
fi

if [[ ! -d "${PRELOAD_DIR}" ]]; then
  _die "preload-docker-compose not found at ${PRELOAD_DIR}"
fi

# --------------------------------------------------------------------------- #
# 1. Load preload Docker images from tarball
# --------------------------------------------------------------------------- #
_load_preload_images() {
  _info "Loading preload Docker images..."

  if [[ ! -f "${IMAGE_PATH}" ]]; then
    _warn "Preload tarball not found at ${IMAGE_PATH}"
    _warn "Docker images will be pulled from Hub on first docker-compose up"
    return 0
  fi

  if ! file "${IMAGE_PATH}" | grep -qE 'gzip|tar archive'; then
    _warn "Preload tarball is not a valid gzip/tar file: ${IMAGE_PATH}"
    return 0
  fi

  _info "Loading images from ${IMAGE_PATH} (this may take several minutes)..."
  if gunzip -c "${IMAGE_PATH}" | docker load; then
    _success "Preload images loaded"
  else
    _warn "Failed to load preload images — docker-compose will pull from Hub"
  fi
}

# --------------------------------------------------------------------------- #
# 2. Apply local config patches
# --------------------------------------------------------------------------- #
_apply_config_patches() {
  _info "Applying local config patches..."

  # Patch: rabbitmq.xml — change addresses from ${rabbitmq.addresses} to ${rabbitmq.host}
  local rabbitmq_xml="${KV_DIR}/portal/src/main/resources/spring/rabbitmq/rabbitmq.xml"
  if [[ -f "${rabbitmq_xml}" ]]; then
    if grep -q 'addresses="\${rabbitmq.addresses}"' "${rabbitmq_xml}"; then
      sed -i 's/addresses="\${rabbitmq.addresses}"/addresses="${rabbitmq.host}"/g' "${rabbitmq_xml}"
      _success "rabbitmq.xml patched"
    fi
  fi

  # Patch: db-scripts — add SET FOREIGN_KEY_CHECKS = 0 to migration file
  local db_migration="${KV_DIR}/db-scripts/db-scripts-kv-mysql/src/main/resources/db/migration/V1.0.0.22__location_id_size_update.sql"
  if [[ -f "${db_migration}" ]]; then
    if ! head -1 "${db_migration}" | grep -q "SET FOREIGN_KEY_CHECKS"; then
      sed -i '1i SET FOREIGN_KEY_CHECKS = 0;' "${db_migration}"
      _success "db-scripts migration patched"
    fi
  fi
}

# --------------------------------------------------------------------------- #
# 3. Build WAR files via Maven
#
# CRITICAL: This MUST happen BEFORE docker-compose tries to mount them.
# The docker-compose.yml has volume mounts like:
#   - ${KV_BACKEND_DIR}/kv-backend/target/kv-backend-*.war:/usr/local/tomcat/webapps/BACKEND.war
# If the WAR doesn't exist, docker-compose will fail with:
#   "not a directory: Are you trying to mount a directory onto a file?"
# --------------------------------------------------------------------------- #
_build_war_files() {
  _info "Building WAR files via Maven..."
  _info "(This may take 10-15 minutes on first run)"

  cd "${KV_DIR}"

  # Check if WARs already exist and are recent (less than 1 hour old)
  local portal_war="${KV_DIR}/portal/target/portal-*.war"
  local backend_war="${KV_DIR}/kv-backend/target/kv-backend-*.war"

  if ls ${portal_war} >/dev/null 2>&1 && ls ${backend_war} >/dev/null 2>&1; then
    local portal_age=$(($(date +%s) - $(stat -c %Y ${portal_war} 2>/dev/null | head -1)))
    if [[ ${portal_age} -lt 3600 ]]; then
      _success "WAR files already built and recent — skipping rebuild"
      return 0
    fi
  fi

  # Build with parallel compilation and skip tests
  if mvn clean package -T 4 -am -pl portal,kv-backend -Dmaven.test.skip -Denforcer.skip=true; then
    _success "WAR files built successfully"
  else
    _die "Maven build failed — check logs above"
  fi
}

# --------------------------------------------------------------------------- #
# 4. Start docker-compose services
# --------------------------------------------------------------------------- #
_start_docker_compose() {
  _info "Starting docker-compose services..."

  cd "${PRELOAD_DIR}"

  if docker compose up -d; then
    _success "docker-compose services started"
  else
    _die "docker-compose up failed"
  fi

  # Wait for services to be ready
  _info "Waiting for services to be ready (this may take 1-2 minutes)..."
  sleep 10

  local max_attempts=30
  local attempt=0
  while [[ ${attempt} -lt ${max_attempts} ]]; do
    if docker compose ps | grep -q "portal.*Up"; then
      _success "Services are ready"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 5
  done

  _warn "Services did not become ready within timeout — continuing anyway"
}

# --------------------------------------------------------------------------- #
# 5. Run database initialization scripts
# --------------------------------------------------------------------------- #
_run_db_scripts() {
  _info "Running database initialization scripts..."

  cd "${PRELOAD_DIR}"

  # Run quick-setup.sh if it exists
  if [[ -f "quick-setup.sh" ]]; then
    _info "Running quick-setup.sh..."
    if bash quick-setup.sh; then
      _success "quick-setup.sh completed"
    else
      _warn "quick-setup.sh failed — database may not be fully initialized"
    fi
  else
    _warn "quick-setup.sh not found — skipping database initialization"
  fi
}

# --------------------------------------------------------------------------- #
# 6. Verify services are running
# --------------------------------------------------------------------------- #
_verify_services() {
  _info "Verifying services..."

  cd "${PRELOAD_DIR}"

  echo ""
  _info "Docker Compose Status:"
  docker compose ps

  echo ""
  _info "Service Health Check:"

  local services_ok=true

  # Check MySQL
  if docker compose exec -T mysql-8 mysql -uroot -proot -e "SELECT 1" >/dev/null 2>&1; then
    _success "MySQL is responding"
  else
    _warn "MySQL is not responding yet"
    services_ok=false
  fi

  # Check RabbitMQ
  if docker compose exec -T rabbitmq rabbitmq-diagnostics -q ping >/dev/null 2>&1; then
    _success "RabbitMQ is responding"
  else
    _warn "RabbitMQ is not responding yet"
    services_ok=false
  fi

  # Check Cassandra
  if docker compose exec -T cassandra nodetool status >/dev/null 2>&1; then
    _success "Cassandra is responding"
  else
    _warn "Cassandra is not responding yet"
    services_ok=false
  fi

  # Check Solr
  if curl -s http://localhost:58983/solr/admin/cores >/dev/null 2>&1; then
    _success "Solr is responding"
  else
    _warn "Solr is not responding yet"
    services_ok=false
  fi

  # Check Portal (Tomcat)
  if curl -s http://localhost:8080/admin/login.html >/dev/null 2>&1; then
    _success "Portal (Tomcat) is responding"
  else
    _warn "Portal (Tomcat) is not responding yet — it may still be starting up"
    services_ok=false
  fi

  echo ""
  if [[ "${services_ok}" == "true" ]]; then
    _success "All services are healthy"
  else
    _warn "Some services are not yet responding — they may still be starting up"
    _info "Check logs with: docker compose logs -f"
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

  _load_preload_images
  _apply_config_patches
  _build_war_files
  _start_docker_compose
  _run_db_scripts
  _verify_services

  echo ""
  echo "╔════════════════════════════════════════════════════════╗"
  echo "║  ✔ Provisioning Complete                              ║"
  echo "╚════════════════════════════════════════════════════════╝"
  echo ""
  echo "Access the application:"
  echo "  URL:      http://localhost:8080/admin/login.html"
  echo "  Username: system_2"
  echo "  Password: admin"
  echo ""
  echo "View logs:"
  echo "  docker compose logs -f"
  echo ""
  echo "Restart services:"
  echo "  docker compose restart"
  echo ""
}

main
