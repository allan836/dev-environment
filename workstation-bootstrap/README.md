# Workstation Bootstrap

Part of the [dev-environment](../README.md) repository.

This subdirectory handles two things:

1. **Direct host install** — `setup.sh` installs all developer tools directly
   on an existing Ubuntu, macOS, or Fedora machine without a VM.
2. **kv-backend service management** — the Makefile drives kv-backend's Docker
   Compose stack regardless of how the environment was provisioned.

> **New developer?** Run `./provision.sh` from the repository root instead.
> It creates an isolated Ubuntu VM, installs everything automatically, and
> then uses this directory's Makefile internally. You do not need to run
> `setup.sh` manually.

## Quick Start — existing machine (no VM)

Use this path if you are already on Ubuntu, macOS, or Fedora and do not
need a VM:

```bash
cd workstation-bootstrap
./setup.sh        # installs git, docker, java 17, maven, node, python on the host
make kv-up        # loads preload Docker images + starts kv-backend stack
make kv-init      # FIRST TIME ONLY — DB/Cassandra/Solr init
make kv-verify    # checks all services are reachable
```

## What `setup.sh` installs

| Stage | What | Script |
|---|---|---|
| Core tools | Git, Docker, GitHub CLI, OpenVPN, AWS CLI, Terraform, kubectl | `scripts/install-core.sh` |
| Runtimes | Node 18/20/22/24 (nvm), Python (pyenv), Java 17 + Maven (SDKMAN), pnpm | `scripts/install-runtimes.sh` |
| Desktop apps | VS Code, DBeaver, Slack, Zoom (best-effort, non-blocking) | `scripts/install-desktop-apps.sh` |
| Verification | Checks all tools and service ports | `scripts/verify.sh` |

OS detection is automatic (macOS / Ubuntu / Debian / Fedora). Every step is
idempotent — safe to re-run.

## kv-backend Makefile targets

All commands are run from this directory (inside the VM: `cd ~/dev-environment/workstation-bootstrap`, or directly on the host):

```bash
make kv-up            # docker compose up -d (builds WARs on first run)
make kv-init          # first-time DB/Cassandra/Solr init (run once)
make kv-verify        # check all service ports are reachable
make kv-status        # docker compose ps
make kv-logs          # docker compose logs -f
make kv-down          # docker compose down
make kv-clean-slate   # wipe volumes and rebuild from zero
make kv-clean-slate-remote  # wipe and seed from Uniserver
make kv-load-images   # load preload Docker images from tarball
```

## kv-backend prerequisites

1. kv-backend must be cloned at `$HOME/workspace/repos/kv-backend`
   (or set `KV_BACKEND_DIR` in `.env`).
2. The preload images tarball must be at
   [`../assets/preload_kv.tar.gz`](../assets/preload_kv.tar.gz)
   (or set `KV_PRELOAD_TAR` in `.env`).
   `make kv-up` runs `docker load` automatically on first run.
3. On Apple Silicon: enable "Use Rosetta for x86/amd64 emulation" in
   Docker Desktop — the preload images are `linux/amd64`.

## Configuration

`setup.sh` creates `.env` from `.env.example` on first run. Edit `.env`
to set:

```bash
KV_BACKEND_DIR=~/workspace/repos/kv-backend   # path to kv-backend clone
KV_PRELOAD_TAR=../assets/preload_kv.tar.gz    # path to preload images tarball
```

## Manual steps (not automated by design)

- Sign in to work Google account, set up 2FA.
- Generate SSH key and add to GitHub: `ssh-keygen -t ed25519 -C "$(hostname)"`.
- Install FortiToken Mobile on your phone.
- Add VPN gateway credentials to openfortivpn config.

## References

- [provision.sh](../provision.sh) — full VM provisioner
- [ansible/roles/](../ansible/roles/) — Ansible roles that mirror setup.sh for the VM path

## Related Documents

- [docs/runbooks/new-machine-bootstrap.md](../docs/runbooks/new-machine-bootstrap.md)
- [docs/runbooks/service-lifecycle.md](../docs/runbooks/service-lifecycle.md)
