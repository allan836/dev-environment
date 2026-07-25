# Dotfiles

## Purpose

Placeholder for managed shell and developer-tool dotfiles (e.g. `.bashrc`,
`.gitconfig`, `.ssh/config` templates) deployed onto the workstation by
automation.

## Scope

Covers shell/tool startup and preference files. Does not cover application
configuration files — see [configs/README.md](../configs/README.md). Never
contains secret material (e.g. actual SSH private keys) — see
[docs/security/secrets-management.md](../docs/security/secrets-management.md).

## Prerequisites

- [docs/setup/git-github-ssh.md](../docs/setup/git-github-ssh.md)
- [docs/automation/ansible.md](../docs/automation/ansible.md)

## Status

**Not yet implemented.** Planned contents:

```text
dotfiles/
├── bashrc
├── gitconfig
└── ssh_config       Template only — no keys, no host-specific secrets
```

## References

- [ARCHITECTURE.md](../ARCHITECTURE.md)

## Related Documents

- [docs/setup/git-github-ssh.md](../docs/setup/git-github-ssh.md)
- [docs/security/ssh-key-management.md](../docs/security/ssh-key-management.md)
- [configs/README.md](../configs/README.md)
