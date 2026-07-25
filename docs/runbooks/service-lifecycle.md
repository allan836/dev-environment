# Runbook: Service Lifecycle

## Purpose

Describe the day-to-day operations of starting, stopping, updating, and
tearing down containerized local services.

## Scope

Covers lifecycle operations for the services defined in
[docs/setup/databases-services.md](../setup/databases-services.md). Does not
cover backup/restore — see
[docs/runbooks/backup-restore.md](./backup-restore.md).

## Prerequisites

- [docs/setup/docker.md](../setup/docker.md) completed.
- Compose stacks present under [docker/compose](../../docker/compose)
  (planned — see [ROADMAP.md](../../ROADMAP.md)).

## Standard Operations (Pattern)

Once Compose stacks are implemented, the standard pattern will be:

```bash
# Start a stack
docker compose -f docker/compose/<stack>.yml up -d

# Check status
docker compose -f docker/compose/<stack>.yml ps

# View logs
docker compose -f docker/compose/<stack>.yml logs -f <service>

# Update to a new pinned image version
docker compose -f docker/compose/<stack>.yml pull
docker compose -f docker/compose/<stack>.yml up -d

# Stop (preserving volumes/data)
docker compose -f docker/compose/<stack>.yml down

# Full teardown (destroys data — confirm backups first)
docker compose -f docker/compose/<stack>.yml down -v
```

## Update Policy

Image versions are pinned explicitly (see
[docs/automation/docker-compose.md](../automation/docker-compose.md)).
Updating a service means deliberately bumping the pinned tag in the Compose
file, not relying on `latest`, so upgrades are reviewed and reversible.

## Verification After Any Lifecycle Change

Always re-run the relevant verification command from
[docs/setup/databases-services.md](../setup/databases-services.md) after
starting or updating a service.

## References

- [Docker Compose CLI reference](https://docs.docker.com/reference/cli/docker/compose/)

## Related Documents

- [docs/setup/databases-services.md](../setup/databases-services.md)
- [docs/automation/docker-compose.md](../automation/docker-compose.md)
- [docs/runbooks/backup-restore.md](./backup-restore.md)
