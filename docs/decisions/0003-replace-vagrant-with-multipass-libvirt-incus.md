# 0003. Replace Vagrant with Multipass / libvirt / Incus Providers

## Status

Accepted

## Context

ADR 0002 chose Vagrant as the VM provisioning abstraction, supporting
VirtualBox, KVM/libvirt, and VMware as hypervisor backends. After extended
use, Vagrant introduced several problems:

1. **Single point of failure** — Vagrant's Ruby-based provider plugins
   frequently broke on version upgrades, and the Vagrant Cloud box
   catalogue had intermittent availability issues.
2. **Heavy abstraction** — Vagrant's uniform CLI masks significant
   differences between hypervisors, leading to subtle bugs when a
   provider-specific behaviour (networking, shared folders, snapshot
   semantics) differs from what the Vagrantfile assumes.
3. **Declining momentum** — HashiCorp's investment in Vagrant has
   slowed; release cadence and community activity have decreased since
   the VMware acquisition.
4. **No native cloud-init workflow** — Vagrant supports cloud-init only
   through provider-specific workarounds. Multipass and libvirt use
   cloud-init as a first-class boot mechanism.
5. **ansible_local fragility** — Installing Ansible inside the VM via
   Vagrant's `ansible_local` provisioner added a fragile dependency chain
   (Ruby → Vagrant guest tools → pip → Ansible) that frequently broke on
   new Ubuntu releases.

The goal is a simpler, more reliable provisioning stack that uses each
virtualization tool's native strengths rather than forcing them through a
shared abstraction layer.

## Decision

Replace Vagrant with **three independent providers** probed in priority order:

| Priority | Provider | Platform | Type |
|----------|----------|----------|------|
| 1 | **Multipass** | macOS, Linux | Snap/cloud-native, cross-platform |
| 2 | **libvirt** | Linux only | Native KVM + cloud-init ISO |
| 3 | **Incus** | Linux only | LXD fork, lightweight VMs |

Key design choices:

- **No shared abstraction** — each provider has its own implementation in
  `lib/providers/<name>.sh` with a common interface (`boot_vm`,
  `destroy_vm`, internal helpers).
- **Cloud-init first-class** — all three providers use the same
  `vm/cloud-init/user-data` for first-boot configuration. No provider
  requires a shell provisioner for OS-level setup.
- **SSH-based Ansible** — Ansible runs over SSH from the host, not inside
  the VM. This eliminates the `ansible_local` dependency chain. The
  inventory uses environment variables (`VM_IP`, `VM_SSH_USER`,
  `VM_SSH_KEY`) set by whichever provider booted the VM.
- **Provider auto-detection** — `lib/detect.sh` probes the host OS and
  available tools; the first provider that can be installed and used is
  selected. The `--provider` flag forces a specific provider.
- **Auto-install with fallbacks** — `lib/dependencies.sh` installs the
  selected provider with multiple fallback methods (snap → apt → direct
  download for Multipass; apt/dnf for libvirt and Incus).
- **Java via apt, not SDKMAN** — the VM runs Ubuntu 24.04 LTS, which has
  first-class `openjdk-8-jdk` and `openjdk-17-jdk` packages. Using apt
  instead of SDKMAN removes a runtime dependency and simplifies the Java
  role.
- **Separate Tomcat role** — Tomcat 9 is a critical kv-backend dependency
  and deserves its own Ansible role rather than being bundled with Java.
- **Library-based architecture** — provisioning logic is modularised into
  `lib/` (log.sh, detect.sh, dependencies.sh, vm.sh, ansible_runner.sh,
  verify.sh) instead of a monolithic provision.sh script.

## Alternatives Considered

- **Keep Vagrant, fix the pain points** — possible, but Vagrant's
  fundamental model (shared abstraction over heterogeneous hypervisors)
  is the source of most issues, not a surface problem that can be patched.
- **Packer + Vagrant** — use Packer to build a pre-provisioned box.
  Adds complexity without addressing the Vagrant-specific fragility.
- **Single provider (Multipass only)** — simplest, but abandons Linux
  users who prefer native KVM performance or have Multipass
  unavailable.
- **Docker Desktop / Lima** — good for macOS, but does not provide a
  full VM with systemd required for the kv-backend stack.

## Consequences

**Positive:**
- Each provider is independent — a bug or version change in Multipass
  does not affect the libvirt or Incus code paths.
- Cloud-init works natively with all three providers (no Vagrant
  workarounds).
- SSH-based Ansible is simpler and more portable than ansible_local.
- Java installation via apt is faster and more reliable than SDKMAN
  for the two versions (8 and 17) used by kv-backend.
- The `lib/` module structure makes the provisioning logic easier to
  test and maintain than a monolithic script.
- `--provider` flag gives explicit control when needed.

**Trade-offs:**
- No single CLI like `vagrant ssh` that works identically across
  providers. Users SSH into the VM using standard `ssh` with the
  provider-reported IP address.
- No `vagrant snapshot` abstraction — snapshots are provider-specific
  (Multipass: `multipass snapshot`, libvirt: `virsh snapshot`,
  Incus: `incus snapshot`).
- Provider-specific suspend/resume/halt commands instead of uniform
  `vagrant suspend`/`vagrant halt`.
- Three code paths to maintain instead of one Vagrantfile — mitigated
  by the shared interface in `lib/providers/`.

## Related Documents

- [0002-use-ubuntu-vm-via-vagrant.md](./0002-use-ubuntu-vm-via-vagrant.md) — superseded
- [provision.sh](../../provision.sh)
- [lib/providers/multipass.sh](../../lib/providers/multipass.sh)
- [lib/providers/libvirt.sh](../../lib/providers/libvirt.sh)
- [lib/providers/incus.sh](../../lib/providers/incus.sh)
- [vm/cloud-init/user-data](../../vm/cloud-init/user-data)
- [ansible/inventory/hosts.yml](../../ansible/inventory/hosts.yml)
