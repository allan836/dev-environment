# Bash Scripting Conventions

## Purpose

Define the conventions Bash scripts in this repository must follow once
implemented, so they remain idempotent, readable, and safe to re-run.

## Scope

Covers scripts under [bootstrap/](../../bootstrap/README.md) and
[scripts/](../../scripts/README.md). Does not cover Ansible content — see
[docs/automation/ansible.md](./ansible.md).

## Prerequisites

- [ARCHITECTURE.md](../../ARCHITECTURE.md) principles: idempotency,
  verification, manual fallback.

## Conventions (to apply once scripts are implemented)

- Every script starts with `set -euo pipefail`.
- Scripts are idempotent: safe to run multiple times without duplicating
  work or failing on already-applied state.
- Every script performs a check step before making changes (e.g. "is this
  package already installed?") and a verification step after.
- Scripts pass `shellcheck` with no warnings (enforced in CI, see
  [.github/workflows](../../.github/workflows)).
- `bootstrap/` contains only the single top-level entry point that
  orchestrates the overall setup (e.g. calling Ansible); `scripts/` contains
  smaller, independently runnable utilities (e.g. health checks, backups).
- No hardcoded secrets — see [docs/security/secrets-management.md](../security/secrets-management.md).
- Scripts print clear, actionable output on both success and failure.

## Naming

- Lowercase kebab-case, `.sh` extension, verb-first names
  (e.g. `bootstrap.sh`, `verify-docker.sh`, `backup-postgres.sh`).

## References

- [ShellCheck](https://www.shellcheck.net/)
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)

## Related Documents

- [bootstrap/README.md](../../bootstrap/README.md)
- [scripts/README.md](../../scripts/README.md)
- [docs/automation/README.md](./README.md)
- [tests/README.md](../../tests/README.md)
