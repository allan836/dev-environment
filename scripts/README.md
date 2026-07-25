# Scripts

## Purpose

Placeholder for standalone Bash utility scripts (verification, backup,
maintenance) that are independent of the main bootstrap flow.

## Scope

Covers small, independently runnable utilities. Does not cover the top-level
bootstrap entry point — see [bootstrap/](../bootstrap/README.md). Does not
cover Ansible automation — see [ansible/](../ansible/README.md).

## Prerequisites

- [docs/automation/bash-scripts.md](../docs/automation/bash-scripts.md) for
  conventions these scripts must follow.

## Status

**Not yet implemented.** Planned scripts, mapped to the runbooks they
support:

| Planned Script | Supports |
|---|---|
| `verify-docker.sh` | [docs/setup/docker.md](../docs/setup/docker.md) verification |
| `verify-services.sh` | [docs/setup/databases-services.md](../docs/setup/databases-services.md) verification |
| `backup-databases.sh` | [docs/runbooks/backup-restore.md](../docs/runbooks/backup-restore.md) |

## References

- [docs/automation/bash-scripts.md](../docs/automation/bash-scripts.md)

## Related Documents

- [bootstrap/README.md](../bootstrap/README.md)
- [docs/runbooks/backup-restore.md](../docs/runbooks/backup-restore.md)
- [tests/README.md](../tests/README.md)
