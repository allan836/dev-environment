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
# 6. xalan serializer dependency — inject into pom.xml files if missing
# --------------------------------------------------------------------------- #
XALAN_SNIPPET='        <dependency>\n            <groupId>xalan</groupId>\n            <artifactId>serializer</artifactId>\n            <version>2.7.3</version>\n        </dependency>'

_inject_xalan() {
  local pom="$1"
  if [[ ! -f "${pom}" ]]; then
    _warn "pom.xml not found: ${pom}"
    return
  fi
  if grep -q "xalan.*serializer\|serializer.*xalan" "${pom}"; then
    _info "xalan serializer already present in ${pom} — skipping"
    return
  fi
  # Insert before the closing </dependencies> tag
  sed -i "0,/<\/dependencies>/{s|</dependencies>|${XALAN_SNIPPET}\n    </dependencies>|}" "${pom}"
  _success "xalan serializer injected into ${pom}"
}

_inject_xalan "${KV_DIR}/portal/pom.xml"
_inject_xalan "${KV_DIR}/kv-backend/pom.xml"

# --------------------------------------------------------------------------- #
# 7. Create directories referenced by configuration.properties
# --------------------------------------------------------------------------- #
mkdir -p "${HOME}/uploads/invite"
mkdir -p "${HOME}/data/seller_rating/merged_feed"
mkdir -p "${KV_DIR}/data/csv"
mkdir -p "${KV_DIR}/data/xml"
_success "Runtime directories created"

_info "Done. All kv-config files applied."
