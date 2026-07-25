# Target Architecture

## Principle

> The machine is thin. The project defines the environment.

Instead of installing every database and service directly onto each
engineer's laptop (the original approach), the host only carries what is
needed to *run* project environments. Everything project-specific is
declared in the project's own repository.

```text
Host (macOS or Fedora)          Project Repository
┌─────────────────────┐        ┌───────────────────────────┐
│ Docker               │        │ docker-compose.yml         │
│ Git                  │  --->  │ .devcontainer/              │
│ VS Code              │        │ Makefile                     │
│ Node/Python/Java     │        │ scripts/                      │
│ Cloud CLIs (AWS/TF)  │        │ .env.example                  │
└─────────────────────┘        └───────────────────────────┘
```

- **Host layer** — this repository's `setup.sh` and `scripts/*.sh`.
- **Project layer** — `docker-compose.yml` + `.devcontainer/` in this
  repository serve as the reusable template every project copies/extends.

## OS Support Strategy

Two package managers are supported behind one interface:

| OS | Package manager | Detected via |
|---|---|---|
| macOS | Homebrew | `$OSTYPE == darwin*` |
| Fedora | `dnf` | `$OSTYPE == linux-gnu*` + `/etc/fedora-release` |

`setup.sh` performs OS detection once and exports it as `$OS_FAMILY`
(`mac` or `fedora`); every script under `scripts/` branches on that
variable instead of re-detecting the OS.

Ansible is intentionally **not** introduced yet — plain Bash is judged
"good enough for now" for a two-OS, single-host bootstrap, per the phased
plan in [../README.md](../README.md#roadmap). Revisit if a third OS or
fleet management is needed.

## Local DNS & HTTPS

The original doc's `dnsmasq` + `/etc/resolver/test` + `nginx` combo is a
macOS-specific mechanism for local `.test` domains and HTTPS termination.
It remains **host-specific, opt-in, and undocumented-by-default** here
because:

- Fedora's equivalent (`systemd-resolved`, NetworkManager's dnsmasq
  integration) is configured differently and isn't needed by most
  containerized projects.
- Projects that need local HTTPS/DNS should prefer a per-project reverse
  proxy container (e.g. `nginx`/Traefik service in that project's own
  `docker-compose.yml`) over a shared host-wide `.test` TLD.

macOS engineers who still need it can run
`scripts/install-desktop-apps.sh --with-local-dns` — see that script's
header comment.

## Devcontainer

[`.devcontainer/devcontainer.json`](../.devcontainer/devcontainer.json) is a
template: a project copies this folder, points `dockerComposeFile` at its
own compose file, and engineers get a fully configured environment by
clicking "Reopen in Container" in VS Code — no host installs of
language-specific tooling required for that project.

## References

- [The Twelve-Factor App](https://12factor.net/) — dev/prod parity.
- [VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers)

## Related Documents

- [docs/classification.md](./classification.md)
- [../docker-compose.yml](../docker-compose.yml)
- [../.devcontainer/devcontainer.json](../.devcontainer/devcontainer.json)
- [../README.md](../README.md)
