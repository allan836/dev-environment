# Bash Scripts

## Purpose

Document the Bash scripts in this repository: their roles, conventions,
and how they relate to each other.

## Scope

Covers `provision.sh` at the repo root, scripts under `vm/scripts/`, and
scripts under `workstation-bootstrap/scripts/`. Does not cover Ansible
content — see [ansible.md](./ansible.md).

## Prerequisites

- [ARCHITECTURE.md](../../ARCHITECTURE.md) principles: idempotency,
  verification, manual fallback.

## Script Inventory

### Root level

| Script | Purpose |
|---|---|
| [`provision.sh`](../../provision.sh) | Single entry point. Installs Vagrant, tries hypervisor backends in order (VirtualBox → KVM → VMware), boots the Ubuntu VM, runs Ansible, clones kv-backend, starts Docker services, verifies. |

### `vm/scripts/`

| Script | Purpose |
|---|---|
| [`provision-vm.sh`](../../vm/scripts/provision-vm.sh) | Runs inside the VM on first boot (via Vagrant shell provisioner). Ensures `apt` is fresh, installs Ansible and Python, sets hostname and timezone. Called before the Ansible playbook runs. |
| [`wait-for-ssh.sh`](../../vm/scripts/wait-for-ssh.sh) | TCP readiness poller. Used when SSH availability needs to be checked against a host:port without Vagrant. Accepts host, port, and optional timeout arguments. |

### `workstation-bootstrap/scripts/`

| Script | Purpose |
|---|---|
| [`install-core.sh`](../../workstation-bootstrap/scripts/install-core.sh) | Installs Git, Docker, GitHub CLI, OpenVPN, AWS CLI, Terraform, kubectl. OS-aware (macOS / Fedora / Ubuntu / Debian). |
| [`install-runtimes.sh`](../../workstation-bootstrap/scripts/install-runtimes.sh) | Installs Node via nvm, Python via pyenv, Java + Maven via SDKMAN, pnpm. |
| [`install-desktop-apps.sh`](../../workstation-bootstrap/scripts/install-desktop-apps.sh) | Best-effort install of VS Code, DBeaver, Slack, Zoom. Non-blocking — failures are warned, not fatal. |
| [`kv-backend.sh`](../../workstation-bootstrap/scripts/kv-backend.sh) | Loads Docker images, starts kv-backend Docker Compose stack, runs first-time init, verifies service ports. |
| [`kv-clean-slate.sh`](../../workstation-bootstrap/scripts/kv-clean-slate.sh) | Wipes all Docker volumes and rebuilds from zero. Supports optional `--remote` flag for Uniserver seeding. |
| [`verify.sh`](../../workstation-bootstrap/scripts/verify.sh) | Checks all tools and service ports. Prints `[ok]` or `[MISSING]` per tool. Non-fatal — reports gaps without aborting. |

## Conventions

All scripts follow these rules:

- Start with `set -euo pipefail`.
- Idempotent — every install step checks whether the tool already exists
  before attempting installation (using `command -v`, `stat`, or equivalent).
- Print clear, human-readable status lines (`==>`, `[ok]`, `warning:`,
  `Error:`).
- No hardcoded secrets — credentials come from `workstation-bootstrap/.env`
  or environment variables.
- Every script has a verification step or produces output confirming what
  was done.
- OS detection is centralised in `setup.sh` (`OS_FAMILY` env var) and
  passed to child scripts — child scripts do not re-detect the OS.

## Naming conventions

- Lowercase kebab-case, `.sh` extension.
- Verb-first names: `install-core.sh`, `verify.sh`, `wait-for-ssh.sh`.

## References

- [ShellCheck](https://www.shellcheck.net/)
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)

## Related Documents

- [provision.sh](../../provision.sh)
- [ansible.md](./ansible.md)
- [docs/runbooks/new-machine-bootstrap.md](../runbooks/new-machine-bootstrap.md)
