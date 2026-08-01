# System Overview

## Purpose

Describe the layered structure of the developer environment and how
components relate to one another.

## Scope

Covers the host, VM, tooling, and services layers at a conceptual level.
Does not cover installation steps or configuration file contents.

## Prerequisites

- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [docs/architecture/README.md](./README.md)

## Layers

### 1. Host Layer

The developer's physical laptop (any OS: macOS, Ubuntu, Debian, or Fedora).
The host runs only three things managed by this repository:

- **git** — to clone this repository (must be pre-installed).
- **Vagrant** — installed automatically by `provision.sh`.
- **A hypervisor** — VirtualBox, KVM/libvirt, or VMware, installed
  automatically by `provision.sh` in that order.

The developer's host OS is otherwise untouched. No developer tools are
installed directly on the laptop.

### 2. VM Layer

An **Ubuntu 24.04 LTS** virtual machine managed by Vagrant. Created
automatically by `provision.sh`. This is where all developer work happens.
The VM is reproducible and disposable — destroying and reprovisioning it
returns to a clean known state.

The VM is created from an Ubuntu cloud image (no ISO installer required)
and configured on first boot by **cloud-init** (`vm/cloud-init/user-data`):
user account, SSH key, base packages, timezone.

### 3. Tooling Layer

Developer tools installed **inside the VM** by the **Ansible playbook**
(`ansible/playbook.yml`). Each tool has its own Ansible role:

| Role | Tools installed |
|---|---|
| `docker` | Docker Engine, Docker Compose plugin |
| `java` | Java 8 + 17 (SDKMAN), Maven |
| `node` | Node 18/20/22/24 (nvm), pnpm |
| `python` | pyenv, Python 3.12, pipenv, uv |
| `terraform` | Terraform, OpenTofu |
| `kubectl` | kubectl, Helm, k9s |
| `cloud_clis` | AWS CLI v2, Azure CLI, Google Cloud CLI |
| `developer_tools` | VS Code, GitHub CLI, openfortivpn, DBeaver, shell tools |
| `kv_backend` | kv-backend clone, Docker image load, .env setup |

### 4. Services Layer

Backing services for kv-backend development, run as containers inside the
VM via Docker Compose. Managed by `workstation-bootstrap/Makefile`:

| Service | Technology |
|---|---|
| MySQL | kv-backend relational database |
| Cassandra | Wide-column / time-series data |
| Solr | Full-text search |
| RabbitMQ | Message broker |
| Memcached | Cache/session store |
| MailHog | Local mail catcher |
| Tomcat/portal | kv-backend portal application |

## Full stack diagram

```
┌──────────────────────────────────────────────────────────────────┐
│  HOST (macOS / Ubuntu / Debian / Fedora)                         │
│                                                                  │
│   git clone + ./provision.sh                                     │
│       │                                                          │
│       ├── Vagrant (installed by provision.sh)                    │
│       └── Hypervisor: VirtualBox → KVM → VMware (auto-selected) │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐   │
│  │  Ubuntu 24.04 LTS VM  (managed by Vagrant)                │   │
│  │                                                           │   │
│  │   cloud-init (first boot): user, SSH, base packages       │   │
│  │                                                           │   │
│  │   Ansible roles: Docker, Java, Node, Python,              │   │
│  │     Terraform, kubectl, cloud CLIs, dev tools,            │   │
│  │     kv-backend                                            │   │
│  │                                                           │   │
│  │  ┌─────────────────────────────────────────────────────┐  │   │
│  │  │  Docker Compose (kv-backend services)                │  │   │
│  │  │  MySQL · Cassandra · Solr · RabbitMQ                 │  │   │
│  │  │  Memcached · MailHog · Tomcat/portal                 │  │   │
│  │  └─────────────────────────────────────────────────────┘  │   │
│  └───────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

## Orchestration boundary

Kubernetes tooling (`kubectl`, Helm, k9s) is installed inside the VM for
running and testing workloads in a cluster-like environment (e.g. a local
`kind` or `minikube` cluster), separate from the always-on local services
managed by Docker Compose. See [docs/setup/kubernetes.md](../setup/kubernetes.md).

## References

- [C4 Model](https://c4model.com/)
- [Vagrant documentation](https://developer.hashicorp.com/vagrant/docs)
- [cloud-init documentation](https://cloudinit.readthedocs.io/)

## Related Documents

- [docs/architecture/networking.md](./networking.md)
- [docs/architecture/storage.md](./storage.md)
- [docs/decisions/README.md](../decisions/README.md)
- [docs/automation/README.md](../automation/README.md)
