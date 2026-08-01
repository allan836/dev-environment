# Ansible Automation

## Purpose

Document the Ansible playbook and role structure used to install all
developer tools inside the Ubuntu VM.

## Scope

Covers content under [`ansible/`](../../ansible/). Does not cover the VM
provisioning itself (see `provision.sh`) or Bash scripts (see
[bash-scripts.md](./bash-scripts.md)) or Compose stacks (see
[docker-compose.md](./docker-compose.md)).

## Prerequisites

- [ARCHITECTURE.md](../../ARCHITECTURE.md) principles: declarative
  infrastructure, idempotency, manual fallback, verification.
- The Ansible playbook runs **inside the VM** — it is invoked automatically
  by `provision.sh` via Vagrant's `ansible_local` provisioner. Ansible
  does not need to be installed on the host machine.

## Structure

```text
ansible/
├── playbook.yml              Top-level playbook — runs all roles in order
├── inventory/
│   └── hosts.yml             Single-host local-connection inventory
└── roles/
    ├── docker/               Docker Engine + Compose plugin
    ├── java/                 Java 8 + 17 (SDKMAN), Maven
    ├── node/                 Node 18/20/22/24 (nvm), pnpm
    ├── python/               pyenv, pipenv, uv
    ├── terraform/            Terraform + OpenTofu
    ├── kubectl/              kubectl, Helm, k9s
    ├── cloud_clis/           AWS CLI v2, Azure CLI, Google Cloud CLI
    ├── developer_tools/      VS Code, GitHub CLI, openfortivpn, DBeaver, shell tools
    └── kv_backend/           kv-backend clone, Docker image load, .env setup
```

## Role Design Rules

- **One role per concern** — each role matches the corresponding guide in
  [docs/setup](../setup/README.md).
- **Idempotent** — every role uses `creates:`, `when:`, or `stat:` guards
  so it can be re-run without duplicating work.
- **`command`/`shell` only when necessary** — built-in Ansible modules
  (`apt`, `file`, `copy`, `systemd`, `user`, `git`) are preferred. Where
  `shell` is unavoidable it always has a `creates:` or `changed_when:` guard.
- **Verification task per role** — every role ends with a version check or
  reachability test, mirroring the "every installation has a verification
  step" principle.
- **No secrets in roles** — credentials are in `workstation-bootstrap/.env`,
  never hardcoded in role defaults or vars.
- **`ignore_errors: true` for optional tools** — cloud CLIs (Azure, gcloud),
  DBeaver, and k9s are best-effort. A failure does not abort the whole
  playbook.

## Running the playbook manually

To re-run the full playbook against the running VM:

```bash
cd vm
vagrant ssh -c "
  cd ~/dev-environment/ansible
  ansible-playbook playbook.yml -i inventory/hosts.yml -v
"
```

To run only specific roles using tags:

```bash
vagrant ssh -c "
  cd ~/dev-environment/ansible
  ansible-playbook playbook.yml -i inventory/hosts.yml --tags docker,java
"
```

Available tags: `docker`, `java`, `runtimes`, `node`, `python`, `terraform`,
`iac`, `kubectl`, `kubernetes`, `k8s`, `cloud`, `aws`, `azure`, `gcp`,
`tools`, `git`, `vscode`, `kv`, `kv-backend`.

## Inventory

`ansible/inventory/hosts.yml` uses `ansible_connection: local` because the
playbook runs on the VM itself (via `ansible_local`). When targeting a
remote machine (e.g. a cloud instance), override the connection:

```bash
ansible-playbook playbook.yml \
  -i <remote-ip>, \
  -u ubuntu \
  --private-key ~/.ssh/id_ed25519 \
  --extra-vars "dev_user=ubuntu"
```

## Next steps (Phase 2 — see ROADMAP)

- `ansible-lint` clean pass on all roles.
- `--check` dry-run support.
- Roles for Podman (rootless) and JetBrains Toolbox.
- Idempotency test: run playbook twice, assert zero changes on second run.

## References

- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html)
- [ansible-lint](https://ansible.readthedocs.io/projects/lint/)

## Related Documents

- [ansible/playbook.yml](../../ansible/playbook.yml)
- [ansible/inventory/hosts.yml](../../ansible/inventory/hosts.yml)
- [docs/setup/README.md](../setup/README.md)
- [provision.sh](../../provision.sh)
