# Docker Compose

## Purpose

Document how Docker Compose is used for local developer services in this
repository.

## Scope

Covers the working Compose stack in `workstation-bootstrap/` (kv-backend
services), and the planned general-purpose stacks under `docker/compose/`.
Does not cover Docker Engine installation — that is handled by the Ansible
`docker` role (see [ansible.md](./ansible.md)).

## Prerequisites

- Docker is installed inside the VM (via Ansible `docker` role).
- The developer VM is running: `cd vm && vagrant up`.

## Working Compose stack: kv-backend services

The `workstation-bootstrap/` directory contains the working Compose
configuration for the kv-backend local development environment. It is
managed via the Makefile:

```bash
cd ~/dev-environment/workstation-bootstrap

make kv-up          # docker compose up -d (builds WARs on first run)
make kv-init        # first-time DB/Cassandra/Solr initialisation
make kv-verify      # check all service ports are reachable
make kv-status      # docker compose ps
make kv-logs        # docker compose logs -f
make kv-down        # docker compose down
make kv-clean-slate # wipe volumes and rebuild from zero
```

Services started by `make kv-up`:

| Service | Port | Technology |
|---|---|---|
| MySQL | 3306 | kv-backend relational DB |
| RabbitMQ | 5672 / 15672 | Message broker + management UI |
| Cassandra | 9042 | Time-series / wide-column data |
| Solr | 8983 | Full-text search |
| Memcached | 11211 | Session/cache store |
| MailHog | 1025 / 8025 | Local mail catcher |
| Tomcat/portal | 8080 | kv-backend portal (built from source) |

## Design rules (applied to kv-backend stack and future stacks)

- **Pinned image versions** — never `latest`. Versions are explicitly set
  in the Compose file so upgrades are deliberate and reversible.
- **Named volumes** for all stateful services — no bind-mounts for data
  (bind-mounts are only used for config files).
- **`:Z` SELinux labels** on bind-mounts for Fedora host compatibility.
- **`127.0.0.1` port binding** — services are not exposed beyond the VM's
  host interface by default.
- **Healthchecks** on every stateful service — `docker compose ps` reflects
  real readiness, not just container start.
- **`.env` for credentials** — never hardcoded in the Compose file.
  See [docs/security/secrets-management.md](../security/secrets-management.md).

## Planned general-purpose stacks (Phase 3)

Once implemented, general-purpose Compose stacks will live under
`docker/compose/`:

```text
docker/compose/
├── data-stack.yml       PostgreSQL, MySQL, MongoDB, Cassandra, Redis
├── messaging-stack.yml  RabbitMQ, Neo4j
└── ai-stack.yml         Ollama, Open WebUI, Qdrant
```

These will be independent of kv-backend and usable for any project.
See [ROADMAP.md](../../ROADMAP.md) Phase 3 for status.

## References

- [Compose file reference](https://docs.docker.com/reference/compose-file/)
- [workstation-bootstrap/Makefile](../../workstation-bootstrap/Makefile)

## Related Documents

- [docs/runbooks/service-lifecycle.md](../runbooks/service-lifecycle.md)
- [docs/architecture/networking.md](../architecture/networking.md)
- [docs/architecture/storage.md](../architecture/storage.md)
