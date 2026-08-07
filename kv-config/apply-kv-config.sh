#!/usr/bin/env bash
# =============================================================================
# kv-config/apply-kv-config.sh — Drop local-dev config files into kv-backend
#
# Run INSIDE the VM after kv-backend has been cloned.
# Copies config files from ~/dev-environment/kv-config/ to the right places
# inside ~/workspace/repos/kv-backend/ so the build and Tomcat run correctly
# without any manual steps.
#
# Files placed:
#   hazelcast.xml         → portal/src/main/resources/
#                         → kv-backend/src/main/resources/  (if module exists)
#   mail.properties       → portal/src/main/resources/
#   HazelCastClusterManager.java
#                         → portal/src/main/java/nl/dtg/kv/task/distributed/impl/
#   portal.configuration.properties
#                         → portal/src/main/resources/configuration.properties
#   backend.configuration.properties
#                         → kv-backend/src/main/resources/configuration.properties
#
# Additionally:
#   - Injects the xalan serializer dependency into portal/pom.xml and
#     kv-backend/pom.xml if not already present.
#   - Creates upload and data directories referenced by configuration.properties.
# =============================================================================
set -euo pipefail

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KV_DIR="${HOME}/workspace/repos/kv-backend"

_info()    { echo "[apply-kv-config] INFO  $*"; }
_success() { echo "[apply-kv-config] OK    $*"; }
_warn()    { echo "[apply-kv-config] WARN  $*"; }
_die()     { echo "[apply-kv-config] ERROR $*" >&2; exit 1; }

# --------------------------------------------------------------------------- #
# Guard: kv-backend must be cloned first
# --------------------------------------------------------------------------- #
if [[ ! -d "${KV_DIR}" ]]; then
  _die "kv-backend not found at ${KV_DIR}. Run clone_kv_backend() first."
fi

# --------------------------------------------------------------------------- #
# 0. Write ~/.m2/settings.xml with Nexus credentials
# --------------------------------------------------------------------------- #
NEXUS_USER="${NEXUS_USERNAME:-}"
NEXUS_PASS="${NEXUS_PASSWORD:-}"

if [[ -z "${NEXUS_USER}" || -z "${NEXUS_PASS}" ]]; then
  _warn "NEXUS_USERNAME or NEXUS_PASSWORD not set — Maven build will fail with 401."
  _warn "Add them to config.env on the host and re-run provision.sh."
else
  mkdir -p "${HOME}/.m2"
  cat > "${HOME}/.m2/settings.xml" <<EOF
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0
                              https://maven.apache.org/xsd/settings-1.0.0.xsd">
  <servers>
    <server>
      <id>kv-repo</id>
      <username>${NEXUS_USER}</username>
      <password>${NEXUS_PASS}</password>
    </server>
  </servers>
  <profiles>
    <profile>
      <id>custom-profile</id>
      <repositories>
        <repository>
          <id>kv-repo</id>
          <url>https://nexus.cicd.nextgen-kiyoh.com/repository/kv-old-super-group</url>
          <releases><enabled>true</enabled></releases>
          <snapshots><enabled>true</enabled></snapshots>
        </repository>
        <repository>
          <id>central</id>
          <url>https://repo.maven.apache.org/maven2</url>
          <releases><enabled>true</enabled></releases>
          <snapshots><enabled>false</enabled></snapshots>
        </repository>
      </repositories>
    </profile>
  </profiles>
  <activeProfiles>
    <activeProfile>custom-profile</activeProfile>
  </activeProfiles>
</settings>
EOF
  _success "~/.m2/settings.xml written with Nexus credentials"
fi

# --------------------------------------------------------------------------- #
# 1. hazelcast.xml — portal resources
# --------------------------------------------------------------------------- #
PORTAL_RES="${KV_DIR}/portal/src/main/resources"
if [[ -d "${PORTAL_RES}" ]]; then
  cp "${CONFIG_DIR}/hazelcast.xml" "${PORTAL_RES}/hazelcast.xml"
  _success "hazelcast.xml → portal/src/main/resources/"
else
  _warn "portal/src/main/resources/ not found — skipping hazelcast.xml for portal"
fi

# hazelcast.xml — kv-backend module resources (if the module exists)
BACKEND_RES="${KV_DIR}/kv-backend/src/main/resources"
if [[ -d "${BACKEND_RES}" ]]; then
  cp "${CONFIG_DIR}/hazelcast.xml" "${BACKEND_RES}/hazelcast.xml"
  _success "hazelcast.xml → kv-backend/src/main/resources/"
fi

# --------------------------------------------------------------------------- #
# 2. mail.properties — portal resources
# --------------------------------------------------------------------------- #
if [[ -d "${PORTAL_RES}" ]]; then
  cp "${CONFIG_DIR}/mail.properties" "${PORTAL_RES}/mail.properties"
  _success "mail.properties → portal/src/main/resources/"
else
  _warn "portal/src/main/resources/ not found — skipping mail.properties"
fi

# --------------------------------------------------------------------------- #
# 3. HazelCastClusterManager.java — portal source
# --------------------------------------------------------------------------- #
HAZELCAST_PKG="${KV_DIR}/portal/src/main/java/nl/dtg/kv/task/distributed/impl"
if [[ -d "${HAZELCAST_PKG}" ]]; then
  cp "${CONFIG_DIR}/HazelCastClusterManager.java" \
     "${HAZELCAST_PKG}/HazelCastClusterManager.java"
  _success "HazelCastClusterManager.java → portal/.../distributed/impl/"
else
  _warn "Package path ${HAZELCAST_PKG} not found — skipping HazelCastClusterManager.java"
fi

# --------------------------------------------------------------------------- #
# 4. portal configuration.properties
# --------------------------------------------------------------------------- #
if [[ -d "${PORTAL_RES}" ]]; then
  cp "${CONFIG_DIR}/portal.configuration.properties" \
     "${PORTAL_RES}/configuration.properties"
  _success "portal.configuration.properties → portal/src/main/resources/configuration.properties"
else
  _warn "portal/src/main/resources/ not found — skipping portal configuration.properties"
fi

# --------------------------------------------------------------------------- #
# 5. backend configuration.properties
# --------------------------------------------------------------------------- #
if [[ -d "${BACKEND_RES}" ]]; then
  cp "${CONFIG_DIR}/backend.configuration.properties" \
     "${BACKEND_RES}/configuration.properties"
  _success "backend.configuration.properties → kv-backend/src/main/resources/configuration.properties"
else
  _warn "kv-backend/src/main/resources/ not found — skipping backend configuration.properties"
fi

# --------------------------------------------------------------------------- #
# 6. xalan serializer dependency — ensure exactly one declaration in pom.xml
# --------------------------------------------------------------------------- #
_inject_xalan() {
  local pom="$1"
  if [[ ! -f "${pom}" ]]; then
    _warn "pom.xml not found: ${pom}"
    return
  fi

  # Count existing occurrences
  local count
  count=$(grep -c '<groupId>xalan</groupId>' "${pom}" 2>/dev/null || echo 0)

  if [[ "${count}" -eq 1 ]]; then
    _info "xalan serializer already present in ${pom} — skipping"
    return
  fi

  # Remove ALL existing xalan/serializer entries if there are duplicates
  if [[ "${count}" -gt 1 ]]; then
    _info "Removing ${count} duplicate xalan serializer entries from ${pom}"
    # Use a Python one-liner to safely remove xalan dependency blocks
    python3 << 'PYTHON_EOF'
import re
import sys
pom_file = sys.argv[1]
with open(pom_file, 'r') as f:
    content = f.read()
# Remove all <dependency> blocks containing xalan/serializer
content = re.sub(
    r'<dependency>\s*<groupId>xalan</groupId>.*?</dependency>',
    '',
    content,
    flags=re.DOTALL
)
with open(pom_file, 'w') as f:
    f.write(content)
PYTHON_EOF
    python3 -c "
import re, sys
pom_file = '${pom}'
with open(pom_file, 'r') as f:
    content = f.read()
content = re.sub(r'<dependency>\s*<groupId>xalan</groupId>.*?</dependency>', '', content, flags=re.DOTALL)
with open(pom_file, 'w') as f:
    f.write(content)
"
  fi

  # Check again after dedup
  if grep -q '<groupId>xalan</groupId>' "${pom}" 2>/dev/null; then
    _info "xalan serializer present after dedup — skipping injection"
    return
  fi

  # Insert before the closing </dependencies> tag using a temp file
  # This avoids sed's issues with literal \n in replacement strings
  local temp_file
  temp_file=$(mktemp)
  cat > "${temp_file}" << 'XALAN_BLOCK'
        <dependency>
            <groupId>xalan</groupId>
            <artifactId>serializer</artifactId>
            <version>2.7.3</version>
        </dependency>
XALAN_BLOCK

  # Use sed to insert the temp file content before </dependencies>
  sed -i "/<\/dependencies>/r ${temp_file}" "${pom}"
  rm -f "${temp_file}"

  _success "xalan serializer injected into ${pom}"
}

_inject_xalan "${KV_DIR}/portal/pom.xml"
_inject_xalan "${KV_DIR}/kv-backend/pom.xml"

# --------------------------------------------------------------------------- #
# 7. Copy sshprovision.sh to preload-docker-compose
# --------------------------------------------------------------------------- #
PRELOAD_DIR="${KV_DIR}/preload-docker-compose"
if [[ -d "${PRELOAD_DIR}" ]]; then
  if [[ -f "${CONFIG_DIR}/../kv-scripts/sshprovision.sh" ]]; then
    cp "${CONFIG_DIR}/../kv-scripts/sshprovision.sh" "${PRELOAD_DIR}/sshprovision.sh"
    chmod +x "${PRELOAD_DIR}/sshprovision.sh"
    _success "sshprovision.sh → preload-docker-compose/"
  else
    _warn "kv-scripts/sshprovision.sh not found — skipping"
  fi
else
  _warn "preload-docker-compose not found — skipping sshprovision.sh copy"
fi

# --------------------------------------------------------------------------- #
# 8. Create directories referenced by configuration.properties
# --------------------------------------------------------------------------- #
mkdir -p "${HOME}/uploads/invite"
mkdir -p "${HOME}/data/seller_rating/merged_feed"
mkdir -p "${KV_DIR}/data/csv"
mkdir -p "${KV_DIR}/data/xml"
_success "Runtime directories created"

_info "Done. All kv-config files applied."
