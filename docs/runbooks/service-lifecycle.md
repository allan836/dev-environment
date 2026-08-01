# Runbook: Service Lifecycle

## Purpose

Describe the day-to-day operations for starting, stopping, rebuilding, and
verifying the kv-backend Docker services that run inside the developer VM.

## Scope

Covers lifecycle operations for the services managed by
`workstation-bootstrap/`. Does not cover backup/restore — see
[backup-restore.md](./backup-restore.md). Does not cover VM lifecycle (start
/ suspend / destroy) — see [new-machine-bootstrap.md](./new-machine-bootstrap.md).

## Prerequisites

- VM is running (use `./provision.sh` or start via your provider).
- Provisioning is complete: `./provision.sh` has been run at least once.

## Standard Operations

All commands below are run **inside the VM** via SSH
(`ssh -i ~/.ssh/dev-env ubuntu@<VM_IP>`), or by piping a command through
SSH. The Makefile target is the primary interface.

```bash
# SSH into the VM first
ssh -i ~/.ssh/dev-env ubuntu@<VM_IP>

# Navigate to the bootstrap directory
cd ~/dev-environment/workstation-bootstrap
```

### Start all services

```bash
make kv-up
```

Starts MySQL, RabbitMQ, Cassandra, Solr, Memcached, and Tomcat/portal via
Docker Compose. On first run this also builds any WARs that are not yet
built.

### First-time initialisation (run once after kv-up)

```bash
make kv-init
```

Runs the kv-backend database and Cassandra schema initialisation. Only
needed the first time, or after `make kv-clean-slate`.

### Check service status

```bash
make kv-status
# or
docker compose ps
```

### Verify services are reachable

```bash
make kv-verify
```

Checks that all service ports are accepting connections and prints a health
summary.

### View logs

```bash
make kv-logs              # follow all services
docker compose logs -f mysql   # a single service
```

### Stop services (preserving data)

```bash
docker compose down
```

Data volumes are preserved. `make kv-up` restarts from where it stopped.

### Clean slate — wipe and rebuild from zero

```bash
make kv-clean-slate
```

Destroys all volumes, removes containers, and triggers a fresh
`kv-up` + `kv-init`. Use this when databases are in a corrupt or unknown
state.

To seed from Uniserver instead of a local init:

```bash
make kv-clean-slate-remote
```

(Requires `UNISERVER_HOST`, `UNISERVER_USER`, `UNISERVER_DB_PASSWORD` in
`workstation-bootstrap/.env`.)

### Bring services down entirely

```bash
make kv-down
```

## Update Policy

Container image versions are pinned in
`kv-backend/preload-docker-compose/docker-compose.yml`. To update a service:

1. Change the pinned image tag.
2. Run `docker compose pull <service>`.
3. Run `docker compose up -d <service>`.
4. Verify with `make kv-verify`.

Never use `latest` tags — pinned versions keep the environment reproducible
and upgrades intentional.

## References

- [workstation-bootstrap/Makefile](../../workstation-bootstrap/Makefile)
- [workstation-bootstrap/scripts/kv-backend.sh](../../workstation-bootstrap/scripts/kv-backend.sh)

## Related Documents

- [backup-restore.md](./backup-restore.md)
- [new-machine-bootstrap.md](./new-machine-bootstrap.md)
- [docs/troubleshooting/docker.md](../troubleshooting/docker.md)
