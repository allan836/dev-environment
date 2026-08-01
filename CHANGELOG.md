# Changelog

## Purpose

Track notable changes to this repository over time, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) conventions.

## Scope

Covers automation additions, documentation changes, and breaking changes to
the repository layout. Does not cover the workstation's own software
versions.

## Prerequisites

None.

## Format

This project follows [Semantic Versioning](https://semver.org/).
`0.x` releases are the current automation phase.

---

## [0.3.0] — 2026-08

### Added

- **Three virtualization providers** replacing Vagrant: Multipass
  (cross-platform), libvirt (Linux native KVM + cloud-init ISO), and Incus
  (Linux LXD fork). Each provider has its own implementation in
  `lib/providers/<name>.sh` with a common interface.
- **`lib/` module library** — modularised provisioning logic:
  - `lib/log.sh` — structured logging helpers (info, warn, error, banner, die).
  - `lib/detect.sh` — host OS detection, hardware virtualization probe,
    provider availability checks.
  - `lib/dependencies.sh` — provider tool installation with fallback chains
    (snap → apt → direct download).
  - `lib/vm.sh` — provider-agnostic VM lifecycle management.
  - `lib/ansible_runner.sh` — Ansible playbook execution over SSH.
  - `lib/verify.sh` + `lib/_verify_inside_vm.sh` — post-provisioning
    verification inside the VM.
- **`--provider` flag** — force a specific provider (multipass, libvirt, or
  incus) instead of automatic detection.
- **`--disk` flag** — custom disk size (default: 40 GB).
- **`config.env`** — central version configuration file at the repository
  root. Single source of truth for all software versions.
- **`ansible/roles/tomcat`** — dedicated Tomcat 9 role (separated from Java
  role; Tomcat 9 is a critical kv-backend requirement).
- **SSH-based Ansible** — Ansible runs over SSH from the host, not via
  `ansible_local` inside the VM. Inventory uses environment variables
  (`VM_IP`, `VM_SSH_USER`, `VM_SSH_KEY`).
- **Java via apt** — OpenJDK 8 and 17 installed via `apt` packages
  (`openjdk-8-jdk`, `openjdk-17-jdk`) instead of SDKMAN. Simpler and
  faster for the two versions required by kv-backend.
- **ADR 0003** — documents the decision to replace Vagrant with
  Multipass/libvirt/Incus providers.

### Changed

- `provision.sh` — rewritten to source `lib/` modules, probe providers in
  priority order, and run Ansible over SSH instead of via Vagrant.
- `ansible/inventory/hosts.yml` — changed from `ansible_connection: local`
  to SSH-based connection using environment variables.
- `vm/cloud-init/user-data` — preserves `ubuntu` user (required for
  provider SSH), adds `developer` user with same permissions.
- `README.md` — updated to reflect provider-based provisioning model.
- `ARCHITECTURE.md` — updated layer table to reference providers instead
  of Vagrant.
- `docs/architecture/overview.md` — rewritten for the provider-based stack.
- `docs/automation/README.md` — updated directory map and flow diagram.
- `docs/automation/ansible.md` — updated for SSH-based Ansible, apt-based
  Java, added Tomcat role.
- `docs/automation/bash-scripts.md` — updated to document `lib/` modules
  and provider scripts.
- `docs/runbooks/new-machine-bootstrap.md` — fully rewritten for
  provider-based provisioning with per-provider lifecycle commands.
- `docs/runbooks/backup-restore.md` — updated snapshots section with
  provider-specific commands.
- `docs/runbooks/disaster-recovery.md` — updated for provider-based
  recovery.
- `docs/runbooks/service-lifecycle.md` — updated SSH instructions.
- `docs/setup/*.md` — updated SSH instructions from `vagrant ssh` to
  `ssh -i ~/.ssh/dev-env ubuntu@<VM_IP>`.
- `docs/setup/languages-runtimes.md` — updated Java section from SDKMAN
  to apt; corrected Maven version to 3.9.6; corrected Node versions to
  18/20/22 (no 24).
- `docs/decisions/0002` — status changed to "Superseded by 0003".
- `CONTRIBUTING.md` — updated testing instructions for SSH-based Ansible.
- `ROADMAP.md` — updated Phase 1 description to reflect provider model.

### Removed

- **Vagrant** — no longer used as a provisioning abstraction.
- **`vm/Vagrantfile`** — replaced by `lib/providers/` implementations.
- **VirtualBox and VMware providers** — replaced by Multipass, libvirt, and
  Incus.

---

## [0.2.0] — 2026-08

### Added

- **`provision.sh`** — single-command developer environment provisioner at
  the repository root. Installs Vagrant on the host, then tries hypervisor
  backends in order (VirtualBox → KVM/libvirt → VMware) until one succeeds.
  On failure, destroys the partial VM and moves to the next backend. Runs
  cloud-init, Ansible, kv-backend clone, Docker services, and verification
  end-to-end.

- **`vm/Vagrantfile`** — multi-provider VM definition for VirtualBox,
  KVM/libvirt, and VMware. Reads VM name, CPU, and RAM from environment
  variables set by `provision.sh`. Uses Ubuntu 24.04 LTS cloud boxes.

- **`vm/cloud-init/user-data`** — first-boot OS configuration: developer
  user, SSH authorised key, timezone, base package list, workspace
  directory structure.

- **`vm/cloud-init/meta-data`** — cloud-init instance identity.

- **`vm/scripts/provision-vm.sh`** — shell provisioner that runs inside
  the VM before Ansible to ensure `apt`, Ansible, and Python are ready.

- **`vm/scripts/wait-for-ssh.sh`** — TCP readiness poller for SSH port
  availability (used in the raw VBoxManage code path).

- **`ansible/playbook.yml`** — full Ansible playbook covering all developer
  tools in role order.

- **`ansible/inventory/hosts.yml`** — local-connection inventory for
  single-host VM provisioning.

- **Ansible roles** (all new):
  - `ansible/roles/docker` — Docker Engine + Compose plugin via official
    Docker apt repository.
  - `ansible/roles/java` — Java 8 + 17 via SDKMAN, Maven 3.8.
  - `ansible/roles/node` — Node 18/20/22/24 via nvm, pnpm.
  - `ansible/roles/python` — pyenv, Python 3.12, pipenv, uv.
  - `ansible/roles/terraform` — Terraform via HashiCorp apt repo, OpenTofu.
  - `ansible/roles/kubectl` — kubectl, Helm, k9s.
  - `ansible/roles/cloud_clis` — AWS CLI v2, Azure CLI, Google Cloud CLI.
  - `ansible/roles/developer_tools` — VS Code, GitHub CLI, openfortivpn,
    DBeaver, tmux, fzf, ripgrep, and shell tools.
  - `ansible/roles/kv_backend` — kv-backend git clone, Docker image load
    from tarball, `.env` setup.

- **ADR 0002** — documents the decision to move from a Fedora host model
  to an Ubuntu VM via Vagrant.

### Changed

- `README.md` — Quick Start rewritten to the three-line single-command flow.
- `ROADMAP.md` — Phase 1 marked complete; phases 2–5 updated to reflect
  what is built and what remains.
- `docs/runbooks/new-machine-bootstrap.md` — fully rewritten to document
  the `provision.sh` workflow. The old manual Fedora procedure is replaced.
- `docs/runbooks/README.md` — updated index and quick-reference commands.
- `docs/runbooks/disaster-recovery.md` — updated for VM-based recovery
  (destroy and reprovision vs. reinstall OS).
- `docs/runbooks/service-lifecycle.md` — rewritten to document actual
  Makefile targets (`make kv-up`, `make kv-init`, etc.).
- `docs/runbooks/backup-restore.md` — added VM snapshot guidance alongside
  database dump procedures.
- `docs/automation/README.md` — updated directory map with status column
  (Implemented / Planned).
- `docs/automation/ansible.md` — updated from "planned structure" to
  "implemented structure" with actual role inventory and usage.
- `docs/automation/bash-scripts.md` — updated to document all real scripts.
- `docs/automation/docker-compose.md` — updated to document working
  kv-backend Compose stack and planned general stacks.
- `docs/architecture/README.md` — updated scope to include VM layer.
- `docs/architecture/overview.md` — rewritten to describe the four-layer
  model: host → VM → tooling → services.
- `docs/setup/README.md` — updated to clarify guides are reference/fallback,
  not the primary setup path; added Ansible role column.
- `docs/decisions/0001` — status updated to "Superseded by 0002".
- `docs/decisions/README.md` — ADR index updated with 0002.
- `CONTRIBUTING.md` — automation standards updated to reflect implemented
  state; testing instructions added for Ansible and provision.sh changes.

---

## [0.1.0] — 2026-07

### Added

- **`workstation-bootstrap/`** — cross-platform (macOS / Fedora / Ubuntu /
  Debian) host bootstrap for existing machines.
  - `setup.sh` — OS-aware entry point running four install stages.
  - `scripts/install-core.sh` — Git, Docker, GitHub CLI, Terraform, kubectl.
  - `scripts/install-runtimes.sh` — nvm (Node), pyenv (Python), SDKMAN
    (Java + Maven), pnpm.
  - `scripts/install-desktop-apps.sh` — VS Code, DBeaver, Slack, Zoom
    (best-effort, non-blocking).
  - `scripts/kv-backend.sh` — Docker image load, Compose up, kv-init,
    verify.
  - `scripts/kv-clean-slate.sh` — wipe and rebuild from zero; optional
    `--remote` Uniserver seed.
  - `scripts/verify.sh` — version check for all tools and service ports.
  - `Makefile` — `kv-up`, `kv-init`, `kv-verify`, `kv-clean-slate`,
    `kv-status`, `kv-logs`, `kv-down`.
  - `assets/preload_kv.tar.gz` — pre-built Docker images (754 MB).

- Initial documentation set under `docs/`: architecture, setup, automation,
  runbooks, troubleshooting, security, and decision records.

- `ARCHITECTURE.md`, `CONTRIBUTING.md`, `ROADMAP.md`, `README.md` — core
  repository documents.

---

## References

- [Keep a Changelog](https://keepachangelog.com/)
- [Semantic Versioning](https://semver.org/)

## Related Documents

- [ROADMAP.md](./ROADMAP.md)
- [README.md](./README.md)
