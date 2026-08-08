#!/usr/bin/env bash
# =============================================================================
# kv-scripts/sshprovision.sh — Provision kv-backend services inside the VM
#
# Automates all manual steps from the Confluence setup doc.
#
# Sequence (mirrors the Confluence instructions exactly):
#   1.  Load preload Docker images from tarball
#   2.  Start infra containers (mysql, cassandra, rabbitmq, solr, memcached)
#   3.  Enable Cassandra thrift
#   4.  Apply local config patches (rabbitmq.xml, db-scripts migration)
#   5.  npm install --no-save  in client/client-portal
#   6.  mvn clean package      (attempt 1 of 3)
#   7.  docker compose up -d portal sidekiq
#   8.  Unzip ROOT.war / BACKEND.war / WIDGETS.war inside portal container
#   9.  docker compose restart portal
#   10. bash quick-setup.sh   (DB init — run once)
#   11. Verify services
#
# Retry logic:
#   If Maven fails, steps 6-9 are retried up to 3 times total before giving up.
#   All other failures are recorded and retried once at the end.
#
# Usage:
#   bash sshprovision.sh [--ci]
# =============================================================================
set -uo pipefail

KV_DIR="${HOME}/workspace/repos/kv-backend"
PRELOAD_DIR="${KV_DIR}/preload-docker-compose"
IMAGE_PATH="${IMAGE_PATH:-${HOME}/dev-environment/assets/preload_kv.tar.gz}"
MAX_MVN_ATTEMPTS=3

_info()    { echo "[sshprovision] INFO  $*"; }
_success() { echo "[sshprovision] OK    $*"; }
_warn()    { echo "[sshprovision] WARN  $*"; }
_error()   { echo "[sshprovision] ERROR $*" >&2; }

CI_MODE=false
SKIP_VPN=false
for _arg in "$@"; do
  case "${_arg}" in
    --ci)        CI_MODE=true  ;;
    --skip-vpn)  SKIP_VPN=true ;;
  esac
done
unset _arg

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

VPN_CONFIG="${HOME}/.config/openfortivpn/config"

# --------------------------------------------------------------------------- #
# Step 0: FortiVPN connect
#
# Connects to the FortiVPN gateway using openfortivpn so that Docker can pull
# images from the private registry.
#
# First run  — requires password (saved to ${VPN_CONFIG}) + OTP.
# Later runs — password is in saved config; only OTP is prompted.
#
# Skips silently when:
#   - VPN is already connected (ppp0 interface is up), OR
#   - ${VPN_CONFIG} does not exist AND running in --ci mode (non-interactive)
# --------------------------------------------------------------------------- #
_connect_vpn() {
  # --skip-vpn: VPN is managed on the host machine (provision.sh step 2).
  # The VM routes through the host gateway via NAT and inherits VPN routes
  # on ppp0 automatically — no tunnel is needed inside this machine.
  if [[ "${SKIP_VPN:-false}" == "true" ]]; then
    _info "VPN managed on host — skipping in-VM VPN setup (--skip-vpn)"
    return 0
  fi

  # Already connected — nothing to do
  if ip link show ppp0 >/dev/null 2>&1; then
    _success "VPN already connected (ppp0 up)"
    return 0
  fi

  # No config and non-interactive CI mode — warn and skip
  if [[ ! -f "${VPN_CONFIG}" && "${CI_MODE}" == "true" ]]; then
    _warn "VPN not connected and no VPN config found at ${VPN_CONFIG}"
    _warn "Docker pulls from private registries may fail."
    _warn "Run sshprovision.sh interactively once to complete VPN setup:"
    _warn "  cd ${PRELOAD_DIR} && ./sshprovision.sh"
    return 0
  fi

  # No config — first-time interactive setup
  if [[ ! -f "${VPN_CONFIG}" ]]; then
    echo ""
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│           FortiVPN — First-Time Setup                    │"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""
    echo "  Your VPN password will be saved to:"
    echo "  ${VPN_CONFIG}"
    echo "  On subsequent runs, only an OTP is required."
    echo ""

    local _vpn_host _vpn_port _vpn_user _vpn_pass _vpn_cert

    read -rp  "  VPN host (e.g. vpn.company.com): " _vpn_host
    read -rp  "  VPN port [10443]: "                _vpn_port
    _vpn_port="${_vpn_port:-10443}"
    read -rp  "  VPN username: "                    _vpn_user
    read -rsp "  VPN password: "                    _vpn_pass
    echo ""

    # Auto-discover certificate fingerprint
    _info "Discovering VPN server certificate fingerprint..."
    local _raw_cert_output
    _raw_cert_output=$(echo "${_vpn_pass}" \
      | sudo timeout 12 openfortivpn \
          "${_vpn_host}:${_vpn_port}" \
          --username="${_vpn_user}" \
          --password="${_vpn_pass}" \
          2>&1 || true)

    _vpn_cert=$(printf '%s\n' "${_raw_cert_output}" \
      | grep -oP 'sha256:[a-f0-9]+' | head -1 || true)
    if [[ -z "${_vpn_cert}" ]]; then
      _vpn_cert=$(printf '%s\n' "${_raw_cert_output}" \
        | grep -oP '(?<=trusted-cert = )[a-f0-9:]+' | head -1 || true)
    fi

    local _cert_line=""
    if [[ -n "${_vpn_cert}" ]]; then
      echo ""
      echo "  Certificate fingerprint: ${_vpn_cert}"
      read -rp "  Trust this certificate? [Y/n] " _ans
      case "${_ans,,}" in
        n|no)
          _error "VPN setup cancelled."
          unset _vpn_pass
          return 1
          ;;
      esac
      _cert_line="trusted-cert = ${_vpn_cert}"
    else
      _warn "Could not auto-discover certificate fingerprint — omitting from config."
    fi

    mkdir -p "$(dirname "${VPN_CONFIG}")"
    cat > "${VPN_CONFIG}" << EOVPNCFG
host = ${_vpn_host}
port = ${_vpn_port}
username = ${_vpn_user}
password = ${_vpn_pass}
${_cert_line}
EOVPNCFG
    chmod 600 "${VPN_CONFIG}"
    unset _vpn_pass
    _success "VPN config saved to ${VPN_CONFIG}"
    _info "On subsequent runs, only your OTP is required."
  fi

  # Prompt for OTP (always required)
  echo ""
  local _otp=""
  read -rp "  VPN OTP (from FortiToken / authenticator app): " _otp
  echo ""

  _info "Connecting to VPN..."

  # Kill any stale process
  sudo pkill -f openfortivpn 2>/dev/null || true
  sleep 1

  sudo nohup openfortivpn \
    --config "${VPN_CONFIG}" \
    --otp="${_otp}" \
    > /tmp/openfortivpn.log 2>&1 &
  local vpn_pid=$!
  _info "openfortivpn PID: ${vpn_pid}"
  unset _otp

  # Wait up to 30s for ppp0
  local i
  for i in $(seq 1 15); do
    sleep 2
    if ip link show ppp0 >/dev/null 2>&1; then
      _success "VPN tunnel up (ppp0 active)"
      return 0
    fi
    printf '[sshprovision] INFO  Waiting for VPN tunnel... (%d/15)\n' "${i}"
  done

  _error "VPN did not connect within 30s."
  _error "Log: /tmp/openfortivpn.log"
  cat /tmp/openfortivpn.log 2>/dev/null || true
  return 1
}

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
# Step 2: Start infra containers only (portal needs WARs, so it comes later)
# --------------------------------------------------------------------------- #
_start_infra_containers() {
  cd "${PRELOAD_DIR}"

  _info "Starting infra containers (mysql, cassandra, rabbitmq, solr, memcached)..."
  docker compose up -d mysql-8 cassandra rabbitmq solr memcached 2>&1

  _info "Waiting for MySQL to be ready (up to 60s)..."
  local attempt=0
  while [[ ${attempt} -lt 30 ]]; do
    if docker compose exec -T mysql-8 mysql -uroot -proot -e "SELECT 1" >/dev/null 2>&1; then
      _success "MySQL is ready"
      break
    fi
    attempt=$(( attempt + 1 ))
    sleep 2
  done
  [[ ${attempt} -eq 30 ]] && _warn "MySQL did not become ready within 60s — continuing"

  _info "Waiting for Cassandra to be ready (up to 60s)..."
  attempt=0
  while [[ ${attempt} -lt 30 ]]; do
    if docker compose exec -T cassandra nodetool status >/dev/null 2>&1; then
      _success "Cassandra is ready"
      return 0
    fi
    attempt=$(( attempt + 1 ))
    sleep 2
  done
  _warn "Cassandra did not become ready within 60s — continuing"
  return 0
}

# --------------------------------------------------------------------------- #
# Step 3: Enable Cassandra thrift (required by kv-backend)
# --------------------------------------------------------------------------- #
_enable_cassandra_thrift() {
  _info "Enabling Cassandra thrift..."
  if docker exec kv_cassandra nodetool enablethrift >/dev/null 2>&1; then
    _success "Cassandra thrift enabled"
  else
    _warn "nodetool enablethrift failed — Cassandra may not be ready yet or thrift already enabled"
  fi
  return 0
}

# --------------------------------------------------------------------------- #
# Step 4: Apply local config patches (do not commit these changes)
# --------------------------------------------------------------------------- #
_apply_config_patches() {
  # rabbitmq.xml patch 1 — line 17: addresses="${rabbitmq.addresses}" → addresses="${rabbitmq.host}"
  local rabbitmq_xml="${KV_DIR}/portal/src/main/resources/spring/rabbitmq/rabbitmq.xml"
  if [[ -f "${rabbitmq_xml}" ]]; then
    if grep -q 'addresses="\${rabbitmq.addresses}"' "${rabbitmq_xml}"; then
      sed -i 's/addresses="\${rabbitmq.addresses}"/addresses="${rabbitmq.host}"/g' "${rabbitmq_xml}"
      _success "rabbitmq.xml: patched addresses property (line 17)"
    else
      _info "rabbitmq.xml: addresses property already patched — skipping"
    fi

    # rabbitmq.xml patch 2 — line 41: rabbitmq.admin.addresses → rabbitmq.host
    if grep -q 'rabbitmq\.admin\.addresses' "${rabbitmq_xml}"; then
      sed -i 's/\${rabbitmq\.admin\.addresses}/${rabbitmq.host}/g' "${rabbitmq_xml}"
      _success "rabbitmq.xml: patched admin.addresses property (line 41)"
    else
      _info "rabbitmq.xml: admin.addresses property already patched — skipping"
    fi
  else
    _warn "rabbitmq.xml not found at ${rabbitmq_xml}"
  fi

  # db-scripts: prepend SET FOREIGN_KEY_CHECKS = 0
  local db_migration="${KV_DIR}/db-scripts/db-scripts-kv-mysql/src/main/resources/db/migration/V1.0.0.22__location_id_size_update.sql"
  if [[ -f "${db_migration}" ]]; then
    if ! head -1 "${db_migration}" | grep -q "SET FOREIGN_KEY_CHECKS"; then
      sed -i '1i SET FOREIGN_KEY_CHECKS = 0;' "${db_migration}"
      _success "db-scripts: migration patched"
    else
      _info "db-scripts: migration already patched — skipping"
    fi
  else
    _warn "Migration file not found: ${db_migration}"
  fi

  # docker-compose.yml: remove WAR file bind-mounts for portal
  # WHY: Docker cannot bind-mount a host FILE to a container path that does
  # not already exist as a file. When the destination path is absent, Docker
  # creates a directory there, then fails with "not a directory". We remove
  # those mounts here and copy the WARs in via docker cp after the container
  # starts (see _unzip_wars_in_portal).
  local compose_yml="${PRELOAD_DIR}/docker-compose.yml"
  if [[ -f "${compose_yml}" ]]; then
    if grep -q '\.war:' "${compose_yml}" 2>/dev/null; then
      # Comment out lines that bind-mount .war files (lines like: - /path/to/foo.war:/dest.war)
      sed -i 's|^\(\s*-\s.*\.war:.*\)$|      # WAR_MOUNT_REMOVED \1|' "${compose_yml}"
      _success "docker-compose.yml: WAR bind-mounts commented out (will use docker cp instead)"
    else
      _info "docker-compose.yml: no WAR bind-mounts found — skipping"
    fi
  else
    _warn "docker-compose.yml not found at ${compose_yml}"
  fi

  return 0
}

# --------------------------------------------------------------------------- #
# Step 5a: Enforce Java 17 for the Maven build
# The system may default to Java 8 (both are installed). Maven requires 17.
# Exports JAVA_HOME and prepends Java 17's bin to PATH for this session only.
# --------------------------------------------------------------------------- #
_enforce_java_17() {
  local current_version
  current_version=$(java -version 2>&1 | awk -F '"' '/version/{print $2}' | cut -d'.' -f1)
  _info "Current default Java version: ${current_version}"

  # Find Java 17 home — try common locations
  local java17_home=""
  for candidate in \
      /usr/lib/jvm/java-17-openjdk-amd64 \
      /usr/lib/jvm/java-17-openjdk \
      /usr/lib/jvm/temurin-17 \
      /usr/lib/jvm/java-17; do
    if [[ -x "${candidate}/bin/java" ]]; then
      java17_home="${candidate}"
      break
    fi
  done

  # Also try update-alternatives to locate java 17
  if [[ -z "${java17_home}" ]]; then
    local alt
    alt=$(update-alternatives --list java 2>/dev/null | grep -E 'java-17|17-openjdk' | head -1 || true)
    if [[ -n "${alt}" ]]; then
      java17_home="${alt%/bin/java}"
    fi
  fi

  if [[ -z "${java17_home}" ]]; then
    _error "Java 17 not found on this system. Install it with: sudo apt install openjdk-17-jdk"
    return 1
  fi

  _info "Java 17 found at: ${java17_home}"

  if [[ "${current_version}" == "17" ]]; then
    _success "Java 17 is already the default — no switch needed"
    export JAVA_HOME="${java17_home}"
    return 0
  fi

  _info "Switching to Java 17 for this build session (was Java ${current_version})..."
  export JAVA_HOME="${java17_home}"
  export PATH="${java17_home}/bin:${PATH}"

  local new_version
  new_version=$(java -version 2>&1 | awk -F '"' '/version/{print $2}' | cut -d'.' -f1)
  if [[ "${new_version}" == "17" ]]; then
    _success "Java 17 active for build (JAVA_HOME=${java17_home})"
  else
    _error "Failed to switch to Java 17 — still on Java ${new_version}"
    return 1
  fi
}

# --------------------------------------------------------------------------- #
# Step 5b: npm install in client/client-portal (must be before Maven)
# --------------------------------------------------------------------------- #
_npm_install_client_portal() {
  local client_dir="${KV_DIR}/client/client-portal"
  if [[ ! -d "${client_dir}" ]]; then
    _warn "client/client-portal not found — skipping npm install"
    return 0
  fi
  _info "Running npm install --no-save in client/client-portal..."
  cd "${client_dir}"
  npm install --no-save
  cd "${KV_DIR}"
  _success "npm install complete"
}

# --------------------------------------------------------------------------- #
# Step 6: Maven build — up to MAX_MVN_ATTEMPTS attempts
# Returns 0 if either WAR was built (even partially), 1 if nothing was built.
# --------------------------------------------------------------------------- #
_build_war_files() {
  if [[ ! -f "${HOME}/.m2/settings.xml" ]]; then
    _warn "~/.m2/settings.xml missing — Nexus artifacts may fail to resolve"
  elif grep -q 'USERNAME\|PASSWORD' "${HOME}/.m2/settings.xml" 2>/dev/null; then
    _error "~/.m2/settings.xml still has placeholder credentials."
    _error "Set NEXUS_USERNAME and NEXUS_PASSWORD in config.env and re-provision."
    return 1
  fi

  cd "${KV_DIR}"

  # Stop portal if running — it locks the WAR file and blocks mvn clean
  if [[ -d "${PRELOAD_DIR}" ]]; then
    if docker compose -f "${PRELOAD_DIR}/docker-compose.yml" ps -q portal 2>/dev/null | grep -q .; then
      _info "Stopping portal container to release WAR file lock..."
      docker compose -f "${PRELOAD_DIR}/docker-compose.yml" stop portal 2>/dev/null || true
    fi
  fi

  # Final Java version check before invoking Maven
  local java_ver
  java_ver=$(java -version 2>&1 | awk -F '"' '/version/{print $2}' | cut -d'.' -f1)
  if [[ "${java_ver}" != "17" ]]; then
    _error "Maven requires Java 17 but active version is Java ${java_ver}. Run 'Enforce Java 17' step first."
    return 1
  fi
  _info "Java ${java_ver} confirmed — proceeding with Maven build"

  local attempt=0
  local mvn_rc=1

  while [[ ${attempt} -lt ${MAX_MVN_ATTEMPTS} ]]; do
    attempt=$(( attempt + 1 ))
    _info "Maven build attempt ${attempt}/${MAX_MVN_ATTEMPTS}..."

    if mvn clean package -T 4 -am -pl portal,kv-backend \
        -Dmaven.test.skip -Denforcer.skip=true; then
      _success "Maven build succeeded on attempt ${attempt}"
      mvn_rc=0
      break
    else
      _warn "Maven build attempt ${attempt} failed"
      if [[ ${attempt} -lt ${MAX_MVN_ATTEMPTS} ]]; then
        _info "Retrying Maven build (attempt $((attempt+1))/${MAX_MVN_ATTEMPTS})..."
        sleep 5
      fi
    fi
  done

  # Check if at least one WAR was produced — a partial build is still useful
  local portal_war
  portal_war=$(ls "${KV_DIR}/portal/target/"portal-*.war 2>/dev/null | head -1 || true)
  local backend_war
  backend_war=$(ls "${KV_DIR}/kv-backend/target/"kv-backend-*.war 2>/dev/null | head -1 || true)

  if [[ -z "${portal_war}" && -z "${backend_war}" ]]; then
    _error "No WAR files produced after ${MAX_MVN_ATTEMPTS} attempts"
    return 1
  fi

  [[ -z "${portal_war}" ]]  && _warn "portal WAR not built — portal container may fail"
  [[ -z "${backend_war}" ]] && _warn "kv-backend WAR not built — BACKEND.war mount will fail"

  # Return 0 even on partial build so downstream steps (docker-compose, unzip) can proceed
  return 0
}

# --------------------------------------------------------------------------- #
# Step 6b: Free port 8080 — stop the Tomcat 9 systemd service if it is
# running.  Ansible installs Tomcat 9 as a system service for standalone use,
# but the portal runs inside the kv_portal Docker container which also binds
# port 8080.  Leaving both up causes "address already in use" on docker up.
# --------------------------------------------------------------------------- #
_free_port_8080() {
  if systemctl is-active --quiet tomcat9 2>/dev/null; then
    _info "Stopping system Tomcat 9 to free port 8080 for kv_portal container..."
    sudo systemctl stop tomcat9
    sudo systemctl disable tomcat9
    _success "Tomcat 9 stopped and disabled — port 8080 is now free."
  elif ss -tlnp 2>/dev/null | grep -q ':8080 '; then
    _warn "Port 8080 is in use by an unknown process:"
    ss -tlnp | grep ':8080 ' || true
    _warn "kv_portal may fail to bind — check what is holding port 8080."
  else
    _info "Port 8080 is free."
  fi
}

# Step 7: Start portal + sidekiq containers
# --------------------------------------------------------------------------- #
_start_app_containers() {
  cd "${PRELOAD_DIR}"

  _info "Starting portal + sidekiq containers..."
  docker compose up -d portal sidekiq 2>&1 || true

  _info "Waiting for portal container to come up (up to 90s)..."
  local attempt=0
  while [[ ${attempt} -lt 18 ]]; do
    if docker compose ps 2>/dev/null | grep -E 'portal.*(Up|running)' >/dev/null 2>&1; then
      _success "Portal container is up"
      return 0
    fi
    attempt=$(( attempt + 1 ))
    sleep 5
  done

  _warn "Portal container did not become ready within 90s"
  docker compose ps
  return 1
}

# --------------------------------------------------------------------------- #
# Step 8: Unzip WARs inside the portal container
# ROOT.war, BACKEND.war, WIDGETS.war — matches Confluence instructions exactly
# --------------------------------------------------------------------------- #
_unzip_wars_in_portal() {
  _info "Installing unzip inside portal container..."
  docker exec kv_portal bash -c "apt-get update -qq && apt-get install -y unzip -qq" >/dev/null 2>&1 || \
    docker exec kv_portal bash -c "which unzip" >/dev/null 2>&1 || \
    _warn "Could not install unzip — it may already be present"

  # Copy WARs into the container via docker cp (bind-mounts were removed in
  # _apply_config_patches to avoid the "not a directory" Docker mount error).
  local portal_war
  portal_war=$(ls "${KV_DIR}/portal/target/"portal-*.war 2>/dev/null | head -1 || true)
  local backend_war
  backend_war=$(ls "${KV_DIR}/kv-backend/target/"kv-backend-*.war 2>/dev/null | head -1 || true)

  if [[ -n "${portal_war}" ]]; then
    _info "Copying $(basename "${portal_war}") → portal:/usr/local/tomcat/webapps/ROOT.war"
    docker cp "${portal_war}" kv_portal:/usr/local/tomcat/webapps/ROOT.war
    _success "ROOT.war copied"
  else
    _warn "portal WAR not found — ROOT.war will be missing"
  fi

  if [[ -n "${backend_war}" ]]; then
    _info "Copying $(basename "${backend_war}") → portal:/usr/local/tomcat/webapps/BACKEND.war"
    docker cp "${backend_war}" kv_portal:/usr/local/tomcat/webapps/BACKEND.war
    _success "BACKEND.war copied"
  else
    _warn "kv-backend WAR not found — BACKEND.war will be missing"
  fi

  _info "Unzipping ROOT.war inside portal container..."
  docker exec kv_portal bash -c "
    cd /usr/local/tomcat/webapps
    if [[ -f ROOT.war ]]; then
      mkdir -p ROOT
      unzip -o ROOT.war -d ROOT 2>&1 | tail -1
      echo 'ROOT.war extracted'
    else
      echo 'ROOT.war not found — skipping'
    fi
  "

  _info "Unzipping BACKEND.war inside portal container..."
  docker exec kv_portal bash -c "
    cd /usr/local/tomcat/webapps
    if [[ -f BACKEND.war ]]; then
      mkdir -p BACKEND
      unzip -o BACKEND.war -d BACKEND 2>&1 | tail -1
      echo 'BACKEND.war extracted'
    else
      echo 'BACKEND.war not found — skipping'
    fi
  "

  _info "Unzipping WIDGETS.war inside portal container..."
  docker compose -f "${PRELOAD_DIR}/docker-compose.yml" exec -w /usr/local/widget-tomcat/webapps/ portal \
    unzip -o WIDGETS.war -d WIDGETS 2>/dev/null && _success "WIDGETS.war extracted" || \
    _warn "WIDGETS.war not found or could not be extracted — skipping"

  _success "WAR extraction complete"
}

# --------------------------------------------------------------------------- #
# Step 9: Restart portal after unzip so Tomcat picks up the new classes
# --------------------------------------------------------------------------- #
_restart_portal() {
  cd "${PRELOAD_DIR}"
  _info "Restarting portal container..."
  docker compose restart portal 2>&1
  _success "Portal restarted"
}

# --------------------------------------------------------------------------- #
# Step 9b: Post-deploy Maven build
# After Tomcat is running with the unzipped WARs, run Maven again to ensure
# any classes that Tomcat loaded on startup are now in sync with a clean build.
# Uses the same retry logic as the initial build (up to MAX_MVN_ATTEMPTS).
# Skips if the portal has not started (no point building if Tomcat is down).
# --------------------------------------------------------------------------- #
_post_deploy_build() {
  # Verify Java 17 still active (PATH export from _enforce_java_17 persists
  # within the same shell session, but confirm before running Maven again)
  local java_ver
  java_ver=$(java -version 2>&1 | awk -F '"' '/version/{print $2}' | cut -d'.' -f1)
  if [[ "${java_ver}" != "17" ]]; then
    _warn "Java ${java_ver} active — re-enforcing Java 17 for post-deploy build"
    _enforce_java_17 || return 1
  fi

  cd "${KV_DIR}"

  # Stop portal to release WAR lock before mvn clean
  _info "Stopping portal container before post-deploy Maven build..."
  docker compose -f "${PRELOAD_DIR}/docker-compose.yml" stop portal 2>/dev/null || true

  local attempt=0
  while [[ ${attempt} -lt ${MAX_MVN_ATTEMPTS} ]]; do
    attempt=$(( attempt + 1 ))
    _info "Post-deploy Maven build attempt ${attempt}/${MAX_MVN_ATTEMPTS}..."

    if mvn clean package -T 4 -am -pl portal,kv-backend \
        -Dmaven.test.skip -Denforcer.skip=true; then
      _success "Post-deploy Maven build succeeded on attempt ${attempt}"

      # Bring portal back up with the freshly built WARs
      _info "Restarting portal with updated WARs..."
      cd "${PRELOAD_DIR}"
      docker compose up -d portal 2>&1 || true

      # Re-unzip so Tomcat picks up the new classes immediately
      _unzip_wars_in_portal
      docker compose restart portal 2>&1 || true
      _success "Portal updated with post-deploy build"
      return 0
    else
      _warn "Post-deploy Maven build attempt ${attempt} failed"
      if [[ ${attempt} -lt ${MAX_MVN_ATTEMPTS} ]]; then
        _info "Retrying (attempt $((attempt+1))/${MAX_MVN_ATTEMPTS})..."
        sleep 5
      fi
    fi
  done

  # Even if Maven failed, bring portal back up with whatever WARs exist
  _warn "Post-deploy Maven build did not succeed — restarting portal with previous WARs"
  cd "${PRELOAD_DIR}"
  docker compose up -d portal 2>&1 || true
  return 1
}

# --------------------------------------------------------------------------- #
# Step 9c: Run alter scripts (MySQL, Cassandra, Solr)
#
# Must run AFTER infra containers are up and BEFORE the Maven/Tomcat build.
# Synchronises the local database state with the latest schema changes.
#
# Searches kv-backend for an alterscript/ folder containing subdirs:
#   mysql/    — .sql files executed via docker exec into kv_mysql_88
#   cassandra/ — .cql files executed via docker exec into kv_cassandra
#   solr/     — .json/.xml config files posted to Solr HTTP API
#
# Scripts are run in filename order (alphabetical = version order).
# Already-applied scripts are skipped based on a tracking table in MySQL
# and a tracking file for Cassandra/Solr.
# --------------------------------------------------------------------------- #
_run_alter_scripts() {
  # Locate the alterscript directory — try common locations
  local alter_dir=""
  for candidate in \
      "${KV_DIR}/alterscript" \
      "${KV_DIR}/alter-scripts" \
      "${KV_DIR}/alter_scripts" \
      "${KV_DIR}/alterscripts" \
      "${KV_DIR}/db-scripts/alterscript" \
      "${KV_DIR}/db-scripts/alter-scripts" \
      "${PRELOAD_DIR}/alterscript" \
      "${PRELOAD_DIR}/alter-scripts"; do
    if [[ -d "${candidate}" ]]; then
      alter_dir="${candidate}"
      break
    fi
  done

  if [[ -z "${alter_dir}" ]]; then
    # Try a broader search under kv-backend
    alter_dir=$(find "${KV_DIR}" -maxdepth 3 -type d \
      \( -iname 'alterscript' -o -iname 'alter-scripts' -o -iname 'alterscripts' \) \
      2>/dev/null | head -1 || true)
  fi

  if [[ -z "${alter_dir}" ]]; then
    _warn "No alterscript directory found under ${KV_DIR} — skipping alter scripts"
    return 0
  fi

  _info "Alter scripts directory: ${alter_dir}"

  # Tracking table in MySQL to avoid re-running applied scripts
  docker exec -i kv_mysql_88 mysql -uroot -proot kv 2>/dev/null << 'TRACK_SQL'
CREATE TABLE IF NOT EXISTS _local_alter_applied (
  script_name VARCHAR(255) NOT NULL PRIMARY KEY,
  applied_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
TRACK_SQL

  # Cassandra / Solr tracking file (on the host side, persists across runs)
  local track_file="${KV_DIR}/.alterscript_applied"
  touch "${track_file}" 2>/dev/null || true

  local total=0 skipped=0 applied=0 failed=0

  # ── MySQL alter scripts ──────────────────────────────────────────────────
  local mysql_dir="${alter_dir}/mysql"
  if [[ -d "${mysql_dir}" ]]; then
    _info "Running MySQL alter scripts from ${mysql_dir}..."
    while IFS= read -r -d '' sql_file; do
      local script_name
      script_name=$(basename "${sql_file}")
      total=$(( total + 1 ))

      # Check tracking table
      local already_applied
      already_applied=$(docker exec -i kv_mysql_88 \
        mysql -uroot -proot kv -sNe \
        "SELECT COUNT(*) FROM _local_alter_applied WHERE script_name='${script_name}';" \
        2>/dev/null || echo "0")

      if [[ "${already_applied}" -gt 0 ]]; then
        _info "  [skip] ${script_name} (already applied)"
        skipped=$(( skipped + 1 ))
        continue
      fi

      _info "  [run]  ${script_name}"
      if docker exec -i kv_mysql_88 mysql -uroot -proot kv < "${sql_file}" 2>&1; then
        docker exec -i kv_mysql_88 mysql -uroot -proot kv -e \
          "INSERT IGNORE INTO _local_alter_applied (script_name) VALUES ('${script_name}');" \
          >/dev/null 2>&1
        _success "  [ok]   ${script_name}"
        applied=$(( applied + 1 ))
      else
        _warn "  [fail] ${script_name} — continuing with next script"
        failed=$(( failed + 1 ))
      fi
    done < <(find "${mysql_dir}" -maxdepth 2 -name '*.sql' -print0 | sort -z)
  else
    _info "No mysql/ subdir in ${alter_dir} — skipping MySQL alter scripts"
  fi

  # ── Cassandra alter scripts ──────────────────────────────────────────────
  local cassandra_dir="${alter_dir}/cassandra"
  if [[ -d "${cassandra_dir}" ]]; then
    _info "Running Cassandra alter scripts from ${cassandra_dir}..."
    while IFS= read -r -d '' cql_file; do
      local script_name
      script_name=$(basename "${cql_file}")
      total=$(( total + 1 ))

      if grep -qxF "${script_name}" "${track_file}" 2>/dev/null; then
        _info "  [skip] ${script_name} (already applied)"
        skipped=$(( skipped + 1 ))
        continue
      fi

      _info "  [run]  ${script_name}"
      if docker exec -i kv_cassandra cqlsh < "${cql_file}" 2>&1; then
        echo "${script_name}" >> "${track_file}"
        _success "  [ok]   ${script_name}"
        applied=$(( applied + 1 ))
      else
        _warn "  [fail] ${script_name} — continuing with next script"
        failed=$(( failed + 1 ))
      fi
    done < <(find "${cassandra_dir}" -maxdepth 2 -name '*.cql' -print0 | sort -z)
  else
    _info "No cassandra/ subdir in ${alter_dir} — skipping Cassandra alter scripts"
  fi

  # ── Solr alter scripts ───────────────────────────────────────────────────
  local solr_dir="${alter_dir}/solr"
  if [[ -d "${solr_dir}" ]]; then
    _info "Running Solr alter scripts from ${solr_dir}..."
    local solr_url="http://localhost:58983/solr"

    while IFS= read -r -d '' solr_file; do
      local script_name
      script_name=$(basename "${solr_file}")
      total=$(( total + 1 ))

      if grep -qxF "${script_name}" "${track_file}" 2>/dev/null; then
        _info "  [skip] ${script_name} (already applied)"
        skipped=$(( skipped + 1 ))
        continue
      fi

      _info "  [run]  ${script_name}"
      local ext="${solr_file##*.}"
      local post_rc=0

      case "${ext}" in
        json)
          curl -sf -X POST "${solr_url}/admin/configs" \
            -H "Content-Type: application/json" \
            --data-binary "@${solr_file}" >/dev/null 2>&1 || post_rc=$?
          ;;
        xml)
          curl -sf -X POST "${solr_url}/admin/cores" \
            -H "Content-Type: application/xml" \
            --data-binary "@${solr_file}" >/dev/null 2>&1 || post_rc=$?
          ;;
        *)
          _warn "  [skip] ${script_name} — unknown extension .${ext}"
          skipped=$(( skipped + 1 ))
          continue
          ;;
      esac

      if [[ ${post_rc} -eq 0 ]]; then
        echo "${script_name}" >> "${track_file}"
        _success "  [ok]   ${script_name}"
        applied=$(( applied + 1 ))
      else
        _warn "  [fail] ${script_name} — continuing with next script"
        failed=$(( failed + 1 ))
      fi
    done < <(find "${solr_dir}" -maxdepth 2 \( -name '*.json' -o -name '*.xml' \) -print0 | sort -z)
  else
    _info "No solr/ subdir in ${alter_dir} — skipping Solr alter scripts"
  fi

  echo ""
  _info "Alter scripts summary: total=${total} applied=${applied} skipped=${skipped} failed=${failed}"
  [[ ${failed} -gt 0 ]] && return 1 || return 0
}

# --------------------------------------------------------------------------- #
# Step 10a: Verify MySQL has the 'kv' database and schema
# Returns 0 if kv DB is healthy, 1 if init is needed.
# --------------------------------------------------------------------------- #
_mysql_kv_db_healthy() {
  # Check if schema_version table exists (created by Flyway during init)
  docker exec -i kv_mysql_88 \
    mysql -uroot -proot kv -e "SELECT 1 FROM schema_version LIMIT 1;" >/dev/null 2>&1
}

# --------------------------------------------------------------------------- #
# Step 10b: MySQL troubleshoot recovery
# Implements both options from the Confluence troubleshooting section:
#   Option 1: docker exec → bash 00-mysql-init.sh inside container
#   Option 2: docker compose down + volume rm + docker compose up (last resort)
# --------------------------------------------------------------------------- #
_recover_mysql() {
  _warn "MySQL 'kv' database not initialised — running recovery..."

  # Option 1: exec into container and run the init script directly
  _info "MySQL recovery Option 1: running 00-mysql-init.sh inside container..."
  if docker exec kv_mysql_88 bash -c "
    cd /docker-entrypoint-initdb.d/ && \
    bash 00-mysql-init.sh 2>&1
  "; then
    _success "00-mysql-init.sh completed"

    # Optional SQL imports if init script alone isn't enough
    for sql_file in 01-create-database.sql 02-kv_local.sql; do
      local sql_path="/docker-entrypoint-initdb.d/${sql_file}"
      if docker exec kv_mysql_88 bash -c "[[ -f '${sql_path}' ]]" 2>/dev/null; then
        _info "Importing ${sql_file}..."
        docker exec kv_mysql_88 bash -c \
          "mysql -uroot -proot kv < ${sql_path}" 2>&1 || \
          _warn "${sql_file} import had errors — may already be applied"
      fi
    done

    # Verify recovery worked
    if _mysql_kv_db_healthy; then
      _success "MySQL recovery Option 1 succeeded — 'kv' database is ready"
      return 0
    fi
    _warn "Option 1 complete but 'kv' database still not healthy"
  else
    _warn "00-mysql-init.sh failed — escalating to Option 2"
  fi

  # Option 2: destroy volume and recreate (last resort — DELETES local data)
  _warn "MySQL recovery Option 2: destroying volume and recreating mysql-8..."
  _warn "⚠  THIS WILL DELETE ALL LOCAL MYSQL DATA ⚠"
  cd "${PRELOAD_DIR}"
  docker compose down mysql-8 2>&1 || true
  docker volume rm preload-docker-compose_kv_mysql8_data 2>&1 || \
    _warn "Volume not found or already removed"
  docker compose up -d mysql-8 2>&1

  _info "Waiting for MySQL to reinitialise (up to 90s)..."
  local attempt=0
  while [[ ${attempt} -lt 45 ]]; do
    if _mysql_kv_db_healthy; then
      _success "MySQL recovery Option 2 succeeded — 'kv' database is ready"
      return 0
    fi
    attempt=$(( attempt + 1 ))
    sleep 2
  done

  _error "MySQL recovery failed after both options — manual intervention required"
  _error "Check logs: docker compose logs mysql-8"
  return 1
}

# --------------------------------------------------------------------------- #
# Step 10: Database initialization via quick-setup.sh
# Runs mysql commands through docker exec so no host mysql client needed.
# If 'kv' DB is missing or schema_version is absent, triggers recovery first.
# --------------------------------------------------------------------------- #
_run_db_scripts() {
  cd "${PRELOAD_DIR}"

  # Check if kv DB already initialised — skip if healthy to avoid re-running
  if _mysql_kv_db_healthy; then
    _info "MySQL 'kv' database already initialised — skipping DB init"
    return 0
  fi

  # Attempt recovery if DB is not ready
  _recover_mysql || return 1

  if [[ -f "quick-setup.sh" ]]; then
    _info "Running quick-setup.sh (DB init — run once)..."
    mysql() { docker exec -i kv_mysql_88 mysql "$@"; }
    export -f mysql
    bash quick-setup.sh 2>&1 || _warn "quick-setup.sh had errors — DB may already be initialized"
    unset -f mysql
    return 0
  fi

  # Fallback: run post-scripts directly via docker exec
  local post_dir="${PRELOAD_DIR}/mysql/post-scripts"
  if [[ -d "${post_dir}" ]]; then
    _info "Running MySQL post-scripts via docker exec..."
    for sql_file in "${post_dir}"/*.sql; do
      [[ -f "${sql_file}" ]] || continue
      _info "  $(basename "${sql_file}")"
      docker exec -i kv_mysql_88 mysql -ukv -pkv kv < "${sql_file}" 2>/dev/null || true
    done
  else
    _warn "quick-setup.sh and post-scripts not found — skipping DB init"
  fi

  return 0
}

# --------------------------------------------------------------------------- #
# Step 11: Verify all services are responding
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
    _warn "Some services not yet responding — they may still be starting"
    _info "Tail logs: docker compose logs -f"
    return 1
  fi
}

# --------------------------------------------------------------------------- #
# Retry pass — re-run any failed non-Maven steps once
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
  return 0
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

  _run_step "Connect VPN"                  _connect_vpn
  _run_step "Load Docker images"           _load_preload_images
  _run_step "Start infra containers"       _start_infra_containers
  _run_step "Enable Cassandra thrift"      _enable_cassandra_thrift
  _run_step "Apply config patches"         _apply_config_patches
  _run_step "Run alter scripts"            _run_alter_scripts
  _run_step "Enforce Java 17"              _enforce_java_17
  _run_step "npm install (client-portal)"  _npm_install_client_portal

  # Maven + docker-compose + unzip run as a unit.
  # Maven is retried up to 3 times internally; docker-compose and unzip
  # proceed regardless of Maven result as long as any WAR exists.
  _run_step "Build WAR files (Maven)"      _build_war_files
  _run_step "Free port 8080 (stop Tomcat)" _free_port_8080
  _run_step "Start app containers"         _start_app_containers
  _run_step "Unzip WARs in portal"         _unzip_wars_in_portal
  _run_step "Restart portal"               _restart_portal
  _run_step "Post-deploy Maven build"      _post_deploy_build

  _run_step "Database initialization"      _run_db_scripts
  _run_step "Verify services"              _verify_services

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
