# Bash Scripts

## Purpose

Document the Bash scripts in this repository: their roles, conventions,
and how they relate to each other.

## Scope

Covers `provision.sh` at the repo root, the `lib/` module library, scripts
under `vm/scripts/`, and scripts under `workstation-bootstrap/scripts/`.
Does not cover Ansible content — see [ansible.md](./ansible.md).

## Prerequisites

- [ARCHITECTURE.md](../../ARCHITECTURE.md) principles: idempotency,
  verification, manual fallback.

## Script Inventory

### Root level

| Script | Purpose |
|---|---|
| [`provision.sh`](../../provision.sh) | Single entry point. Sources `lib/` modules, probes providers in priority order (Multipass → libvirt → Incus), installs the selected provider, boots the Ubuntu VM, runs Ansible over SSH, clones kv-backend, starts Docker services, verifies. |

### `lib/` — Core provisioning modules

All modules are sourced by `provision.sh` and are not meant to be run
standalone.

| Module | Purpose |
|---|---|
| [`lib/log.sh`](../../lib/log.sh) | Structured logging helpers (`info`, `success`, `warn`, `error`, `banner`, `die`). |
| [`lib/detect.sh`](../../lib/detect.sh) | Host OS detection, hardware virtualization probe, provider availability checks. Exports `HOST_OS`, `PKG_MANAGER`, `HOST_ARCH`, `AVAILABLE_PROVIDERS`, `SELECTED_PROVIDER`. |
| [`lib/dependencies.sh`](../../lib/dependencies.sh) | Provider tool installation with fallback chains (snap → apt → direct download). |
| [`lib/vm.sh`](../../lib/vm.sh) | Provider-agnostic VM lifecycle management. Exports `VM_SSH_KEY`, `ACTIVE_PROVIDER`, `VM_IP`, `VM_SSH_USER`, `VM_SSH_PORT`. |
| [`lib/ansible_runner.sh`](../../lib/lib/ansible_runner.sh) | Ansible playbook execution orchestration over SSH. |
| [`lib/verify.sh`](../../lib/verify.sh) | Runs verification checks inside the VM via SSH. |
| [`lib/_verify_inside_vm.sh`](../../lib/_verify_inside_vm.sh) | Actual verification checks (runs inside VM): tools, runtimes, services. |

### `lib/providers/` — Provider implementations

Each provider implements `boot_vm` and `destroy_vm` functions consumed by
`lib/vm.sh`.

| Provider | Platform | Purpose |
|---|---|---|
| [`lib/providers/multipass.sh`](../../lib/providers/multipass.sh) | macOS, Linux | Multipass provider — cross-platform, snap-based. Mounts repo into VM. |
| [`lib/providers/libvirt.sh`](../../lib/providers/libvirt.sh) | Linux only | KVM/libvirt + cloud-init ISO provider. Downloads Ubuntu cloud image, creates qcow2 overlay + cloud-init seed ISO. |
| [`lib/providers/incus.sh`](../../lib/providers/incus.sh) | Linux only | Incus (LXD fork) VM provider. Lightweight alternative to KVM. |

### `vm/scripts/`

| Script | Purpose |
|---|---|
| [`provision-vm.sh`](../../vm/scripts/provision-vm.sh) | Pre-Ansible setup inside the VM. Ensures `apt` is fresh and Ansible dependencies are present. |
| [`wait-for-ssh.sh`](../../vm/scripts/wait-for-ssh.sh) | TCP readiness poller. Used to check SSH availability against a host:port. Accepts host, port, and optional timeout arguments. |

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
- OS detection is centralised in `lib/detect.sh` (exported as `HOST_OS`,
  `PKG_MANAGER`) — child scripts do not re-detect the OS.

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
