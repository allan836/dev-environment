# Contributing

## Purpose

Define how changes — documentation or automation — are proposed, reviewed,
and merged into this repository.

## Scope

Applies to all contributors, including the primary maintainer working solo.
Covers branching, commit conventions, review expectations, and documentation
standards. Does not cover release versioning semantics — see [CHANGELOG.md](./CHANGELOG.md).

## Prerequisites

- Read [README.md](./README.md) and [ARCHITECTURE.md](./ARCHITECTURE.md) first.
- Run `./provision.sh` to have a working local VM before making changes.
- Git and GitHub CLI are configured inside the VM automatically by provisioning.

## Workflow

1. Open an issue describing the problem or improvement before large changes.
2. Create a feature branch: `docs/<topic>`, `feat/<automation-area>`, or
   `fix/<issue>`.
3. Keep pull requests focused on a single concern.
4. Update related documentation in the same pull request as any automation
   change — documentation and code must never drift apart.
5. Request review; at least one approval required before merge (or
   self-review checklist below when working solo).

## Documentation Standards

- Written in Markdown, one topic per file.
- Every document includes: **Purpose, Scope, Prerequisites, References,
  Related documents**.
- Cross-reference existing documents instead of duplicating content.
- Keep language concise and professional; prefer tables and lists over prose.
- File names use lowercase kebab-case (e.g. `new-machine-bootstrap.md`).

## Automation Standards

- All scripts and playbooks must be idempotent (safe to re-run).
- Every automated task must have its manual fallback documented in the
  corresponding `docs/setup` guide.
- Every task must include a verification step.
- No secrets committed — see [docs/security/secrets-management.md](./docs/security/secrets-management.md).
- Shell scripts must pass `shellcheck`; Ansible content must pass `ansible-lint`.
- Changes to `ansible/roles/` must be tested by running the playbook
  inside the VM: `vagrant ssh -c "cd ~/dev-environment/ansible && ansible-playbook playbook.yml -i inventory/hosts.yml"`.
- Changes to `provision.sh` must be tested with `./provision.sh --destroy`
  to verify the full end-to-end flow.

## Commit Conventions

- Use [Conventional Commits](https://www.conventionalcommits.org/):
  `docs:`, `feat:`, `fix:`, `chore:`, `refactor:`.
- Reference related issues/ADRs in the commit body when relevant.

## Self-Review Checklist

- [ ] Document includes all five required sections.
- [ ] No duplicated content — cross-referenced instead.
- [ ] No secrets or machine-specific paths committed.
- [ ] Links to related documents resolve correctly.
- [ ] `CHANGELOG.md` updated for user-facing changes.

## References

- [Conventional Commits](https://www.conventionalcommits.org/)
- [Keep a Changelog](https://keepachangelog.com/)

## Related Documents

- [README.md](./README.md)
- [ARCHITECTURE.md](./ARCHITECTURE.md)
- [CHANGELOG.md](./CHANGELOG.md)
- [docs/security/secrets-management.md](./docs/security/secrets-management.md)
