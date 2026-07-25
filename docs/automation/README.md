# Automation Documentation

## Purpose

Index and entry point for documentation describing how automation in this
repository is designed and organized across Bash, Ansible, and Docker
Compose.

## Scope

Covers the design and conventions of the automation layer. Does not contain
the automation itself yet — see [ROADMAP.md](../../ROADMAP.md) for
implementation status. Does not cover manual setup steps — see
[docs/setup](../setup/README.md).

## Prerequisites

- [ARCHITECTURE.md](../../ARCHITECTURE.md) for the guiding principles
  (idempotency, manual fallback, verification steps).

## Contents

| Document | Description |
|---|---|
| [bash-scripts.md](./bash-scripts.md) | Bootstrap and utility script conventions |
| [ansible.md](./ansible.md) | Role structure, inventory, and playbook conventions |
| [docker-compose.md](./docker-compose.md) | Compose stack organization for local services |

## Automation Directory Map

| Repository Path | Purpose |
|---|---|
| [bootstrap/](../../bootstrap/README.md) | Single entry point to bootstrap a new machine |
| [scripts/](../../scripts/README.md) | Standalone utility scripts |
| [ansible/](../../ansible) | Playbooks, roles, and inventory |
| [docker/compose/](../../docker/compose) | Compose files per service/stack |
| [tests/](../../tests/README.md) | Verification tests for automation |

## References

- [ARCHITECTURE.md](../../ARCHITECTURE.md)

## Related Documents

- [docs/setup/README.md](../setup/README.md)
- [docs/runbooks/new-machine-bootstrap.md](../runbooks/new-machine-bootstrap.md)
- [ROADMAP.md](../../ROADMAP.md)
