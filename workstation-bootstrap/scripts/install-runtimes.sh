#!/usr/bin/env bash
# =============================================================================
# install-runtimes.sh — Language runtime installation
#
# Installs: nvm + Node.js, pnpm, pyenv + Python, SDKMAN + Java 8 + Java 17,
#           Maven.
#
# All versions are read from config.env (repository root).
# Idempotent: each tool is skipped if already present.
# Requires OS_FAMILY to be exported by setup.sh.
# =============================================================================
set -euo pipefail

: "${OS_FAMILY:?OS_FAMILY must be set (run via ./setup.sh)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_ENV="${REPO_ROOT}/config.env"

if [[ ! -f "$CONFIG_ENV" ]]; then
  echo "Error: config.env not found at ${CONFIG_ENV}" >&2
  echo "       Are you running this from inside the dev-environment repository?" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_ENV"

has() { command -v "$1" >/dev/null 2>&1; }

SHELL_RC="$HOME/.bashrc"
[[ "$OS_FAMILY" == "mac" ]] && SHELL_RC="$HOME/.zshrc"

# --------------------------------------------------------------------------- #
# Node.js via nvm
# --------------------------------------------------------------------------- #
if [[ ! -d "$HOME/.nvm" ]]; then
  echo "==> Installing nvm ${NVM_VERSION}..."
  curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash
fi

export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1090
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

if has nvm; then
  echo "==> Installing Node.js versions: ${NODE_VERSIONS}..."
  for v in $NODE_VERSIONS; do
    nvm install "$v" >/dev/null
  done
  nvm alias default "${NODE_DEFAULT}"
  echo "==> Node.js default: $(node --version)"
fi

# ---- pnpm ------------------------------------------------------------------
if ! has pnpm; then
  echo "==> Installing pnpm..."
  curl -fsSL https://get.pnpm.io/install.sh | sh -
fi

# --------------------------------------------------------------------------- #
# Python via pyenv
# --------------------------------------------------------------------------- #
if [[ ! -d "$HOME/.pyenv" ]]; then
  echo "==> Installing pyenv..."
  curl -fsSL https://pyenv.run | bash
fi

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if has pyenv; then
  eval "$(pyenv init -)"
  echo "==> Installing Python ${PYTHON_VERSION} via pyenv..."
  pyenv install -s "${PYTHON_VERSION}"
  pyenv global "${PYTHON_VERSION}"
  echo "==> Python: $(python3 --version)"
fi

if has pip3; then
  echo "==> Installing pipenv..."
  pip3 install --user pipenv || true
fi

if ! has uv; then
  echo "==> Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# --------------------------------------------------------------------------- #
# Java 8 + Java 17 via apt (Ubuntu/Debian) or SDKMAN (macOS/Fedora)
# CRITICAL: only Java 8 and Java 17 — kv-backend compatibility
# --------------------------------------------------------------------------- #
case "$OS_FAMILY" in
  ubuntu|debian)
    echo "==> Installing Java 8 (${JAVA_8_PKG}) and Java 17 (${JAVA_17_PKG}) via apt..."
    sudo apt-get update -qq
    # Ubuntu 24.04 may need the openjdk-r PPA for Java 8
    if apt-cache show "${JAVA_8_PKG}" &>/dev/null; then
      sudo apt-get install -y "${JAVA_8_PKG}" "${JAVA_17_PKG}"
    else
      sudo apt-get install -y software-properties-common
      sudo add-apt-repository -y ppa:openjdk-r/ppa
      sudo apt-get update -qq
      sudo apt-get install -y "${JAVA_8_PKG}" "${JAVA_17_PKG}"
    fi
    # Set Java 17 as default
    sudo update-alternatives --set java \
      "$(update-alternatives --list java | grep java-17)" 2>/dev/null || true
    echo "==> Java default: $(java -version 2>&1 | head -n1)"
    ;;
  mac|fedora|rhel)
    # Use SDKMAN on macOS and Fedora
    if [[ ! -d "$HOME/.sdkman" ]]; then
      echo "==> Installing SDKMAN..."
      curl -s "https://get.sdkman.io" | bash
    fi
    # shellcheck disable=SC1090
    [ -s "$HOME/.sdkman/bin/sdkman-init.sh" ] && source "$HOME/.sdkman/bin/sdkman-init.sh"
    if has sdk; then
      echo "==> Installing Java 8 and Java 17 via SDKMAN..."
      # Install OpenJDK builds — identifiers listed via: sdk list java | grep open
      sdk install java 8-open  <<< "n" || sdk install java 8.0.432-open  <<< "n" || true
      sdk install java 17-open <<< "n" || sdk install java 17.0.12-open  <<< "n" || true
      sdk default java 17-open 2>/dev/null || sdk default java 17.0.12-open 2>/dev/null || true
      echo "==> Java default: $(java -version 2>&1 | head -n1)"
    fi
    ;;
esac

# --------------------------------------------------------------------------- #
# Maven
# --------------------------------------------------------------------------- #
if ! has mvn; then
  echo "==> Installing Maven ${MAVEN_VERSION}..."
  curl -fsSL "${MAVEN_ARCHIVE_URL}" -o /tmp/apache-maven-bin.tar.gz
  sudo mkdir -p /opt/maven
  sudo tar -xzf /tmp/apache-maven-bin.tar.gz --strip-components=1 -C /opt/maven
  sudo ln -sf /opt/maven/bin/mvn /usr/local/bin/mvn
  rm -f /tmp/apache-maven-bin.tar.gz
  echo "==> Maven: $(mvn --version | head -n1)"
fi

echo ""
echo "==> Language runtimes install complete."
echo "    Restart your shell (or source ${SHELL_RC}) to pick up PATH changes."
