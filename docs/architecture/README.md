# Architecture Documentation

## Purpose

Index and entry point for system design documentation describing how the
developer environment is structured and why.

## Scope

Covers system-level design: the VM provisioning model, layering, networking,
storage, and technology selection rationale. Does not cover step-by-step
installation (see [docs/setup](../setup/README.md)) or day-to-day operations
(see [docs/runbooks](../runbooks/README.md)).

## Prerequisites

- Read [ARCHITECTURE.md](../../ARCHITECTURE.md) for repository-wide
  philosophy before reading these documents.

## Contents

| Document | Description |
|---|---|
| [overview.md](./overview.md) | Layered system overview: host → VM → tools → services |
| [networking.md](./networking.md) | Host/VM/container networking and port allocation |
| [storage.md](./storage.md) | Data persistence strategy for containerized services |

## References

- [C4 Model](https://c4model.com/) for describing software architecture.

## Related Documents

- [ARCHITECTURE.md](../../ARCHITECTURE.md) — repository philosophy.
- [docs/decisions/README.md](../decisions/README.md) — decision records.
- [docs/setup/README.md](../setup/README.md) — implementation-level guides.
- [docs/automation/README.md](../automation/README.md) — how automation is built.
