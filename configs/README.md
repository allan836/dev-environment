# Configs

## Purpose

Placeholder for managed, version-controlled application and service
configuration files (e.g. VS Code settings, tool config files) that are
deployed onto the workstation by automation.

## Scope

Covers non-secret configuration files intended to be copied/templated onto
the host. Does not cover shell dotfiles — see
[dotfiles/README.md](../dotfiles/README.md). Does not cover secrets, which
are never stored here — see
[docs/security/secrets-management.md](../docs/security/secrets-management.md).

## Prerequisites

- [docs/automation/ansible.md](../docs/automation/ansible.md) for how these
  files will eventually be deployed.

## Status

**Not yet implemented.** Planned contents, one subdirectory per tool,
mirroring [docs/setup](../docs/setup/README.md) (e.g. `configs/vscode/`,
`configs/git/`).

## References

- [ARCHITECTURE.md](../ARCHITECTURE.md)

## Related Documents

- [dotfiles/README.md](../dotfiles/README.md)
- [templates/README.md](../templates/README.md)
- [docs/setup/ides.md](../docs/setup/ides.md)
