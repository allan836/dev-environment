# Ansible Automation Conventions

## Purpose

Define how Ansible will be structured once implemented: role boundaries,
inventory approach, and idempotency expectations, so future automation is
consistent and maintainable.

## Scope

Covers content under [ansible/](../../ansible). Does not cover Bash scripts
(see [docs/automation/bash-scripts.md](./bash-scripts.md)) or Compose stacks
(see [docs/automation/docker-compose.md](./docker-compose.md)).

## Prerequisites

- [ARCHITECTURE.md](../../ARCHITECTURE.md) principles: declarative
  infrastructure, idempotency, manual fallback, verification.

## Planned Structure

```text
ansible/
├── roles/            One role per tool or logical group, mirroring
│                      docs/setup/*.md guides (e.g. roles/docker,
│                      roles/languages, roles/cloud-clis).
├── inventory/         Single-host inventory for this workstation
│                      (localhost, connection: local).
└── site.yml            Top-level playbook (to be added) tying roles
                          together, invoked by bootstrap/bootstrap.sh.
```

## Role Design Rules

- One role per concern, matching the corresponding guide in
  [docs/setup](../setup/README.md) (e.g. `roles/docker` implements what
  [docs/setup/docker.md](../setup/docker.md) documents manually).
- Roles use built-in idempotent modules (`dnf`, `copy`, `template`, `service`)
  rather than raw `command`/`shell` where possible.
- Where `command`/`shell` is unavoidable, a `creates`/`changed_when` guard is
  required to preserve idempotency.
- Every role includes a verification task (e.g. checking a binary's
  `--version` output) mirroring the "Verification" section of its
  corresponding setup guide.
- Variables that differ per environment live in `inventory/`, not hardcoded
  in roles.
- No secrets in role defaults or `vars/` — see
  [docs/security/secrets-management.md](../security/secrets-management.md)
  for the vault/env-based approach to be used.

## Execution Model

Single-host, local-connection inventory (this is a workstation, not a
fleet). Playbooks are expected to be run via `ansible-playbook site.yml`
from the bootstrap entry point — see
[bootstrap/README.md](../../bootstrap/README.md).

## References

- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html)
- [ansible-lint](https://ansible.readthedocs.io/projects/lint/)

## Related Documents

- [ansible/roles/README.md](../../ansible/roles/README.md)
- [ansible/inventory/README.md](../../ansible/inventory/README.md)
- [docs/setup/README.md](../setup/README.md)
- [bootstrap/README.md](../../bootstrap/README.md)
