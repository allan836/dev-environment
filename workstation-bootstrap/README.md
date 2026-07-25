# Workstation Bootstrap

> Part of the [dev-environment](../README.md) repository. This subdirectory
> is a self-contained, cross-platform (macOS + Fedora) onboarding automation
> project, separate from the Fedora-only documentation set at the repo root.

Automated, OS-agnostic (macOS + Fedora) replacement for the original
manual, macOS-only, Homebrew-based engineer onboarding checklist.

## Principles

1. The host stays thin — only what's needed to *run* a project's
   environment is installed on the machine itself.
2. Databases and backing services are containerized, not brew-installed,
   so they're versioned, reproducible, and disposable per project.
3. One command bootstraps the host; one command starts local services.
4. Every automated step is idempotent (safe to re-run) and has a
   documented manual fallback.

See [docs/classification.md](docs/classification.md) for how every tool
from the original checklist was categorized, and
[docs/architecture.md](docs/architecture.md) for the target design.

## Quick Start

A new engineer only needs to do this:

```bash
git clone <this-repo-url> workstation-bootstrap
cd workstation-bootstrap
./setup.sh           # installs host tooling + runtimes, creates .env, prints next steps
docker compose up -d   # starts MySQL, MongoDB, Cassandra, RabbitMQ, Neo4j, nginx, Consul
./scripts/verify.sh
```

Or via `make`: `make setup`, `make up`, `make verify`, `make down`.

`setup.sh` auto-creates `.env` from `.env.example` on first run. Review it
if you want non-default local credentials before running `docker compose
up -d`. See [Manual Steps](#manual-steps-not-automated) below for the
handful of things that still require a human (2FA, SSH key, phone app).

## What Gets Installed Where

| Layer | Where | Details |
|---|---|---|
| Core system tools (Git, Docker, `gh`, OpenVPN, AWS CLI, Terraform, `kubectl`) | Host | [scripts/install-core.sh](scripts/install-core.sh) |
| Language runtimes (Node/nvm, Python/pyenv/pipenv/uv, Java/SDKMAN, pnpm) | Host | [scripts/install-runtimes.sh](scripts/install-runtimes.sh) |
| Databases & services (MySQL, MongoDB, Cassandra, RabbitMQ, Neo4j, nginx, Consul) | Docker | [docker-compose.yml](docker-compose.yml) |
| Dev tools (VS Code, Docker Desktop, Lens, DBeaver, MongoDB Compass) | Host | [scripts/install-core.sh](scripts/install-core.sh), [scripts/install-desktop-apps.sh](scripts/install-desktop-apps.sh) |
| Communication apps (Slack, Zoom, Teams, etc.) | Host, best-effort | [scripts/install-desktop-apps.sh](scripts/install-desktop-apps.sh) |

Full rationale: [docs/classification.md](docs/classification.md).

## Local Service Access

| Service | URL / Address | Default credentials |
|---|---|---|
| RabbitMQ management | http://localhost:15672 | guest / guest |
| Neo4j browser | http://localhost:7474 | neo4j / see `.env` |
| nginx | http://localhost:8080 | — |
| Consul UI | http://localhost:8500 | — |
| MySQL | localhost:3306 | root / see `.env` |
| MongoDB | localhost:27017 | — |
| Cassandra | localhost:9042 | — |

## Devcontainer Template

[.devcontainer/devcontainer.json](.devcontainer/devcontainer.json) is a
starting template: copy `.devcontainer/` and `docker-compose.yml` into a
project repo, adjust the `service` field, and engineers get a fully
configured environment via VS Code's "Reopen in Container" — no manual
runtime installs needed for that project.

## Manual Steps (Not Automated)

These require human judgment or an interactive dialog/mobile device and are
intentionally left out of `setup.sh`:

- Sign in to work Google Workspace account, enable 2FA, share personal
  Google Photos with the work account.
- Accept the Xcode Command Line Tools license (macOS interactive prompt).
- Generate an SSH key: `ssh-keygen -C "$(hostname)"`.
- Install FortiToken Mobile on your personal phone.
- Grant Screen & System Audio Recording permissions (macOS Privacy &
  Security settings) for Firefox, Chrome, Slack, Shottr, LICEcap, Zoom,
  Microsoft Teams, OBS.
- Enable Kubernetes in Docker Desktop (macOS): Settings → Kubernetes →
  Enable Kubernetes → Apply. On Fedora, use `kind`/`minikube` instead (not
  yet scripted — see Roadmap).

## Roadmap

- [x] Phase 1 — Extract install steps into scripts, run on both macOS and Fedora.
- [x] Phase 2 — Move all databases/services to Docker.
- [x] Phase 3 — Add `docker-compose.yml`.
- [x] Phase 4 — Add devcontainer template.
- [ ] Phase 5 — Retire the remaining manual checklist items where feasible;
      add a Fedora local-Kubernetes script (`kind`); consider Ansible if a
      third OS or fleet management is ever needed.

## Related Documents

- [docs/classification.md](docs/classification.md)
- [docs/architecture.md](docs/architecture.md)
- [docs/migration-notes.md](docs/migration-notes.md)
