# Tool Classification

This is the redesign of the original MacBook-only onboarding checklist. Every
tool from that document is placed into one of five layers, then marked as
**host** (installed directly on the engineer's machine) or **container**
(runs in Docker, defined by a project, not the workstation).

> **Note:** the container examples below (`docker compose up mongo`, etc.)
> describe the original, generic placeholder stack that used to live in
> [../docker-compose.yml](../docker-compose.yml). That file no longer
> defines any services — for kv-backend, the actual container layer is
> kv-backend's own `preload-docker-compose` stack, driven via
> `make kv-up`/`kv-init`/`kv-verify` (see [../README.md](../README.md#kv-backend-local-environment)).
> This page still reflects the general host-vs-container reasoning applied
> to the original checklist.

## 1. Core System Tools (host)

| Tool | Notes |
|---|---|
| Git | Installed via Xcode CLT (mac) / `dnf` (Fedora) |
| Docker (Desktop on mac / Engine on Fedora) | Required to run everything in layer 3 |
| GitHub CLI (`gh`) | |
| OpenVPN client | Corporate VPN access |
| AWS CLI | |
| Terraform | |
| `kubectl` | Ships with Docker Desktop (mac) or installed separately (Fedora) |
| SSH key | Generated once per machine, never shared |

## 2. Language Runtimes (host)

| Tool | Manager |
|---|---|
| Node.js | `nvm` (18, 20, 22, 24; default 20) |
| Python | `pyenv`, `pipenv`, `uv` |
| Java | `sdkman` (8 and 17; default 17) |
| Maven | `sdkman` (3.8) |
| pnpm | via `pnpm setup` |

Runtimes stay on the host because they are the developer's primary
interface and change per-project frequently; version managers already give
per-project pinning without needing a container.

## 3. Databases & Backing Services (container — moved off host)

These were previously installed with Homebrew directly on macOS. They are
now defined in [`docker-compose.yml`](../docker-compose.yml) instead:

| Service | Previous host install | Now |
|---|---|---|
| MySQL 8.0 | `brew install mysql@8.0` | `docker compose up mysql` |
| MongoDB (CE) | `brew tap/install mongodb-community` | `docker compose up mongo` |
| Cassandra | `brew install cassandra` (version pinning was broken — see Notes) | `docker compose up cassandra`, version pinned in the image tag |
| RabbitMQ | `brew services start rabbitmq` | `docker compose up rabbitmq` |
| Neo4j | `brew install neo4j` | `docker compose up neo4j` |
| nginx | `brew install nginx` | `docker compose up nginx` |
| Consul | `brew install consul` | `docker compose up consul` |

**Why move these:** version conflicts between projects, inability to pin
exact versions with Homebrew (see the original doc's Cassandra note),
difficulty reproducing on a second machine or a Fedora machine, and no
clean teardown/reset story on the host.

`consul-template` and `dnsmasq` remain host-side (see layer 1 rationale
below) since they configure the host's own networking/DNS resolution, not a
backing service a project depends on.

## 4. Dev Tools (host)

| Tool | Notes |
|---|---|
| VS Code | + CLI launcher (`code`) |
| Docker Desktop / Docker Engine | |
| Lens | Kubernetes GUI |
| DBeaver | Universal DB GUI — replaces the "TODO: local GUI for Cassandra/MySQL" from the original doc |
| MongoDB Compass | |
| Vagrant + VirtualBox | Kept for the rare case a full VM is needed |

## 5. Communication / Desktop Apps (host, best-effort automatable)

Slack, Zoom, Microsoft Teams, FortiClient, OBS, Shottr, LICEcap, Inkscape,
GIMP, LibreOffice, Google Drive, VLC, OpenShot. These are installed via
`brew install --cask` on macOS. On Fedora, equivalents are installed via
`dnf`/Flatpak where available — see
[`scripts/install-desktop-apps.sh`](../scripts/install-desktop-apps.sh) and
its inline notes on gaps (e.g. no Fedora equivalent for FortiClient/Shottr).

## Explicitly Not Host-Installed

`dnsmasq`'s local `.test` TLD resolution and `nginx`'s local reverse proxy
role are host-networking concerns tied to macOS's `/etc/resolver`
mechanism. On Fedora this is handled differently (`systemd-resolved` /
`NetworkManager` dnsmasq plugin) and is documented separately rather than
forced into the cross-platform installer — see
[docs/architecture.md](./architecture.md#local-dns--https).

## References

- Original onboarding checklist (source document, macOS-only, Homebrew-based).

## Related Documents

- [docs/architecture.md](./architecture.md)
- [docs/migration-notes.md](./migration-notes.md)
- [../docker-compose.yml](../docker-compose.yml)
- [../README.md](../README.md)
