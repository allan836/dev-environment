# Troubleshooting

## Purpose

Index of known issues and their resolutions, organized by subsystem, to
speed up diagnosis instead of re-solving the same problem repeatedly.

## Scope

Covers issue diagnosis and resolution. Does not cover installation
procedures — see [docs/setup](../setup/README.md). Does not cover planned
operational procedures — see [docs/runbooks](../runbooks/README.md).

## Prerequisites

- None specific; consult the relevant [docs/setup](../setup/README.md) guide
  first to confirm correct installation before assuming a bug.

## Contents

| Document | Covers |
|---|---|
| [docker.md](./docker.md) | Docker daemon, permissions, container issues |
| [kubernetes.md](./kubernetes.md) | `kubectl`, local cluster issues |
| [networking.md](./networking.md) | Port conflicts, container networking, firewall |

## Contribution Convention

Each entry follows: **Symptom → Cause → Resolution → Prevention**. Add new
entries as they are discovered — this is a living knowledge base per
[ARCHITECTURE.md](../../ARCHITECTURE.md) principle of documentation as code.

## References

- [ARCHITECTURE.md](../../ARCHITECTURE.md)

## Related Documents

- [docs/setup/README.md](../setup/README.md)
- [docs/runbooks/README.md](../runbooks/README.md)
