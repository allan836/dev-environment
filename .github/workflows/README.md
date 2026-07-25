# GitHub Actions Workflows

## Purpose

Placeholder for CI workflows that validate documentation and automation
changes on every pull request.

## Scope

Covers CI pipeline definitions. Does not implement the checks themselves —
see [tests/README.md](../../tests/README.md) and [tools/README.md](../../tools/README.md)
for what will be run.

## Prerequisites

- [CONTRIBUTING.md](../../CONTRIBUTING.md)

## Status

**Not yet implemented.** Planned workflows:

| Planned Workflow | Purpose |
|---|---|
| `lint-docs.yml` | Markdown lint + link check on `docs/**` |
| `lint-shell.yml` | `shellcheck` on `scripts/**`, `bootstrap/**` |
| `lint-ansible.yml` | `ansible-lint` / syntax-check on `ansible/**` |
| `validate-compose.yml` | `docker compose config` on `docker/compose/**` |

## References

- [GitHub Actions documentation](https://docs.github.com/en/actions)

## Related Documents

- [tests/README.md](../../tests/README.md)
- [tools/README.md](../../tools/README.md)
- [CONTRIBUTING.md](../../CONTRIBUTING.md)
