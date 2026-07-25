# 0001. Use Fedora Workstation as the Base OS

## Status

Accepted

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

- All setup guides ([docs/setup](../setup/README.md)) use `dnf` and
  Fedora-specific repositories.
- Ansible roles (once implemented) target the `dnf`/`systemd` toolchain
  exclusively.
- Multi-OS support (macOS/Windows) is explicitly out of scope unless a
  future ADR supersedes this one.

## Related Documents

- [docs/setup/fedora-base-setup.md](../setup/fedora-base-setup.md)
- [README.md](../../README.md) — Supported Platforms section.
