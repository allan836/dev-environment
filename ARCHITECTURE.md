# Repository Philosophy & Architecture

## Purpose

Define the non-negotiable principles that govern how this repository is
structured, how automation is written, and how decisions are made. Every
document, script, and playbook added to this repository must be consistent
with the principles below.

## Scope

Applies to the entire repository: documentation structure, automation design
(Bash/Ansible/Docker Compose), configuration management, and secret handling.
Does not cover specific tool installation steps — see [docs/setup](./docs/setup/README.md).

## Prerequisites

- Familiarity with the [README.md](./README.md) project overview.

## Repository Philosophy

1. **Everything is version controlled.**
   Every configuration file, script, playbook, and piece of documentation
   that defines the workstation lives in this Git repository. Nothing
   important should exist only on a single machine.

2. **Infrastructure is declarative.**
   Desired state is described (Ansible roles, Compose files, Terraform/OpenTofu
   configs), not a sequence of imperative one-off commands. The system should
   converge to the declared state regardless of starting point.

3. **Documentation is treated as code.**
   Markdown documents are reviewed with the same rigor as scripts: accuracy,
   clarity, and cross-referencing are required. Documentation changes ship in
   the same pull request as the automation change they describe.

4. **Configuration is automated.**
   Manual configuration is a temporary state, tracked in [ROADMAP.md](./ROADMAP.md),
   until it is captured in Bash, Ansible, or Compose.

5. **Local services run in containers where practical.**
   Databases, brokers, and AI tooling (PostgreSQL, Redis, RabbitMQ, Neo4j,
   MySQL, MongoDB, Cassandra, Qdrant, Ollama, Open WebUI) run as containers
   via Docker/Podman Compose rather than being installed directly on the host,
   minimizing host pollution and easing teardown/rebuild.

6. **Secrets are never committed.**
   No API keys, passwords, tokens, or private keys are stored in this
   repository in plaintext. See [docs/security/secrets-management.md](./docs/security/secrets-management.md).

7. **Every automated task has a manual fallback documented.**
   Automation can fail or be unavailable. Each guide in [docs/setup](./docs/setup/README.md)
   documents the manual procedure the automation is intended to replace.

8. **Every installation has a verification step.**
   No setup step (manual or automated) is considered complete without a
   documented way to confirm it succeeded (e.g. version check, health check,
   test connection).

## Architectural Layers

| Layer | Responsibility | Primary Mechanism |
|---|---|---|
| Host | Developer's laptop (any OS) — runs Vagrant and hypervisor only | `provision.sh` |
| VM | Ubuntu 24.04 LTS virtual machine — isolated, reproducible, disposable | Vagrant + cloud-init |
| Tooling | Languages, cloud CLIs, IaC tools, IDEs — installed inside the VM | Ansible roles |
| Services | kv-backend Docker Compose stack — MySQL, Cassandra, Solr, RabbitMQ, etc. | Docker Compose via Makefile |

Full component-level design is in [docs/architecture/overview.md](./docs/architecture/overview.md).

## Decision-Making

Architecturally significant choices (e.g. "Docker vs Podman as default",
"Ansible vs pure Bash") are recorded as Architecture Decision Records in
[docs/decisions](./docs/decisions/README.md), not buried in commit messages.

## References

- [The Twelve-Factor App](https://12factor.net/) — principles adapted for
  workstation configuration (declarative config, environment parity).
- [Architecture Decision Records](https://adr.github.io/)

## Related Documents

- [README.md](./README.md) — project overview and repository layout.
- [docs/architecture/README.md](./docs/architecture/README.md) — detailed system design.
- [docs/decisions/README.md](./docs/decisions/README.md) — decision records.
- [docs/security/secrets-management.md](./docs/security/secrets-management.md) — secret handling rules.
