# Containerized Databases & Services

## Purpose

Document the containerized local services available on this workstation:
data stores, messaging, and the local AI stack. Serve as the authoritative
reference for default ports, credentials handling, and persistence per
service.

## Scope

Covers PostgreSQL, MySQL, MongoDB, Cassandra, Redis, RabbitMQ, Neo4j,
Qdrant, Ollama, and Open WebUI as Docker/Podman Compose services. Does not
cover the container runtime itself — see [docs/setup/docker.md](./docker.md)
and [docs/setup/podman.md](./podman.md). Does not cover backup procedures —
see [docs/runbooks/backup-restore.md](../runbooks/backup-restore.md).

## Prerequisites

- [docs/setup/docker.md](./docker.md) (or [podman.md](./podman.md)) completed.
- [docs/architecture/networking.md](../architecture/networking.md) and
  [docs/architecture/storage.md](../architecture/storage.md) read for the
  design rationale behind ports and volumes.

## Service Reference

| Service | Purpose | Default Port | Persistent Volume |
|---|---|---|---|
| PostgreSQL | Primary relational database | 5432 | Yes |
| MySQL | Relational database (MySQL-compatible workloads) | 3306 | Yes |
| MongoDB | Document database | 27017 | Yes |
| Cassandra | Wide-column distributed database | 9042 | Yes |
| Redis | In-memory cache / data structure store | 6379 | Optional (cache by default, see [docs/architecture/storage.md](../architecture/storage.md)) |
| RabbitMQ | Message broker | 5672 (AMQP), 15672 (mgmt UI) | Yes |
| Neo4j | Graph database | 7474 (HTTP), 7687 (Bolt) | Yes |
| Qdrant | Vector database | 6333 (HTTP), 6334 (gRPC) | Yes |
| Ollama | Local LLM runtime | 11434 | Yes (model storage) |
| Open WebUI | Web UI for Ollama-backed chat | 8080 | Yes (app state) |

All ports above are workstation defaults, bound to `127.0.0.1` unless a
guide-specific reason requires wider exposure, per
[docs/architecture/networking.md](../architecture/networking.md).

## Manual Startup (Pattern)

Each service will have a Compose file under [docker/compose](../../docker/compose)
(e.g. `docker/compose/postgres.yml`). The general pattern, once implemented:

```bash
docker compose -f docker/compose/<service>.yml up -d
```

Until Compose files are implemented (see [ROADMAP.md](../../ROADMAP.md)),
services may be started manually with `docker run`, referencing the port and
volume conventions in the table above.

## Configuration

- Credentials (database passwords, RabbitMQ users) are supplied via
  environment variables sourced from an untracked `.env` file — never
  committed. See [docs/security/secrets-management.md](../security/secrets-management.md).
- The AI stack (Ollama, Open WebUI, Qdrant) is typically run together as one
  Compose project since Open WebUI depends on both.

## Verification

- **PostgreSQL:** `pg_isready -h 127.0.0.1 -p 5432`
- **MySQL:** `mysqladmin ping -h 127.0.0.1 -P 3306`
- **MongoDB:** `mongosh --eval "db.adminCommand('ping')"`
- **Cassandra:** `cqlsh 127.0.0.1 9042 -e "describe cluster"`
- **Redis:** `redis-cli -h 127.0.0.1 ping`
- **RabbitMQ:** management UI at `http://127.0.0.1:15672`
- **Neo4j:** browser at `http://127.0.0.1:7474`
- **Qdrant:** `curl http://127.0.0.1:6333/readyz`
- **Ollama:** `curl http://127.0.0.1:11434/api/tags`
- **Open WebUI:** browser at `http://127.0.0.1:8080`

## Automation Status

Not yet automated. Compose files for each service are planned in
[docker/compose](../../docker/compose) — see
[docs/automation/docker-compose.md](../automation/docker-compose.md) and
[ROADMAP.md](../../ROADMAP.md) Phase 3.

## References

- [Docker Hub official images](https://hub.docker.com/search?q=&image_filter=official)
- [Ollama documentation](https://github.com/ollama/ollama)
- [Open WebUI documentation](https://docs.openwebui.com/)
- [Qdrant documentation](https://qdrant.tech/documentation/)

## Related Documents

- [docs/architecture/networking.md](../architecture/networking.md)
- [docs/architecture/storage.md](../architecture/storage.md)
- [docs/automation/docker-compose.md](../automation/docker-compose.md)
- [docs/runbooks/backup-restore.md](../runbooks/backup-restore.md)
- [docs/security/secrets-management.md](../security/secrets-management.md)
