# Language Runtimes

## Purpose

Reference guide for the language runtimes installed inside the developer VM.

## Scope

Covers Node.js, Python, and Java — their version managers, installed
versions, and how to switch between versions. Does not cover
project-level dependency management (`npm`, `pip`, `mvn`), which is
project-specific.

## Prerequisites

- Developer VM is running (`./provision.sh` completed).
- SSH into the VM: `ssh -i ~/.ssh/dev-env ubuntu@<VM_IP>`.

## Automation Status

**Fully automated** by Ansible:

| Runtime | Ansible role | What is installed |
|---|---|---|
| Node.js | [`ansible/roles/node`](../../ansible/roles/node/tasks/main.yml) | nvm, Node 18/20/22 (default: 20), pnpm |
| Python | [`ansible/roles/python`](../../ansible/roles/python/tasks/main.yml) | pyenv, Python 3.12 (default), pipenv, uv |
| Java | [`ansible/roles/java`](../../ansible/roles/java/tasks/main.yml) | OpenJDK 8 + 17 (apt), Maven 3.9.6 |

## Using Node.js (nvm)

```bash
# Load nvm (already in .bashrc)
source ~/.nvm/nvm.sh

nvm list             # installed versions
nvm use 22           # switch version for this shell
nvm alias default 20 # change the default

node --version
pnpm --version
```

## Using Python (pyenv)

```bash
pyenv versions       # installed versions
pyenv global 3.12.0  # set global default
python3 --version

# Create a project virtualenv
python3 -m venv .venv && source .venv/bin/activate

# Or with uv (faster)
uv venv && source .venv/bin/activate
```

## Using Java (apt / update-alternatives)

```bash
# List installed Java versions
sudo update-alternatives --config java

# Switch default (interactive — select from menu)
sudo update-alternatives --config java

# Verify
java -version
mvn --version
```

## Manual Install (fallback only)

If Ansible failed for a specific runtime:

```bash
# Node via nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

# Python via pyenv
curl -fsSL https://pyenv.run | bash

# Java via apt
sudo apt-get install -y openjdk-8-jdk openjdk-17-jdk
```

## References

- [nvm](https://github.com/nvm-sh/nvm)
- [pyenv](https://github.com/pyenv/pyenv)

## Related Documents

- [ansible/roles/node](../../ansible/roles/node/tasks/main.yml)
- [ansible/roles/python](../../ansible/roles/python/tasks/main.yml)
- [ansible/roles/java](../../ansible/roles/java/tasks/main.yml)
