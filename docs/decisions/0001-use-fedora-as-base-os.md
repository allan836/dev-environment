# 0001. Use Fedora Workstation as the Base OS

## Status

Superseded by [0002](./0002-use-ubuntu-vm-via-vagrant.md)

## Context

The workstation needs a Linux distribution that provides current package
versions for cloud/platform engineering tooling (containers, Kubernetes,
language runtimes), strong upstream alignment with Red Hat/OpenShift
ecosystems commonly used in enterprise platform engineering, and a
predictable release cadence for reproducible rebuilds.

## Decision

Standardize on Fedora Workstation (latest two releases supported) as the
only officially supported OS for this repository.

## Alternatives Considered

- **Ubuntu/Debian** — very common, but slower-moving package versions on
  LTS releases can lag behind the container/Kubernetes ecosystem's pace.
- **Arch Linux** — bleeding-edge packages and full declarative control, but
  higher maintenance burden and less predictable stability for a
  professional daily-driver workstation.
- **macOS** — strong developer tooling, but outside the scope of an
  IaC/Ansible-driven Linux workstation rebuild story, and not the target
  hardware for this repository.

## Consequences

- All original setup guides under [docs/setup](../setup/README.md) used
  `dnf` and Fedora-specific repositories.
- This decision was superseded when the team moved to a VM-based model
  (see ADR 0002), where the VM OS is Ubuntu 24.04 LTS and the host OS
  can be anything with Vagrant/VirtualBox support.

## Related Documents

- [0002-use-ubuntu-vm-via-vagrant.md](./0002-use-ubuntu-vm-via-vagrant.md)
- [README.md](../../README.md) — Supported Platforms section.
