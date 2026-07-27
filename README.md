# Dev Environment — Fedora Developer Workstation

## Project Vision

A single source of truth for building, documenting, and rebuilding a modern
cloud/platform engineering workstation on Fedora Linux. This repository
treats a developer machine as infrastructure: version-controlled, declarative,
reproducible, and disaster-recovery ready. If a laptop dies, a new Fedora
install combined with this repository should be enough to be productive again
within hours, not days.

## Goals

- Provide a documented, repeatable process to configure a Fedora Workstation
  for cloud/platform engineering and software development.
- Automate installation and configuration wherever safely possible.
- Preserve institutional knowledge (decisions, troubleshooting, runbooks) that
  normally lives only in one engineer's head.
- Support container-based local services (databases, message brokers, AI
  tooling) with minimal host pollution.
- Enable disaster recovery: rebuild a workstation from bare metal using only
  this repository and a few secrets.

## Design Principles

1. **Reproducibility** — the same inputs always produce the same workstation.
2. **Automation** — manual steps are the exception, not the rule.
3. **Maintainability** — documentation and automation evolve together.
4. **Documentation as Code** — Markdown lives in version control, reviewed
   like any other change.
5. **Idempotency** — every automated task can be re-run safely with no
   unintended side effects.

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the full philosophy and
architectural decision rules.

## Architecture Overview

The workstation is composed of three layers:

- **Host layer** — Fedora Workstation, base packages, shell, SSH, Git.
- **Tooling layer** — language runtimes (Python, Node.js, Java), cloud CLIs
  (AWS, Azure, GCP), IaC tools (Terraform, OpenTofu, Kubernetes CLI), IDEs.
- **Services layer** — containerized local services (PostgreSQL, Redis,
  RabbitMQ, Neo4j, MySQL, MongoDB, Cassandra, Qdrant, Ollama, Open WebUI)
  run via Docker/Podman Compose, not installed directly on the host.

Configuration of all three layers is driven by Ansible playbooks and roles,
invoked through Bash bootstrap scripts. Details: [docs/architecture](./docs/architecture/README.md).

## Repository Layout

```text
dev-environment/
├── README.md                Project entry point (this file)
├── ARCHITECTURE.md          Repository philosophy and architectural rules
├── LICENSE                  License terms
├── CONTRIBUTING.md          Contribution workflow and standards
├── CHANGELOG.md             Notable changes per release
├── ROADMAP.md               Planned automation and documentation work
├── docs/                    All documentation, organized by concern
│   ├── architecture/        System design and technology decisions
│   ├── setup/               Per-tool/service manual setup guides
│   ├── automation/          How automation (Bash/Ansible/Compose) works
│   ├── runbooks/            Operational procedures (DR, bootstrap, backup)
│   ├── troubleshooting/     Known issues and resolutions
│   ├── security/            Secrets and credential handling
│   └── decisions/           Architecture Decision Records (ADRs)
├── bootstrap/                Entry-point bootstrap scripts (placeholders)
├── scripts/                  Standalone Bash utility scripts (placeholders)
├── ansible/                   Ansible playbooks, roles, inventory (placeholders)
│   ├── roles/
│   └── inventory/
├── docker/                    Container definitions and Compose stacks
│   └── compose/
├── configs/                   Managed application/service configuration files
├── dotfiles/                   Managed shell and tool dotfiles
├── templates/                  Reusable file/config templates
├── tests/                      Automation verification tests
├── tools/                      Helper/developer tooling for this repo itself
├── assets/                     Diagrams and other static assets
└── .github/workflows/          CI workflows
```

## Supported Platforms

- **Primary target:** Fedora Workstation (latest two releases).
- **Container runtime:** Docker (primary), Podman (optional, rootless).
- **Not currently supported:** macOS, Windows, other Linux distributions.
  Contributions to extend support are welcome — see [CONTRIBUTING.md](./CONTRIBUTING.md).

## Quick Start

> Root-level automation (`bootstrap/`, `ansible/`, `docker/compose/`) is not
> yet implemented. See [ROADMAP.md](./ROADMAP.md) for status.

**For kv-backend specifically**, use [workstation-bootstrap/](./workstation-bootstrap/)
instead — it is the real, working single-command path today:

```bash
cd workstation-bootstrap
./setup.sh      # host tools: git, docker, java 17, maven, node...
make kv-up      # builds kv-backend + starts its own docker-compose stack
make kv-init    # first time only: DB/Cassandra/Solr init
make kv-verify  # checks kv-backend services are reachable
```

See [workstation-bootstrap/README.md#kv-backend-local-environment](./workstation-bootstrap/README.md#kv-backend-local-environment)
for prerequisites (kv-backend's preload Docker images must be downloaded
manually first) and full details.

For the general Fedora-only workstation described below:

1. Install Fedora Workstation on the target machine.
2. Read [docs/setup/fedora-base-setup.md](./docs/setup/fedora-base-setup.md).
3. Clone this repository.
4. Follow [docs/runbooks/new-machine-bootstrap.md](./docs/runbooks/new-machine-bootstrap.md)
   for the end-to-end rebuild procedure.
5. Once automation lands, run the bootstrap entry point described in
   [bootstrap/README.md](./bootstrap/README.md).

## Documentation Index

| Area | Document |
|---|---|
| Philosophy | [ARCHITECTURE.md](./ARCHITECTURE.md) |
| System design | [docs/architecture/README.md](./docs/architecture/README.md) |
| Manual setup guides | [docs/setup/README.md](./docs/setup/README.md) |
| Automation design | [docs/automation/README.md](./docs/automation/README.md) |
| Operational runbooks | [docs/runbooks/README.md](./docs/runbooks/README.md) |
| Troubleshooting | [docs/troubleshooting/README.md](./docs/troubleshooting/README.md) |
| Security & secrets | [docs/security/README.md](./docs/security/README.md) |
| Decision records | [docs/decisions/README.md](./docs/decisions/README.md) |
| Cross-platform onboarding automation (macOS + Fedora) | [workstation-bootstrap/README.md](./workstation-bootstrap/README.md) |

## Automation Roadmap

Automation will be delivered in phases: Bash bootstrap scripts, Ansible roles
per tool/service, and Docker Compose stacks for local services. Current
status and planned phases are tracked in [ROADMAP.md](./ROADMAP.md).

## Technology Stack

| Category | Tools |
|---|---|
| OS | Fedora Workstation |
| Containers | Docker, Podman (optional) |
| Orchestration | Kubernetes |
| Infrastructure as Code | Terraform, OpenTofu |
| Version Control | Git, GitHub, SSH |
| Languages/Runtimes | Python, Node.js, Java |
| Cloud CLIs | AWS CLI, Azure CLI, Google Cloud CLI |
| IDEs | VS Code, JetBrains IDEs |
| AI / Vector | Ollama, Open WebUI, Qdrant |
| Data Stores | PostgreSQL, MySQL, MongoDB, Cassandra, Neo4j, Redis |
| Messaging | RabbitMQ |
| Automation | Bash, Ansible, Docker Compose |

Full rationale per tool is documented in [docs/architecture](./docs/architecture/README.md)
and individual guides under [docs/setup](./docs/setup/README.md).

## Development Workflow

Changes to this repository (documentation or, later, automation code) follow
standard pull-request review. See [CONTRIBUTING.md](./CONTRIBUTING.md) for
branching, commit, and review conventions.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](./CONTRIBUTING.md) before
opening a pull request.

## License

Distributed under the terms in [LICENSE](./LICENSE).
