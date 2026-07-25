# Runbooks

## Purpose

Index of operational procedures for this workstation: rebuilding it from
scratch, recovering from failure, backing up state, and managing the
lifecycle of containerized services.

## Scope

Covers operational, task-oriented procedures. Does not cover installation
rationale or step-by-step tool setup — see [docs/setup](../setup/README.md).
Does not cover issue diagnosis — see [docs/troubleshooting](../troubleshooting/README.md).

## Prerequisites

- [docs/architecture/README.md](../architecture/README.md) for system
  design context.

## Contents

| Runbook | When to use |
|---|---|
| [new-machine-bootstrap.md](./new-machine-bootstrap.md) | Setting up a brand-new Fedora install |
| [disaster-recovery.md](./disaster-recovery.md) | Full recovery after hardware loss/failure |
| [backup-restore.md](./backup-restore.md) | Routine and pre-rebuild backups of stateful services |
| [service-lifecycle.md](./service-lifecycle.md) | Starting, stopping, updating containerized services |

## References

- [ARCHITECTURE.md](../../ARCHITECTURE.md)

## Related Documents

- [docs/setup/README.md](../setup/README.md)
- [docs/troubleshooting/README.md](../troubleshooting/README.md)
- [docs/security/README.md](../security/README.md)
