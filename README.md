# Dev Environment — Developer Environment Provisioner

## Project Vision

A single source of truth for building, documenting, and rebuilding a modern
cloud/platform engineering developer environment. This repository treats a
developer machine as infrastructure: version-controlled, declarative,
reproducible, and disaster-recovery ready. One command provisions a complete
Ubuntu VM from scratch on any host OS. If a machine is lost, running
`./provision.sh` on any laptop restores a working environment in minutes.

## Goals

- Provide a single-command setup that works on any developer laptop
  (macOS, Ubuntu, Debian, Fedora) — no manual OS installation required.
- Automate all tool installation inside an isolated, reproducible Ubuntu VM.
- Preserve institutional knowledge (decisions, troubleshooting, runbooks)
  that normally lives only in one engineer's head.
- Support kv-backend's containerized local services with minimal friction.
- Enable disaster recovery: rebuild the entire environment from zero using
  only this repository.

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

The environment is composed of four layers:

- **Host layer** — the developer's laptop (any OS). Runs only Vagrant and a
  hypervisor. Untouched beyond that.
- **VM layer** — Ubuntu 24.04 LTS virtual machine managed by Vagrant.
  Created and configured automatically by `provision.sh`.
- **Tooling layer** — language runtimes (Python, Node.js, Java), cloud CLIs
  (AWS, Azure, GCP), IaC tools (Terraform, OpenTofu, kubectl), VS Code, and
  developer tools — all installed inside the VM by Ansible.
- **Services layer** — kv-backend's Docker Compose stack (MySQL, Cassandra,
  Solr, RabbitMQ, Memcached, MailHog, Tomcat) running inside the VM.

Details: [docs/architecture](./docs/architecture/README.md).

## Repository Layout

```text
dev-environment/
├── provision.sh             Single entry point — clone and run this
├── README.md                Project entry point (this file)
├── ARCHITECTURE.md          Repository philosophy and architectural rules
├── LICENSE                  License terms
├── CONTRIBUTING.md          Contribution workflow and standards
├── CHANGELOG.md             Notable changes per release
├── ROADMAP.md               Planned work and what is already built
├── vm/                      VM definition and first-boot config
│   ├── Vagrantfile          Multi-provider VM (VirtualBox / KVM / VMware)
│   ├── cloud-init/          First-boot OS config (user, SSH, packages)
│   └── scripts/             Helper scripts run inside the VM at boot
├── ansible/                 All developer tool installation
│   ├── playbook.yml         Main playbook — runs all roles in order
│   ├── inventory/           Single-host local-connection inventory
│   └── roles/               One role per tool: docker, java, node, python,
│                              terraform, kubectl, cloud_clis,
│                              developer_tools, kv_backend
├── workstation-bootstrap/   Direct host install path (no VM required)
│   ├── setup.sh             OS-aware entry point (macOS/Ubuntu/Fedora)
│   ├── Makefile             kv-up, kv-init, kv-verify, kv-clean-slate, …
│   └── scripts/             Per-stage install and verify scripts
├── assets/                  Static assets (preload Docker images tarball)
└── docs/                    All documentation, organized by concern
    ├── architecture/        System design and technology decisions
    ├── setup/               Per-tool reference guides and manual fallbacks
    ├── automation/          How automation (Bash/Ansible/Compose) works
    ├── runbooks/            Operational procedures (provision, DR, backup)
    ├── troubleshooting/     Known issues and resolutions
    ├── security/            Secrets and credential handling
    └── decisions/           Architecture Decision Records (ADRs)
```

## Supported Platforms

- **Host OS** (the laptop running `provision.sh`): macOS, Ubuntu, Debian, Fedora.
- **VM OS**: Ubuntu 24.04 LTS (fixed — all developers get the same environment).
- **Hypervisors**: VirtualBox (default), KVM/libvirt (Linux hosts), VMware Workstation/Fusion.
- **Direct host install** (no VM, via `workstation-bootstrap/setup.sh`): macOS, Ubuntu, Debian, Fedora.

## Quick Start — Single Command

Prerequisites on the host laptop: **git** and **internet access**.
Everything else (Vagrant, the hypervisor, Ubuntu, all developer tools)
is installed automatically.

```bash
git clone https://github.com/allandzingo/dev-environment.git
cd dev-environment
./provision.sh
```

`provision.sh` will:
1. Install **Vagrant** on the host.
2. Try hypervisor backends in order (**VirtualBox → KVM → VMware**) until
   one works — if one fails it destroys the partial VM and tries the next.
3. Boot an **Ubuntu 24.04 LTS** VM (cloud image, no ISO needed).
4. Run **cloud-init** on first boot and then an **Ansible playbook** that
   installs every developer tool inside the VM.
5. Pause once to show the VM's SSH public key — add it to your GitHub
   account (Settings → SSH keys). This is the only manual step.
6. Clone **kv-backend**, load Docker images, start all services.
7. Print `✔ Developer workstation ready.`

Options:

```bash
./provision.sh --cpu 6 --ram 12288   # more resources
./provision.sh --destroy             # wipe VM and reprovision from scratch
./provision.sh --skip-ansible        # boot VM only, skip tool install
./provision.sh --help                # full usage
```

SSH into the running VM at any time:

```bash
cd vm && vagrant ssh
```

See [ROADMAP.md](./ROADMAP.md) for what was built and what is planned next.

---

**Existing machine (no VM needed):** if you are already on Ubuntu, macOS, or
Fedora, use [workstation-bootstrap/](./workstation-bootstrap/) directly:

```bash
cd workstation-bootstrap
./setup.sh      # installs git, docker, java 17, maven, node on the host
make kv-up      # starts the kv-backend docker-compose stack
make kv-init    # first-time DB/Cassandra/Solr init
make kv-verify  # checks all services are reachable
```

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
| Direct host install (no VM) | [workstation-bootstrap/README.md](./workstation-bootstrap/README.md) |

## Automation Roadmap

Automation will be delivered in phases: Bash bootstrap scripts, Ansible roles
per tool/service, and Docker Compose stacks for local services. Current
status and planned phases are tracked in [ROADMAP.md](./ROADMAP.md).

## Technology Stack

| Category | Tools |
|---|---|
| VM OS | Ubuntu 24.04 LTS |
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
