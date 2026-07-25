# Docker Setup

## Purpose

Install and configure Docker Engine and Docker Compose as the primary
container runtime for local services on this workstation.

## Scope

Covers Docker Engine, Docker Compose plugin, and rootless-vs-root usage
considerations. Does not cover Podman (the optional alternative) — see
[docs/setup/podman.md](./podman.md). Does not cover individual service
Compose stacks — see [docs/setup/databases-services.md](./databases-services.md).

## Prerequisites

- [docs/setup/fedora-base-setup.md](./fedora-base-setup.md) completed.

## Manual Installation Steps

1. Remove any conflicting packages (`podman-docker`, `moby-engine` if
   present from a previous setup).
2. Add the Docker CE repository and install:
   ```bash
   sudo dnf-3 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
   sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
   ```
3. Enable and start the daemon:
   ```bash
   sudo systemctl enable --now docker
   ```
4. Allow the current user to run Docker without `sudo`:
   ```bash
   sudo usermod -aG docker $USER
   ```
   Log out and back in for the group change to take effect.

## Configuration

- Default Docker network and storage-driver settings are left at defaults
  unless a specific service guide requires an override.
- Port allocation for containers follows [docs/architecture/networking.md](../architecture/networking.md).

## Verification

```bash
docker version
docker run --rm hello-world
docker compose version
```
Confirms the daemon is running, containers can execute, and Compose is
available.

## Automation Status

Not yet automated. Planned as an Ansible role; Compose stacks will live under
[docker/compose](../../docker/compose). See [docs/automation/docker-compose.md](../automation/docker-compose.md).

## References

- [Docker Engine install guide (Fedora)](https://docs.docker.com/engine/install/fedora/)

## Related Documents

- [docs/setup/podman.md](./podman.md)
- [docs/architecture/networking.md](../architecture/networking.md)
- [docs/automation/docker-compose.md](../automation/docker-compose.md)
- [docs/setup/databases-services.md](./databases-services.md)
