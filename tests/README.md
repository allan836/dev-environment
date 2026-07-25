# Tests

## Purpose

Placeholder for automated verification tests covering scripts, Ansible
roles, and Compose stacks, so automation changes can be validated before
being applied to a real machine.

## Scope

Covers automation verification (linting, syntax checks, dry runs). Does not
cover manual verification steps for individual tools, which live in each
[docs/setup](../docs/setup/README.md) guide's "Verification" section.

## Prerequisites

- [docs/automation/README.md](../docs/automation/README.md)

## Status

**Not yet implemented.** Planned test types:

| Test Type | Target |
|---|---|
| `shellcheck` | All scripts under [scripts/](../scripts/README.md) and [bootstrap/](../bootstrap/README.md) |
| `ansible-lint` / `--syntax-check` | All content under [ansible/](../ansible/README.md) |
| `docker compose config` | All stacks under [docker/compose](../docker/compose/README.md) |

These will be wired into CI under [.github/workflows](../.github/workflows).

## References

- [ShellCheck](https://www.shellcheck.net/)
- [ansible-lint](https://ansible.readthedocs.io/projects/lint/)

## Related Documents

- [docs/automation/bash-scripts.md](../docs/automation/bash-scripts.md)
- [docs/automation/ansible.md](../docs/automation/ansible.md)
- [.github/workflows](../.github/workflows)
