#!/usr/bin/env bash
# Installs language runtimes via version managers, identically on both OSes:
# nvm (Node), pyenv + pipenv + uv (Python), SDKMAN (Java + Maven), pnpm.
# Idempotent: skips anything already installed.
set -euo pipefail

: "${OS_FAMILY:?OS_FAMILY must be set (run via ./setup.sh)}"

has() { command -v "$1" >/dev/null 2>&1; }
SHELL_RC="$HOME/.bashrc"
[[ "$OS_FAMILY" == "mac" ]] && SHELL_RC="$HOME/.zshrc"

# --- Node via nvm ---
if [[ ! -d "$HOME/.nvm" ]]; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi
# shellcheck disable=SC1090
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
if has nvm; then
  for v in 18 20 22 24; do nvm install "$v" >/dev/null; done
  nvm alias default 20
fi

# --- pnpm ---
if ! has pnpm; then
  curl -fsSL https://get.pnpm.io/install.sh | sh -
fi

# --- Python: pyenv, pipenv, uv ---
if [[ ! -d "$HOME/.pyenv" ]]; then
  curl -fsSL https://pyenv.run | bash
fi
if has pip3; then
  pip3 install "pipenv>=2026.0.2" --user
  echo "export PATH=\"\$PATH:$(python3 -m site --user-base)/bin\"" >> "$SHELL_RC"
fi
if ! has uv; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# --- Java + Maven via SDKMAN ---
if [[ ! -d "$HOME/.sdkman" ]]; then
  curl -s "https://get.sdkman.io" | bash
fi
# shellcheck disable=SC1090
[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ] && source "$HOME/.sdkman/bin/sdkman-init.sh"
if has sdk; then
  sdk install java 8.0.442-amzn <<< "n" || true
  sdk install java 17.0.12-oracle <<< "n" || true
  sdk default java 17.0.12-oracle
  sdk install maven 3.8.8 <<< "n" || true
fi

echo "Language runtimes install stage complete. Restart your shell (or 'source $SHELL_RC') to pick up PATH changes."
