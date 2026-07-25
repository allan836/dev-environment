# Git, GitHub, and SSH Setup

## Purpose

Configure Git identity, SSH key-based authentication, and GitHub CLI access
required for all source control operations on this workstation.

## Scope

Covers Git configuration, SSH key generation/management, and GitHub CLI
authentication. Does not cover repository-specific workflow — see
[CONTRIBUTING.md](../../CONTRIBUTING.md). Does not cover secret storage
policy — see [docs/security/ssh-key-management.md](../security/ssh-key-management.md).

## Prerequisites

- [docs/setup/fedora-base-setup.md](./fedora-base-setup.md) completed.

## Manual Installation Steps

1. Install Git and GitHub CLI:
   ```bash
   sudo dnf install -y git gh
   ```
2. Configure Git identity:
   ```bash
   git config --global user.name "Your Name"
   git config --global user.email "you@example.com"
   git config --global init.defaultBranch main
   ```
3. Generate an SSH key (Ed25519 recommended):
   ```bash
   ssh-keygen -t ed25519 -C "you@example.com" -f ~/.ssh/id_ed25519
   ```
4. Add the key to the SSH agent and `~/.ssh/config`, then add the public key
   to GitHub via `gh auth login` or the GitHub web UI.

## Configuration

- Recommended `~/.gitconfig` additions (aliases, `pull.rebase`) are managed
  as a dotfile — see [dotfiles/README.md](../../dotfiles/README.md).
- SSH client configuration (`~/.ssh/config`) is also managed as a dotfile;
  private keys themselves are **never** committed — see
  [docs/security/ssh-key-management.md](../security/ssh-key-management.md).

## Verification

```bash
git config --list --global
ssh -T git@github.com
gh auth status
```
Confirms Git identity, SSH authentication to GitHub, and CLI auth state.

## Automation Status

Not yet automated. Planned as an Ansible role covering package install and
dotfile deployment; SSH key generation remains a manual, human-in-the-loop
step by design (see [docs/security/ssh-key-management.md](../security/ssh-key-management.md)).

## References

- [GitHub Docs: Connecting with SSH](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)
- [GitHub CLI Manual](https://cli.github.com/manual/)

## Related Documents

- [docs/setup/fedora-base-setup.md](./fedora-base-setup.md)
- [docs/security/ssh-key-management.md](../security/ssh-key-management.md)
- [CONTRIBUTING.md](../../CONTRIBUTING.md)
- [dotfiles/README.md](../../dotfiles/README.md)
