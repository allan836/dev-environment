# Runbook: Backup & Restore

## Purpose

Define what must be backed up outside of Git, and the general approach for
backing up and restoring stateful containerized services.

## Scope

Covers backup targets and restore procedure outline for local services.
Does not implement backup scripts yet (placeholders live under
[scripts/README.md](../../scripts/README.md)). Does not cover disaster
recovery sequencing — see [docs/runbooks/disaster-recovery.md](./disaster-recovery.md).

## Prerequisites

- [docs/architecture/storage.md](../architecture/storage.md) for the
  volume/persistence model this runbook backs up.

## What Must Be Backed Up

Everything in this repository is already backed up by virtue of being in
Git/GitHub. The following are **not** in Git and require a separate backup
strategy:

| Item | Location | Backup Approach |
|---|---|---|
| Database volumes (Postgres, MySQL, MongoDB, Cassandra, Neo4j) | Docker named volumes | Periodic dump/export (see per-service tooling) to an off-machine location |
| RabbitMQ definitions/queues | Docker named volume | Export definitions via management API |
| Qdrant collections | Docker named volume | Snapshot API export |
| Ollama models | Docker named volume | Re-pullable from model registry; backup optional |
| SSH private keys | `~/.ssh/` | Secure secret manager, never this repository |
| Cloud CLI credentials | `~/.aws/`, `~/.azure/`, `~/.config/gcloud/` | Re-authenticate rather than backup, where possible |

## Restore Procedure (Outline)

1. Ensure the target service is running (see
   [docs/runbooks/service-lifecycle.md](./service-lifecycle.md)).
2. Restore the relevant database dump/snapshot using the tool's native
   restore command (e.g. `pg_restore`, `mongorestore`).
3. Verify using the per-service verification steps in
   [docs/setup/databases-services.md](../setup/databases-services.md).

## Automation Status

Not yet automated. Backup/restore scripts are planned under
[scripts/README.md](../../scripts/README.md) — see [ROADMAP.md](../../ROADMAP.md)
Phase 5.

## References

- [Docker volume backup guidance](https://docs.docker.com/storage/volumes/#back-up-restore-or-migrate-data-volumes)

## Related Documents

- [docs/architecture/storage.md](../architecture/storage.md)
- [docs/runbooks/disaster-recovery.md](./disaster-recovery.md)
- [docs/runbooks/service-lifecycle.md](./service-lifecycle.md)
- [docs/setup/databases-services.md](../setup/databases-services.md)
