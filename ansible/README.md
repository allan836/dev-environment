# Ansible

## Purpose

Placeholder for Ansible playbooks, roles, and inventory that will automate
host- and tooling-layer configuration on this workstation.

## Scope

Covers declarative configuration management for the host and tooling
layers. Does not cover containerized services — see
[docker/README.md](../docker/README.md). Does not cover the bootstrap entry
point that will invoke this automation — see
[bootstrap/README.md](../bootstrap/README.md).

## Prerequisites

- [docs/automation/ansible.md](../docs/automation/ansible.md) for role
  structure and design rules.

## Status

**Not yet implemented.** Planned top-level contents:

```text
ansible/
├── site.yml           Top-level playbook (not yet created)
├── roles/              See roles/README.md
└── inventory/           See inventory/README.md
```

## References

- [docs/automation/ansible.md](../docs/automation/ansible.md)

## Related Documents

- [ansible/roles/README.md](./roles/README.md)
- [ansible/inventory/README.md](./inventory/README.md)
- [bootstrap/README.md](../bootstrap/README.md)
- [docs/setup/README.md](../docs/setup/README.md)
