# Ansible Inventory

## Purpose

Placeholder for the Ansible inventory defining the (single, local) host this
automation targets.

## Scope

Covers inventory structure for a single-workstation, local-connection setup.
Does not cover multi-host fleet management, which is out of scope for this
repository.

## Prerequisites

- [docs/automation/ansible.md](../../docs/automation/ansible.md)

## Status

**Not yet implemented.** Planned contents:

```text
inventory/
└── hosts.ini    Single-host, local-connection inventory
                   (localhost ansible_connection=local)
```

## References

- [Ansible inventory documentation](https://docs.ansible.com/ansible/latest/inventory_guide/index.html)

## Related Documents

- [ansible/README.md](../README.md)
- [ansible/roles/README.md](../roles/README.md)
