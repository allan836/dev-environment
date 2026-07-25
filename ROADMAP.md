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

### Phase 0 — Documentation & Structure (current)

- [x] Define repository layout and standards.
- [x] Write architecture and philosophy documentation.
- [x] Write manual setup guides for all supported tools/services.
- [x] Write runbooks, troubleshooting, and security documentation.
- [x] Create placeholders for all automation directories.

### Phase 1 — Bash Bootstrap

- [ ] `bootstrap/bootstrap.sh` entry point: OS check, prerequisite install.
- [ ] Idempotency checks for re-runs.
- [ ] Verification/health-check helpers in `scripts/`.

### Phase 2 — Ansible Automation

- [ ] Base role: Fedora system packages, dnf configuration.
- [ ] Role per tool: Docker/Podman, Kubernetes, Terraform/OpenTofu, Git/SSH,
      Python/Node.js/Java, AWS/Azure/GCP CLIs, VS Code/JetBrains.
- [ ] Inventory and variable structure for single-host runs.
- [ ] `ansible-lint` and `--check` (dry-run) support.

### Phase 3 — Containerized Services

- [ ] Docker Compose stack for AI tooling: Ollama, Open WebUI, Qdrant.
- [ ] Docker Compose stack for data stores: PostgreSQL, Redis, RabbitMQ,
      Neo4j, MySQL, MongoDB, Cassandra.
- [ ] Volume and backup strategy per service.
- [ ] Podman Compose parity (optional path).

### Phase 4 — Verification & CI

- [ ] Automated tests under `tests/` (script linting, Compose config
      validation, Ansible syntax checks).
- [ ] GitHub Actions workflows under `.github/workflows/`.
- [ ] End-to-end rebuild validation in a disposable VM.

### Phase 5 — Disaster Recovery Hardening

- [ ] Backup/restore automation for stateful services.
- [ ] Documented and tested full-rebuild drill.

## Non-Goals

- Multi-OS support (macOS/Windows) is out of scope unless explicitly revisited.
- Managing secrets/credentials storage backend selection is deferred to
  [docs/security/secrets-management.md](./docs/security/secrets-management.md).

## References

- [Semantic Versioning](https://semver.org/)

## Related Documents

- [README.md](./README.md)
- [CHANGELOG.md](./CHANGELOG.md)
- [docs/automation/README.md](./docs/automation/README.md)
