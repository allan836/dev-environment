# Ansible Automation

## Purpose

Document the Ansible playbook and role structure used to install all
developer tools inside the Ubuntu VM.

## Scope

Covers content under [`ansible/`](../../ansible/). Does not cover the VM
provisioning itself (see `provision.sh` and [bash-scripts.md](./bash-scripts.md))
or Compose stacks (see [docker-compose.md](./docker-compose.md)).

## Prerequisites

- [ARCHITECTURE.md](../../ARCHITECTURE.md) principles: declarative
  infrastructure, idempotency, manual fallback, verification.
- The Ansible playbook runs **over SSH from the host** — it is invoked
  automatically by `provision.sh` after the VM is booted. Ansible is
  installed on the host by `provision.sh` if not present.

## Structure

```text
ansible/
├── playbook.yml              Top-level playbook — runs all roles in order
├── inventory/
│   └── hosts.yml             Environment-variable-driven SSH inventory
├── group_vars/
│   └── all/
│       └── versions.yml      Software versions (mirrors config.env)
└── roles/
    ├── docker/               Docker Engine + Compose plugin
    ├── java/                 Java 8 + 17 (apt), Maven
    ├── tomcat/               Tomcat 9 (kv-backend requirement)
    ├── node/                 Node 18/20/22 (nvm), pnpm
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

`provision.sh` sets the `VM_IP`, `VM_SSH_USER`, and `VM_SSH_KEY` environment
variables after booting the VM. To re-run the full playbook manually:

```bash
ansible-playbook ansible/playbook.yml \
  -i "ubuntu@${VM_IP}," \
  --private-key ~/.ssh/dev-env \
  --extra-vars "dev_user=${DEV_USER}" \
  -v
```

To run only specific roles using tags:

```bash
ansible-playbook ansible/playbook.yml \
  -i "ubuntu@${VM_IP}," \
  --private-key ~/.ssh/dev-env \
  --extra-vars "dev_user=${DEV_USER}" \
  --tags docker,java
```

Available tags: `docker`, `java`, `tomcat`, `runtimes`, `node`, `python`,
`terraform`, `iac`, `kubectl`, `kubernetes`, `k8s`, `cloud`, `aws`,
`azure`, `gcp`, `tools`, `git`, `kv`, `kv-backend`.

## Inventory

`ansible/inventory/hosts.yml` uses environment variables (`VM_IP`,
`VM_SSH_USER`, `VM_SSH_KEY`) so the same inventory works regardless of
which provider (Multipass, libvirt, or Incus) booted the VM. When running
manually, override the connection:

```bash
ansible-playbook playbook.yml \
  -i <remote-ip>, \
  -u ubuntu \
  --private-key ~/.ssh/dev-env \
  --extra-vars "dev_user=ubuntu"
```

## Version configuration

All software versions have two sources that must be kept in sync:

- [`config.env`](../../config.env) — shell variables (used by provision.sh and lib/ scripts)
- [`ansible/group_vars/all/versions.yml`](../../ansible/group_vars/all/versions.yml) — Ansible variables (used by roles)

When bumping a version, update both files.

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
