# Secrets Management

## Purpose

Define how credentials, API keys, tokens, and passwords are stored and
supplied to tools and containers on this workstation, without ever being
committed to this repository.

## Scope

Covers the policy and mechanisms for secret handling across cloud CLIs,
containerized services, and Ansible automation. Does not cover SSH key
specifics — see [docs/security/ssh-key-management.md](./ssh-key-management.md).

## Prerequisites

- [ARCHITECTURE.md](../../ARCHITECTURE.md) principle: secrets are never
  committed.

## Policy

- No secret value is ever written into a tracked file in this repository.
  Enforced structurally via [.gitignore](../../.gitignore) patterns
  (`*.env`, `*.pem`, `*.key`, `secrets/`, `*.tfvars`, vault password files).
- Local service credentials (database passwords, RabbitMQ users) are
  supplied to Docker Compose via an untracked `.env` file at the repository
  root or per-stack, following `docker/compose/.env.example` (a
  non-secret template, to be added when Compose files are implemented).
- Cloud provider credentials (AWS/Azure/GCP) are managed by each CLI's own
  credential store (`~/.aws/`, `~/.azure/`, `~/.config/gcloud/`), never
  copied into this repository. SSO/temporary credentials are preferred over
  long-lived static keys — see [docs/setup/cloud-clis.md](../setup/cloud-clis.md).
- Ansible secrets, once automation is implemented, use **Ansible Vault**
  rather than plaintext variable files; the vault password itself is kept
  outside this repository.
- Terraform/OpenTofu variable files containing sensitive values use the
  `*.tfvars` pattern excluded by [.gitignore](../../.gitignore); an
  `*.tfvars.example` with placeholder values is committed instead.

## Verification

- Before every commit, confirm no secret patterns are staged:
  `git diff --cached --name-only` reviewed against [.gitignore](../../.gitignore).
- CI includes a secret-scanning step (planned — see
  [.github/workflows](../../.github/workflows) and [ROADMAP.md](../../ROADMAP.md)).

## References

- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
- [Ansible Vault documentation](https://docs.ansible.com/ansible/latest/vault_guide/index.html)

## Related Documents

- [docs/security/ssh-key-management.md](./ssh-key-management.md)
- [docs/setup/cloud-clis.md](../setup/cloud-clis.md)
- [docs/automation/ansible.md](../automation/ansible.md)
- [.gitignore](../../.gitignore)
