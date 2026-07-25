# Bootstrap

## Purpose

Placeholder for the single entry-point script that will bootstrap a fresh
Fedora Workstation install into a fully configured developer workstation.

## Scope

Covers the top-level orchestration entry point only (`bootstrap.sh`, once
implemented). Does not contain individual tool installation logic — that
will live in [ansible/roles](../ansible/roles/README.md). Does not contain
general-purpose utilities — see [scripts/](../scripts/README.md).

## Prerequisites

- Fedora Workstation freshly installed.
- Read [docs/runbooks/new-machine-bootstrap.md](../docs/runbooks/new-machine-bootstrap.md)
  for the current (manual) procedure this directory will eventually replace.

## Status

**Not yet implemented.** No scripts exist here yet. Planned contents:

```text
bootstrap/
└── bootstrap.sh    Entry point: checks prerequisites, installs Ansible if
                      needed, and runs ansible/site.yml.
```

See [docs/automation/bash-scripts.md](../docs/automation/bash-scripts.md)
for the conventions this script will follow, and [ROADMAP.md](../ROADMAP.md)
Phase 1 for status.

## References

- [ARCHITECTURE.md](../ARCHITECTURE.md)

## Related Documents

- [docs/runbooks/new-machine-bootstrap.md](../docs/runbooks/new-machine-bootstrap.md)
- [docs/automation/bash-scripts.md](../docs/automation/bash-scripts.md)
- [ansible/README.md](../ansible/README.md)
