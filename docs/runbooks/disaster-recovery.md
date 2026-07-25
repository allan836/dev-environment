# Runbook: Disaster Recovery

## Purpose

Describe how to recover full workstation productivity after catastrophic
loss of the machine (hardware failure, theft, disk corruption).

## Scope

Covers the recovery sequence and its dependencies on backups and this
repository. Does not duplicate setup instructions — see
[docs/runbooks/new-machine-bootstrap.md](./new-machine-bootstrap.md). Does
not define backup mechanics — see
[docs/runbooks/backup-restore.md](./backup-restore.md).

## Prerequisites

- Off-machine backups exist for anything not in Git (per
  [docs/runbooks/backup-restore.md](./backup-restore.md)):
  database volumes, SSH private keys (via a secure secret manager, not this
  repository), and any credential store.
- Access to this repository from another device or via GitHub.

## Recovery Procedure

1. **Assess loss.** Confirm what was lost: OS only, or OS + data volumes.
2. **Provision new hardware/VM** and install Fedora Workstation.
3. **Recover access to secrets** (SSH keys, cloud credentials, vault
   passwords) from your secret manager — see
   [docs/security/secrets-management.md](../security/secrets-management.md).
   This repository intentionally contains none of these.
4. **Clone this repository.**
5. **Run the full bootstrap procedure**: follow
   [docs/runbooks/new-machine-bootstrap.md](./new-machine-bootstrap.md)
   end to end.
6. **Restore stateful service data** (databases, message queues) from the
   most recent backup per
   [docs/runbooks/backup-restore.md](./backup-restore.md).
7. **Verify** each restored service using the verification steps in
   [docs/setup/databases-services.md](../setup/databases-services.md).
8. **Record the incident** — add a note to this runbook or open an issue if
   the recovery revealed a gap in documentation or automation.

## Recovery Time Assumptions

Recovery time depends on network speed (package downloads, container image
pulls) and backup restore size. No fixed SLA is assumed; the goal is
"hours, not days" per the project vision in [README.md](../../README.md).

## References

- [ARCHITECTURE.md](../../ARCHITECTURE.md)

## Related Documents

- [docs/runbooks/new-machine-bootstrap.md](./new-machine-bootstrap.md)
- [docs/runbooks/backup-restore.md](./backup-restore.md)
- [docs/security/secrets-management.md](../security/secrets-management.md)
