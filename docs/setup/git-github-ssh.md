# Git, GitHub, and SSH Setup

## Purpose

Reference guide for Git identity, SSH key authentication, and GitHub CLI
access inside the developer VM.

## Scope

Covers Git configuration, SSH key generation, and GitHub CLI authentication.
Does not cover secret storage policy — see
[docs/security/ssh-key-management.md](../security/ssh-key-management.md).

## Prerequisites

- Developer VM is running (`./provision.sh` completed).
- SSH into the VM: `ssh -i ~/.ssh/dev-env ubuntu@<VM_IP>`.

## Automation Status

**Partially automated** by the Ansible `developer_tools` role:
- Git is installed.
- `init.defaultBranch main` and `pull.rebase false` are configured globally.
- GitHub CLI (`gh`) is installed.
- An SSH key (`~/.ssh/id_ed25519`) is generated during `provision.sh`.

**Remains manual:**
- Adding the SSH public key to your GitHub account — `provision.sh` pauses
  and prints the key; you paste it into GitHub Settings → SSH keys.
- `git config --global user.name` and `user.email` — these are personal
  and must be set by you inside the VM.

## Configure Git identity (inside VM)

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

## Verify SSH authentication to GitHub

```bash
ssh -T git@github.com
# Expected: Hi <username>! You've successfully authenticated...
```

## GitHub CLI authentication

```bash
gh auth login
# Follow the interactive prompts (browser or token)

gh auth status
```

## View your SSH public key

```bash
cat ~/.ssh/id_ed25519.pub
```

## References

- [GitHub SSH documentation](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)
- [GitHub CLI](https://cli.github.com/)

## Related Documents

- [docs/security/ssh-key-management.md](../security/ssh-key-management.md)
- [docs/runbooks/new-machine-bootstrap.md](../runbooks/new-machine-bootstrap.md)
