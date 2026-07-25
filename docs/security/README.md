# Security Documentation

## Purpose

Index of security-related documentation: how secrets are handled and how
SSH keys are managed on this workstation.

## Scope

Covers workstation-level secret handling and SSH key lifecycle. Does not
cover application-level security practices for individual projects, which
are out of scope for this repository.

## Prerequisites

- [ARCHITECTURE.md](../../ARCHITECTURE.md) principle: secrets are never
  committed.

## Contents

| Document | Description |
|---|---|
| [secrets-management.md](./secrets-management.md) | How credentials, tokens, and passwords are stored and injected |
| [ssh-key-management.md](./ssh-key-management.md) | SSH key generation, rotation, and storage policy |

## References

- [ARCHITECTURE.md](../../ARCHITECTURE.md)

## Related Documents

- [.gitignore](../../.gitignore) — enforces secrets are never staged.
- [CONTRIBUTING.md](../../CONTRIBUTING.md)
- [docs/setup/cloud-clis.md](../setup/cloud-clis.md)
