# Docker Compose Stacks

## Purpose

Placeholder for the Docker Compose files defining local containerized
services, grouped by concern.

## Scope

Covers Compose file organization only. Does not cover per-service ports,
volumes, or verification — see
[docs/setup/databases-services.md](../../docs/setup/databases-services.md).

## Prerequisites

- [docs/automation/docker-compose.md](../../docs/automation/docker-compose.md)

## Status

**Not yet implemented.** Planned files:

| Planned File | Services |
|---|---|
| `data-stack.yml` | PostgreSQL, MySQL, MongoDB, Cassandra, Redis |
| `messaging-stack.yml` | RabbitMQ, Neo4j |
| `ai-stack.yml` | Ollama, Open WebUI, Qdrant |
| `.env.example` | Non-secret template for required environment variables |

## References

- [docs/automation/docker-compose.md](../../docs/automation/docker-compose.md)

## Related Documents

- [docker/README.md](../README.md)
- [docs/setup/databases-services.md](../../docs/setup/databases-services.md)
- [docs/security/secrets-management.md](../../docs/security/secrets-management.md)
