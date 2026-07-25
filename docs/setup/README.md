# Setup Guides

## Purpose

Index of manual, step-by-step setup guides for every tool and service
supported on this workstation. Each guide is the authoritative manual
procedure that automation (Bash/Ansible/Compose) is intended to eventually
replace.

## Scope

Covers installation and initial configuration of host tooling and
containerized services on Fedora Workstation. Does not cover ongoing
operations (see [docs/runbooks](../runbooks/README.md)) or issue resolution
(see [docs/troubleshooting](../troubleshooting/README.md)).

## Prerequisites

- Fedora Workstation installed — start with
  [fedora-base-setup.md](./fedora-base-setup.md) before any other guide.

## Contents

| Guide | Covers |
|---|---|
| [fedora-base-setup.md](./fedora-base-setup.md) | Base OS configuration, DNF, updates |
| [git-github-ssh.md](./git-github-ssh.md) | Git, GitHub CLI/auth, SSH keys |
| [docker.md](./docker.md) | Docker Engine and Docker Compose |
| [podman.md](./podman.md) | Podman as an optional Docker alternative |
| [kubernetes.md](./kubernetes.md) | `kubectl` and local cluster options |
| [terraform-opentofu.md](./terraform-opentofu.md) | Terraform and OpenTofu CLIs |
| [languages-runtimes.md](./languages-runtimes.md) | Python, Node.js, Java |
| [cloud-clis.md](./cloud-clis.md) | AWS CLI, Azure CLI, Google Cloud CLI |
| [ides.md](./ides.md) | VS Code, JetBrains IDEs |
| [databases-services.md](./databases-services.md) | PostgreSQL, MySQL, MongoDB, Cassandra, Redis, RabbitMQ, Neo4j, Qdrant, Ollama, Open WebUI |

## Guide Structure Convention

Every guide in this directory follows the same internal structure in
addition to the standard five sections: **Manual Installation Steps**,
**Configuration**, **Verification**, and **Automation Status** (linking to
the corresponding Ansible role or Compose service once implemented, per
[ARCHITECTURE.md](../../ARCHITECTURE.md) principle 7).

## References

- [Fedora Documentation](https://docs.fedoraproject.org/)

## Related Documents

- [docs/architecture/README.md](../architecture/README.md)
- [docs/automation/README.md](../automation/README.md)
- [docs/runbooks/new-machine-bootstrap.md](../runbooks/new-machine-bootstrap.md)
