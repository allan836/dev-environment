# 0002. Use Ubuntu 24.04 VM via Vagrant as the Developer Environment

## Status

Accepted

## Context

ADR 0001 standardised on Fedora Workstation as the host OS. This required
every new developer to:

1. Download the Fedora ISO.
2. Create a VM or reinstall their laptop.
3. Configure CPU, RAM, and disk.
4. Install Fedora through the graphical installer.
5. Clone this repository.
6. Run setup scripts.

This process took 1–2 hours, involved many manual decisions (partitioning,
user setup, locale), and produced slightly different environments across
developers depending on which Fedora version and package state they started
from.

Additionally, some developers work on macOS laptops and could not use the
Fedora-targeted scripts at all without modification.

The goal is a single command that works on any developer laptop regardless
of host OS, and produces an identical environment every time.

## Decision

Replace the bare Fedora host model with a **Vagrant-managed Ubuntu 24.04
LTS virtual machine** as the standard developer environment. The host OS
(macOS, Ubuntu, Debian, Fedora) is irrelevant — only `git` and internet
access are required on the host.

The provisioning stack:

- **Vagrant** — installed by `provision.sh` on the host; provides a single
  CLI interface that abstracts VirtualBox, KVM, and VMware.
- **Ubuntu 24.04 LTS cloud image** — pre-installed Ubuntu system; no ISO
  installer required. Boot time from zero is under 2 minutes.
- **cloud-init** — handles first-boot OS configuration (user, SSH keys,
  base packages, timezone) declaratively.
- **Ansible** — installs all developer tools inside the VM via idempotent
  roles (one role per tool). Replaces the bash-script-per-tool approach.

The hypervisor backend is selected automatically by trying VirtualBox,
then KVM/libvirt, then VMware Workstation/Fusion — whichever succeeds
first is used.

## Alternatives Considered

- **Keep Fedora host, just add more automation** — this still requires
  developers to install Fedora manually. It does not solve the multi-OS
  host problem or the environment consistency problem.
- **Docker Dev Containers** — provides environment isolation without a
  full VM, but Docker-in-Docker (needed for kv-backend's Docker Compose
  stack) is complex and not well-supported in all cases.
- **Nix/NixOS** — fully declarative, but high learning curve and
  significant tooling investment to adapt existing scripts.
- **Vagrant without cloud-init** — possible, but cloud-init provides
  first-boot configuration that runs before Vagrant's shell provisioner,
  ensuring the system is in a known state before Ansible starts.
- **Raw VBoxManage (no Vagrant)** — more control, but requires separate
  implementations for each hypervisor rather than Vagrant's single
  abstraction layer.

## Consequences

**Positive:**
- A new developer needs only `git` and internet access. `provision.sh`
  acquires all other dependencies automatically.
- The VM is identical for every developer regardless of host OS.
- The VM is disposable — `vagrant destroy && ./provision.sh` returns to a
  clean known state in ~10 minutes.
- Host laptops are untouched — no developer tools are installed on the host.
- The Ansible playbook targets Ubuntu's `apt`/`systemd` toolchain, which
  has broader package availability and more official Docker/HashiCorp
  support than `dnf`.

**Trade-offs:**
- Developers must have a hypervisor available (VirtualBox is free and
  cross-platform; most laptops can run it).
- VM overhead (~1–2 GB RAM for the guest OS) compared to native install.
- `vagrant ssh` is the entry point to the environment, not the native
  terminal.
- Fedora-specific setup guides (under `docs/setup/`) remain as reference
  but the `fedora-base-setup.md` guide no longer represents the primary
  setup path.

## Related Documents

- [0001-use-fedora-as-base-os.md](./0001-use-fedora-as-base-os.md) — superseded
- [provision.sh](../../provision.sh)
- [vm/Vagrantfile](../../vm/Vagrantfile)
- [vm/cloud-init/user-data](../../vm/cloud-init/user-data)
- [ansible/playbook.yml](../../ansible/playbook.yml)
- [docs/runbooks/new-machine-bootstrap.md](../runbooks/new-machine-bootstrap.md)
