# Roadmap

## Purpose

Communicate the planned phases of work for this repository, from
documentation-only to fully automated workstation rebuild.

## Scope

Covers documentation milestones and future automation (Bash, Ansible,
Docker Compose). Does not track day-to-day tasks — use the issue tracker
for that.

## Prerequisites

- Read [README.md](./README.md) for project vision and goals.

## Phases

### Phase 0 — Documentation & Structure (complete)

- [x] Define repository layout and standards.
- [x] Write architecture and philosophy documentation.
- [x] Write manual setup guides for all supported tools/services.
- [x] Write runbooks, troubleshooting, and security documentation.
- [x] Create placeholders for all automation directories.

### Phase 1 — VM Provisioner (complete)

The repository now ships a single-command developer environment provisioner.
A new developer only needs `git` and an internet connection on their laptop.

**Entry point:**
```bash
git clone https://github.com/allandzingo/dev-environment.git
cd dev-environment
./provision.sh
```

**What provision.sh does, in order:**

1. Detects host OS (Linux / macOS).
2. Probes virtualization providers in priority order —
   **Multipass** (cross-platform) → **libvirt** (Linux native KVM) →
   **Incus** (Linux LXD fork) — and selects the first one that works.
3. Installs the selected provider tool if it is not already present
   (with multiple fallback methods: snap → apt → direct download).
4. Boots an Ubuntu 24.04 LTS VM (cloud image — no ISO required) using the
   selected provider.
5. Runs cloud-init on first boot (user, SSH, base packages).
6. Waits for SSH readiness.
7. Runs the **Ansible playbook** over SSH (all developer tools).
8. Prompts the developer to add their SSH key to GitHub (only manual step).
9. Clones kv-backend.
10. Starts Docker services via `make kv-up`.
11. Runs verification and prints "Developer workstation ready."

**New files:**

| File | Purpose |
|---|---|
| `provision.sh` | Root-level single-command entry point |
| `config.env` | Central version configuration |
| `lib/log.sh` | Structured logging helpers |
| `lib/detect.sh` | Host OS / provider detection |
| `lib/dependencies.sh` | Provider tool installation |
| `lib/vm.sh` | Provider-agnostic VM lifecycle |
| `lib/ansible_runner.sh` | Ansible execution over SSH |
| `lib/verify.sh` | Post-provisioning verification |
| `lib/providers/multipass.sh` | Multipass provider implementation |
| `lib/providers/libvirt.sh` | KVM/libvirt provider implementation |
| `lib/providers/incus.sh` | Incus provider implementation |
| `vm/cloud-init/user-data` | First-boot OS configuration |
| `vm/cloud-init/meta-data` | cloud-init instance identity |
| `vm/scripts/provision-vm.sh` | Shell setup inside VM before Ansible |
| `vm/scripts/wait-for-ssh.sh` | TCP poller for SSH readiness |
| `ansible/playbook.yml` | Main Ansible playbook |
| `ansible/inventory/hosts.yml` | Ansible inventory (SSH-based) |
| `ansible/roles/docker/` | Docker Engine + Compose plugin |
| `ansible/roles/java/` | Java 8 + 17 via apt, Maven |
| `ansible/roles/tomcat/` | Tomcat 9 (kv-backend requirement) |
| `ansible/roles/node/` | Node 18/20/22 via nvm, pnpm |
| `ansible/roles/python/` | pyenv, pipenv, uv |
| `ansible/roles/terraform/` | Terraform + OpenTofu |
| `ansible/roles/kubectl/` | kubectl, Helm, k9s |
| `ansible/roles/cloud_clis/` | AWS CLI v2, Azure CLI, gcloud |
| `ansible/roles/developer_tools/` | VS Code, GitHub CLI, openfortivpn, DBeaver |
| `ansible/roles/kv_backend/` | kv-backend clone + Docker image load |

### Phase 2 — Ansible Hardening (next)

- [ ] `ansible-lint` clean pass on all roles.
- [ ] `--check` (dry-run) support: `./provision.sh --check`.
- [ ] Role for Podman (rootless container alternative).
- [ ] Role for JetBrains toolbox.
- [ ] Idempotency tests: run playbook twice, assert zero changes on second run.

### Phase 3 — Containerized Services

- [ ] Docker Compose stack for AI tooling: Ollama, Open WebUI, Qdrant.
- [ ] Docker Compose stack for data stores: PostgreSQL, Redis, RabbitMQ,
      Neo4j, MySQL, MongoDB, Cassandra.
- [ ] Volume and backup strategy per service.

### Phase 4 — Verification & CI

- [ ] Automated tests under `tests/` (shellcheck, Ansible syntax, Compose
      config validation).
- [ ] GitHub Actions: lint on every PR, end-to-end provision test in a
      nested VM (VirtualBox inside a Linux runner).
- [ ] `provision.sh --verify-only`: re-run verification without reprovisioning.

### Phase 5 — Disaster Recovery Hardening

- [ ] Backup/restore automation for stateful Docker volumes.
- [ ] Documented and tested full-rebuild drill (destroy VM → reprovision →
      restore data → verify).
- [ ] `provision.sh --restore BACKUP_PATH` flag.

## Non-Goals

- Windows host support: the provisioner uses Bash and Linux/macOS
  providers. A PowerShell wrapper could be added later.
- Managing secrets/credentials storage backend selection is deferred to
  [docs/security/secrets-management.md](./docs/security/secrets-management.md).

## References

- [Semantic Versioning](https://semver.org/)

## Related Documents

- [README.md](./README.md)
- [CHANGELOG.md](./CHANGELOG.md)
- [docs/automation/README.md](./docs/automation/README.md)
