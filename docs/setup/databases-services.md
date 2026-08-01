# kv-backend Services

## Purpose

Reference guide for the containerized services that make up the kv-backend
local development environment.

## Scope

Covers the seven Docker Compose services started by `make kv-up`. Does not
cover the container runtime itself — see [docker.md](./docker.md). Does not
cover backup procedures — see
[docs/runbooks/backup-restore.md](../runbooks/backup-restore.md).

## Prerequisites

- Developer VM is running and provisioned (`./provision.sh` completed).
- SSH into the VM: `ssh -i ~/.ssh/dev-env ubuntu@<VM_IP>`.
- kv-backend is cloned at `~/workspace/repos/kv-backend`.

## Service Reference

All services are started together with `make kv-up` from
`~/dev-environment/workstation-bootstrap/`. They are part of kv-backend's
own `preload-docker-compose` stack.

| Service | Port | Purpose |
|---|---|---|
| MySQL | 43306 | kv-backend relational database |
| RabbitMQ | 35672 (AMQP), 45672 (management UI) | Message broker |
| Cassandra | 59042 | Time-series / wide-column data |
| Solr | 58983 | Full-text search |
| Memcached | 41211 | Cache / session store |
| MailHog | 1025 (SMTP), 8025 (web UI) | Local mail catcher — captures outbound email |
| Tomcat / portal | 8080 | kv-backend portal application |

> Ports are non-standard (prefixed with 4x/5x) to avoid conflicts with
> any natively running services on the host.

## Starting and managing services

```bash
cd ~/dev-environment/workstation-bootstrap

make kv-up          # start all services (loads preload images on first run)
make kv-init        # FIRST TIME ONLY — initialises MySQL schema + Cassandra keyspaces
make kv-verify      # check all service ports are reachable
make kv-status      # docker compose ps
make kv-logs        # follow logs for all services
make kv-down        # stop all services (data volumes preserved)
make kv-clean-slate # wipe all volumes and rebuild from zero
```

## Preload Docker images

kv-backend's services use pre-built images (`kv_rabbitmq:preload_v1`,
`kv_cassandra:preload_v1`, `kv_portal:preload_v1`). These are loaded from
the tarball at `assets/preload_kv.tar.gz` (~754 MB).

`make kv-up` runs `docker load` automatically on first run. Subsequent runs
skip this since the images are already in Docker's image store.

## Configuration

Credentials and paths are in `workstation-bootstrap/.env` (created from
`.env.example` on first run by `setup.sh`). Key variables:

```bash
KV_BACKEND_DIR=~/workspace/repos/kv-backend
KV_PRELOAD_TAR=../assets/preload_kv.tar.gz
```

## Verification

```bash
make kv-verify
```

Checks that every service port is accepting connections and prints a health
summary.

## Clean slate (broken or unknown state)

```bash
make kv-clean-slate
# Destroys all volumes, removes containers, reruns kv-up + kv-init
```

To seed from Uniserver instead of local init (requires Uniserver
credentials in `.env`):

```bash
make kv-clean-slate-remote
```

## References

- [workstation-bootstrap/Makefile](../../workstation-bootstrap/Makefile)
- [workstation-bootstrap/scripts/kv-backend.sh](../../workstation-bootstrap/scripts/kv-backend.sh)

## Related Documents

- [docs/runbooks/service-lifecycle.md](../runbooks/service-lifecycle.md)
- [docs/runbooks/backup-restore.md](../runbooks/backup-restore.md)
- [docs/troubleshooting/docker.md](../troubleshooting/docker.md)
