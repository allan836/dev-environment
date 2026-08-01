# Storage Architecture

## Purpose

Describe how data persistence is handled for containerized services, and
the general strategy for separating disposable state from state that must
survive a rebuild.

## Scope

Covers Docker/Podman volume strategy and its relationship to backup and
disaster recovery. Does not define backup schedules or commands — see
[docs/runbooks/backup-restore.md](../runbooks/backup-restore.md).

## Prerequisites

- [docs/architecture/overview.md](./overview.md)

## Principles

- All stateful services (MySQL, Cassandra, RabbitMQ, Solr) use named Docker
  volumes, never anonymous volumes or container-internal storage, so data
  survives container recreation.
- Named volumes are mapped under a predictable path (documented per stack in
  [docs/setup/databases-services.md](../setup/databases-services.md)) to
  simplify backup tooling.
- Redis is treated as a cache by default (no durable volume). If a specific
  workflow requires persistence, it will be documented explicitly in the
  relevant setup guide.
- Configuration (`configs/`) and dotfiles (`dotfiles/`) are version
  controlled; data volumes are not — they are backed up separately per
  [docs/runbooks/backup-restore.md](../runbooks/backup-restore.md).

## Volume Ownership Table

Actual volume names and mount paths are defined in the Compose files under
`workstation-bootstrap/` and documented per service in
[docs/setup/databases-services.md](../setup/databases-services.md)
to avoid duplication.

## References

- [Docker volumes documentation](https://docs.docker.com/storage/volumes/)

## Related Documents

- [docs/architecture/overview.md](./overview.md)
- [docs/setup/databases-services.md](../setup/databases-services.md)
- [docs/runbooks/backup-restore.md](../runbooks/backup-restore.md)
- [docs/runbooks/disaster-recovery.md](../runbooks/disaster-recovery.md)
