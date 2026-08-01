# Automation Documentation

## Purpose

Index and entry point for documentation describing how automation in this
repository is designed, organized, and used.

## Scope

Covers the design and conventions of the automation layer: the VM
provisioner, Ansible roles, Bash scripts, and Docker Compose stacks.
Does not cover manual setup steps — see [docs/setup](../setup/README.md).

## Prerequisites

- [ARCHITECTURE.md](../../ARCHITECTURE.md) for guiding principles
  (idempotency, manual fallback, verification steps).

## Contents

| Document | Description |
|---|---|
| [bash-scripts.md](./bash-scripts.md) | `provision.sh` and utility script conventions |
| [ansible.md](./ansible.md) | Role structure, inventory, and playbook conventions |
| [docker-compose.md](./docker-compose.md) | Compose stack conventions for local services |

## Automation Directory Map

| Repository Path | Purpose | Status |
|---|---|---|
| [`provision.sh`](../../provision.sh) | Single entry point — installs Vagrant, hypervisor, boots VM, runs Ansible | **Implemented** |
| [`vm/Vagrantfile`](../../vm/Vagrantfile) | Multi-provider VM definition (VirtualBox / KVM / VMware) | **Implemented** |
| [`vm/cloud-init/`](../../vm/cloud-init/) | First-boot OS config (user, SSH, packages) | **Implemented** |
| [`ansible/`](../../ansible/) | Playbooks, roles, and inventory | **Implemented** |
| [`workstation-bootstrap/`](../../workstation-bootstrap/) | Direct host bootstrap (no VM) for existing Ubuntu/macOS machines | **Implemented** |
| [`docker/compose/`](../../docker/compose/) | General-purpose Compose stacks for AI/data services | Planned — Phase 3 |
| `scripts/` | Standalone utility scripts (backup, health checks) | Planned — Phase 5 |
| `tests/` | Verification tests for automation | Planned — Phase 4 |

## How it all fits together

```
provision.sh  (host)
    │
    ├── installs Vagrant (apt/brew/dnf)
    ├── installs hypervisor (VirtualBox → KVM → VMware, first success wins)
    │
    └── vagrant up (vm/Vagrantfile)
            │
            ├── cloud-init (vm/cloud-init/user-data)  — first boot OS setup
            │
            └── ansible_local (ansible/playbook.yml)  — tool installation
                    ├── roles/docker
                    ├── roles/java
                    ├── roles/node
                    ├── roles/python
                    ├── roles/terraform
                    ├── roles/kubectl
                    ├── roles/cloud_clis
                    ├── roles/developer_tools
                    └── roles/kv_backend
```

After provisioning, day-to-day service management uses the Makefile in
`workstation-bootstrap/` (see [service-lifecycle.md](../runbooks/service-lifecycle.md)).

## References

- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [ROADMAP.md](../../ROADMAP.md)

## Related Documents

- [docs/setup/README.md](../setup/README.md)
- [docs/runbooks/new-machine-bootstrap.md](../runbooks/new-machine-bootstrap.md)
- [ROADMAP.md](../../ROADMAP.md)
