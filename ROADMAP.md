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
2. Installs **Vagrant** on the host (apt / dnf / brew / HashiCorp direct).
   Vagrant is installed by provision.sh itself — no manual prerequisite
   beyond `git` and internet access.
3. Tries hypervisor backends **one at a time until one works**:
   - **VirtualBox** — free, cross-platform, tried first.
   - **KVM/libvirt** — Linux-native, tried second.
   - **VMware Workstation/Fusion** — enterprise option, tried third.
   If a backend fails the VM is destroyed and the next backend is tried.
4. Boots an Ubuntu 24.04 LTS VM (cloud image — no ISO required).
5. Runs cloud-init on first boot (user, SSH, base packages).
6. Runs the **Ansible playbook** inside the VM (all developer tools).
7. Prompts the developer to add their SSH key to GitHub (only manual step).
8. Clones kv-backend.
9. Starts Docker services via `make kv-up`.
10. Runs verification and prints "Developer workstation ready."

**New files:**

| File | Purpose |
|---|---|
| `provision.sh` | Root-level single-command entry point |
| `vm/Vagrantfile` | Multi-provider VM definition (VirtualBox / KVM / VMware) |
| `vm/cloud-init/user-data` | First-boot OS configuration |
| `vm/cloud-init/meta-data` | cloud-init instance identity |
| `vm/scripts/provision-vm.sh` | Shell setup inside VM before Ansible |
| `vm/scripts/wait-for-ssh.sh` | TCP poller for SSH readiness |
| `ansible/playbook.yml` | Main Ansible playbook |
| `ansible/inventory/hosts.yml` | Ansible inventory |
| `ansible/roles/docker/` | Docker Engine + Compose plugin |
| `ansible/roles/java/` | Java 8 + 17 via SDKMAN, Maven |
| `ansible/roles/node/` | Node 18/20/22/24 via nvm, pnpm |
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

- Windows host support: Vagrant + VirtualBox works on Windows but
  provision.sh uses Bash. A PowerShell wrapper could be added later.
- Managing secrets/credentials storage backend selection is deferred to
  [docs/security/secrets-management.md](./docs/security/secrets-management.md).

## References

- [Semantic Versioning](https://semver.org/)

## Related Documents

- [README.md](./README.md)
- [CHANGELOG.md](./CHANGELOG.md)
- [docs/automation/README.md](./docs/automation/README.md)
