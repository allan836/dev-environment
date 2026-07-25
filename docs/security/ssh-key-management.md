# SSH Key Management

## Purpose

Define the policy for generating, storing, and rotating SSH keys used for
Git/GitHub authentication and remote host access from this workstation.

## Scope

Covers SSH key lifecycle policy. Does not cover the initial setup steps for
Git/GitHub — see [docs/setup/git-github-ssh.md](../setup/git-github-ssh.md).
Does not cover general secret handling for cloud/service credentials — see
[docs/security/secrets-management.md](./secrets-management.md).

## Prerequisites

- [docs/setup/git-github-ssh.md](../setup/git-github-ssh.md)

## Policy

- Key type: Ed25519 by default (smaller, faster, and as secure as RSA-4096
  for this use case). RSA-4096 is an acceptable fallback for legacy systems
  that do not support Ed25519.
- Private keys never leave the machine they were generated on and are never
  committed to this or any repository — enforced via
  [.gitignore](../../.gitignore) patterns (`*.key`, `*_ed25519`, `*_rsa`).
- Each machine gets its own key pair; keys are not copied between machines.
  A lost/compromised machine only requires revoking that machine's key.
- Public keys are registered with GitHub per
  [docs/setup/git-github-ssh.md](../setup/git-github-ssh.md); private keys
  are optionally protected with a passphrase and unlocked via the SSH
  agent/`gnome-keyring`.
- Key generation itself remains a manual, human-in-the-loop step (not
  automated), consistent with the manual-fallback principle for
  sensitive operations.

## Rotation / Revocation

- On suspected compromise or machine decommission: remove the corresponding
  public key from GitHub immediately, then generate a fresh key pair on any
  replacement machine following
  [docs/setup/git-github-ssh.md](../setup/git-github-ssh.md).
- Recommended rotation cadence: at minimum whenever a machine is
  decommissioned, or per organizational policy if stricter.

## Verification

```bash
ssh-add -l
ssh -T git@github.com
```

## References

- [GitHub Docs: Connecting with SSH](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)

## Related Documents

- [docs/setup/git-github-ssh.md](../setup/git-github-ssh.md)
- [docs/security/secrets-management.md](./secrets-management.md)
- [docs/runbooks/disaster-recovery.md](../runbooks/disaster-recovery.md)
