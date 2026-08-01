# Architecture Decision Records (ADRs)

## Purpose

Record architecturally significant decisions made for this workstation and
repository, along with the context and alternatives considered, so future
maintainers understand *why*, not just *what*.

## Scope

Covers decisions that affect repository structure, technology choices, or
automation approach. Does not record routine implementation details — those
belong in the relevant [docs/setup](../setup/README.md) or
[docs/automation](../automation/README.md) document.

## Prerequisites

- [ARCHITECTURE.md](../../ARCHITECTURE.md) for the principles decisions
  must align with.

## Index

| ADR | Title | Status |
|---|---|---|
| [0001](./0001-use-fedora-as-base-os.md) | Use Fedora Workstation as the base OS | Superseded by 0002 |
| [0002](./0002-use-ubuntu-vm-via-vagrant.md) | Use Ubuntu 24.04 VM via Vagrant as the developer environment | Superseded by 0003 |
| [0003](./0003-replace-vagrant-with-multipass-libvirt-incus.md) | Replace Vagrant with Multipass / libvirt / Incus providers | Accepted |

## ADR Process

1. Copy the template below into a new file `NNNN-short-title.md`
   (zero-padded, sequential).
2. Fill in all sections.
3. Submit via pull request per [CONTRIBUTING.md](../../CONTRIBUTING.md).
4. Add a row to the index table above.

## Template

```markdown
# NNNN. <Title>

## Status
Proposed | Accepted | Superseded by [NNNN](./NNNN-title.md) | Deprecated

## Context
What problem or question prompted this decision?

## Decision
What was decided.

## Alternatives Considered
What else was evaluated, and why it was not chosen.

## Consequences
Resulting trade-offs, positive and negative.

## Related Documents
Links to affected setup/architecture docs.
```

## References

- [Architecture Decision Records (ADR)](https://adr.github.io/)

## Related Documents

- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [docs/architecture/README.md](../architecture/README.md)
