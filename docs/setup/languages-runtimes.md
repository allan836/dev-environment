# Language Runtimes

## Purpose

Reference guide for the language runtimes installed inside the developer VM.

## Scope

Covers Node.js, Python, and Java — their version managers, installed
versions, and how to switch between versions. Does not cover
project-level dependency management (`npm`, `pip`, `mvn`), which is
project-specific.

## Prerequisites

- Developer VM is running (`./provision.sh` completed or `cd vm && vagrant up`).
- SSH into the VM: `cd vm && vagrant ssh`.

## Automation Status

**Fully automated** by Ansible:

| Runtime | Ansible role | What is installed |
|---|---|---|
| Node.js | [`ansible/roles/node`](../../ansible/roles/node/tasks/main.yml) | nvm, Node 18/20/22/24 (default: 20), pnpm |
| Python | [`ansible/roles/python`](../../ansible/roles/python/tasks/main.yml) | pyenv, Python 3.12 (default), pipenv, uv |
| Java | [`ansible/roles/java`](../../ansible/roles/java/tasks/main.yml) | SDKMAN, Java 8 (Amazon Corretto) + Java 17 (Oracle, default), Maven 3.8.8 |

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

## Using Java (SDKMAN)

```bash
source ~/.sdkman/bin/sdkman-init.sh

sdk list java          # available JDKs
sdk use java 8.0.442-amzn  # switch for current shell
sdk default java 17.0.12-oracle  # set permanent default

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

# Java via SDKMAN
curl -s "https://get.sdkman.io" | bash
```

## References

- [nvm](https://github.com/nvm-sh/nvm)
- [pyenv](https://github.com/pyenv/pyenv)
- [SDKMAN](https://sdkman.io/)

## Related Documents

- [ansible/roles/node](../../ansible/roles/node/tasks/main.yml)
- [ansible/roles/python](../../ansible/roles/python/tasks/main.yml)
- [ansible/roles/java](../../ansible/roles/java/tasks/main.yml)
