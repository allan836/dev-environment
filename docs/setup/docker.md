# Docker Setup

## Purpose

Reference guide for Docker Engine and Docker Compose inside the developer VM.

## Scope

Covers Docker Engine, Docker Compose plugin, and the developer user group
setup. Does not cover individual service Compose stacks — see
[databases-services.md](./databases-services.md).

## Prerequisites

- Developer VM is running (`./provision.sh` completed or `cd vm && vagrant up`).
- SSH into the VM: `cd vm && vagrant ssh`.

## Automation Status

**Fully automated** by the Ansible `docker` role.
Source: [`ansible/roles/docker/tasks/main.yml`](../../ansible/roles/docker/tasks/main.yml).

Provisioning installs Docker Engine via the official Docker apt repository
and adds the developer user to the `docker` group automatically.

## Manual Steps (fallback only)

If the Ansible role failed or you are setting up without `provision.sh`:

```bash
# Add Docker GPG key
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker apt repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list

# Install
sudo apt-get update
sudo apt-get install -y \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

# Enable and add user to group
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

Log out and back in (or `newgrp docker`) for group membership to take effect.

## Verification

```bash
docker version
docker compose version
docker run --rm hello-world
```

## References

- [Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)

## Related Documents

- [ansible/roles/docker/tasks/main.yml](../../ansible/roles/docker/tasks/main.yml)
- [databases-services.md](./databases-services.md)
- [docs/troubleshooting/docker.md](../troubleshooting/docker.md)
