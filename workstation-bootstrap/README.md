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
./setup.sh        # installs host tooling + runtimes (git, docker, java, maven...), creates .env
make kv-up        # builds kv-backend WARs (mvn) + starts kv-backend's own docker-compose stack
make kv-init       # FIRST TIME ONLY: runs kv-backend's quick-setup.sh (DB/Cassandra/Solr init)
make kv-verify     # checks kv-backend's services are reachable
```

Or without `make`: `./scripts/kv-backend.sh {load-images|up|init|verify|status|down}`.

`setup.sh` auto-creates `.env` from `.env.example` on first run — set
`KV_BACKEND_DIR` there if your kv-backend clone isn't at
`$HOME/workspace/repos/kv-backend`. `make kv-up` automatically
`docker load`s the preload images tarball at
[../assets/preload_kv.tar.gz](../assets/preload_kv.tar.gz) the first time
it's needed — no manual download/load step. See
[kv-backend Local Environment](#kv-backend-local-environment) below for
details.

## What Gets Installed Where

| Layer | Where | Details |
|---|---|---|
| Core system tools (Git, Docker, `gh`, OpenVPN, AWS CLI, Terraform, `kubectl`) | Host | [scripts/install-core.sh](scripts/install-core.sh) |
| Language runtimes (Node/nvm, Python/pyenv/pipenv/uv, Java 17 + Maven/SDKMAN, pnpm) | Host | [scripts/install-runtimes.sh](scripts/install-runtimes.sh) |
| kv-backend databases & services (MySQL, RabbitMQ, Cassandra, Solr, Memcached, Tomcat/portal) | Docker, driven from kv-backend's own `preload-docker-compose` | [scripts/kv-backend.sh](scripts/kv-backend.sh) |
| Dev tools (VS Code, Docker Desktop, Lens, DBeaver, MongoDB Compass) | Host | [scripts/install-core.sh](scripts/install-core.sh), [scripts/install-desktop-apps.sh](scripts/install-desktop-apps.sh) |
| Communication apps (Slack, Zoom, Teams, etc.) | Host, best-effort | [scripts/install-desktop-apps.sh](scripts/install-desktop-apps.sh) |

Full rationale: [docs/classification.md](docs/classification.md).

## kv-backend Local Environment

kv-backend already ships its own, authoritative local-services stack at
`<kv-backend>/preload-docker-compose/`. [scripts/kv-backend.sh](scripts/kv-backend.sh)
(wired to `make kv-*`) drives that stack — it never modifies anything
inside the kv-backend repo, it only runs `mvn`/`docker compose`/its
existing `quick-setup.sh` from within it.

### Prerequisites (one-time)
1. Clone kv-backend, e.g. to `$HOME/workspace/repos/kv-backend` (or set
   `KV_BACKEND_DIR` in `.env` to wherever it's cloned).
2. The preload images tarball must be present at
   [../assets/preload_kv.tar.gz](../assets/preload_kv.tar.gz) (override the
   path with `KV_PRELOAD_TAR` in `.env` if you keep it elsewhere). `make
   kv-up` (and `make kv-load-images`) auto-run `docker load -i` on it the
   first time any of `kv_rabbitmq:preload_v1`, `kv_cassandra:preload_v1`,
   `kv_portal:preload_v1` is missing — subsequent runs skip this since the
   images are already loaded. Expect this step to take several minutes on
   first run (~750MB tarball).
3. These images are built for `linux/amd64` — on Apple Silicon, enable
   "Use Rosetta for x86/amd64 emulation" in Docker Desktop settings first.

> **Note:** a 750MB binary in `assets/` is too large for a normal git
> remote (GitHub rejects files over 100MB without Git LFS). Keep it
> `.gitignore`d and distribute it out-of-band (shared drive, artifact
> storage, LFS) rather than committing it directly.

### Commands
| Command | What it does |
|---|---|
| `make kv-load-images` | `docker load`s the preload tarball from `assets/preload_kv.tar.gz`. Skipped automatically if images already loaded. |
| `make kv-up` | Runs `kv-load-images` if needed, builds kv-backend's WARs (`mvn package install`, skipped if already built), and runs `docker compose up -d` from `preload-docker-compose` |
| `make kv-init` | **First time only.** Runs kv-backend's own `quick-setup.sh` (MySQL/Cassandra/Solr init). Destructive to existing local data — don't re-run casually. |
| `make kv-verify` | Checks each service port is reachable |
| `make kv-status` | `docker compose ps` for the kv-backend stack |
| `make kv-logs` | `docker compose logs -f` for the kv-backend stack |
| `make kv-down` | `docker compose down` |

### Local Service Access

| Service | URL / Address | Credentials |
|---|---|---|
| Portal (Tomcat) | http://localhost:8080/portal | system_2 / admin |
| MySQL | localhost:43306 | root / root, kv / kv (db `kv`) |
| RabbitMQ management | http://localhost:45672 | admin / admin |
| RabbitMQ AMQP | localhost:35672 | admin / admin |
| Cassandra | localhost:59042 | — |
| Solr | http://localhost:58983 | — |
| Memcached | localhost:41211 | — |

These match kv-backend's `preload-docker-compose/docker-compose.yml`
exactly — they are intentionally different from the ports/images you'd get
from a generic MySQL/Cassandra/RabbitMQ compose stack, so nothing here
duplicates or conflicts with kv-backend's own setup.

## Devcontainer Template

[.devcontainer/devcontainer.json](.devcontainer/devcontainer.json) is a
generic Java 17 + Maven + Docker CLI starting template for VS Code's
"Reopen in Container". It is independent of kv-backend's own
`preload-docker-compose` stack (which needs to run on the host, not nested
inside a container) — use it only if you want an isolated build shell.

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
