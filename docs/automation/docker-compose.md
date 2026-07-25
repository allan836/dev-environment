# Docker Compose Automation Conventions

## Purpose

Define how local containerized services will be organized as Docker Compose
stacks once implemented, so services are consistent, isolated, and easy to
manage individually.

## Scope

Covers content under [docker/compose](../../docker/compose). Does not cover
container runtime installation — see [docs/setup/docker.md](../setup/docker.md)
and [docs/setup/podman.md](../setup/podman.md). Does not cover per-service
port/volume reference — see [docs/setup/databases-services.md](../setup/databases-services.md).

## Prerequisites

- [docs/setup/docker.md](../setup/docker.md) completed.
- [docs/architecture/networking.md](../architecture/networking.md) and
  [docs/architecture/storage.md](../architecture/storage.md) read.

## Planned Structure

```text
docker/
├── compose/
│   ├── data-stack.yml       PostgreSQL, MySQL, MongoDB, Cassandra, Redis
│   ├── messaging-stack.yml  RabbitMQ, Neo4j
│   └── ai-stack.yml         Ollama, Open WebUI, Qdrant
└── <service>/                Dockerfiles/config for services needing
                                 customization beyond the official image.
```
Stacks are grouped by concern (data, messaging, AI) rather than one giant
file, so individual stacks can be started/stopped independently.

## Design Rules

- Every service uses an official upstream image pinned to a specific
  version tag (never `latest`), for reproducibility.
- Every stateful service uses a named volume per
  [docs/architecture/storage.md](../architecture/storage.md).
- Credentials are injected via environment variables read from an untracked
  `.env` file — see [docs/security/secrets-management.md](../security/secrets-management.md).
- Ports are bound to `127.0.0.1` by default per
  [docs/architecture/networking.md](../architecture/networking.md).
- Every stack includes healthchecks so `docker compose ps` reflects real
  service readiness, satisfying the "every installation has a verification
  step" principle in [ARCHITECTURE.md](../../ARCHITECTURE.md).

## References

- [Compose file reference](https://docs.docker.com/reference/compose-file/)

## Related Documents

- [docs/setup/databases-services.md](../setup/databases-services.md)
- [docs/architecture/networking.md](../architecture/networking.md)
- [docs/architecture/storage.md](../architecture/storage.md)
- [docker/README.md](../../docker/README.md)
- [docker/compose/README.md](../../docker/compose/README.md)
