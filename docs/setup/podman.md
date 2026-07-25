# Podman Setup (Optional)

## Purpose

Document Podman as an optional, rootless alternative to Docker for
developers who prefer a daemonless container runtime.

## Scope

Covers Podman and `podman-compose` installation and how it relates to the
Docker-based workflow used elsewhere in this repository. Does not cover
Docker itself — see [docs/setup/docker.md](./docker.md).

## Prerequisites

- [docs/setup/fedora-base-setup.md](./fedora-base-setup.md) completed.
- Decide whether Podman will replace or coexist with Docker on this machine
  — see [docs/decisions](../decisions/README.md) for the rationale behind
  Docker as the default.

## Manual Installation Steps

1. Install Podman and Compose support (Podman is present by default on many
   Fedora installs; this ensures it and Compose compatibility are present):
   ```bash
   sudo dnf install -y podman podman-compose podman-docker
   ```
2. (Optional) Enable the Podman socket for tools expecting the Docker API:
   ```bash
   systemctl --user enable --now podman.socket
   ```

## Configuration

- Podman runs rootless by default for the invoking user; no `docker` group
  membership is required.
- Compose files under [docker/compose](../../docker/compose) are written to
  be compatible with both `docker compose` and `podman-compose` where
  practical; exceptions are noted per stack in
  [docs/setup/databases-services.md](./databases-services.md).

## Verification

```bash
podman version
podman run --rm hello-world
podman-compose version
```

## Automation Status

Not yet automated. Docker remains the default runtime for automation; Podman
support is tracked as an optional parity target in [ROADMAP.md](../../ROADMAP.md).

## References

- [Podman Documentation](https://docs.podman.io/)

## Related Documents

- [docs/setup/docker.md](./docker.md)
- [docs/architecture/overview.md](../architecture/overview.md)
- [docs/decisions/README.md](../decisions/README.md)
