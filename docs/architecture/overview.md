# System Overview

## Purpose

Describe the layered structure of the workstation and how components relate
to one another.

## Scope

Covers the host, tooling, and services layers at a conceptual level. Does
not cover installation steps or configuration file contents.

## Prerequisites

- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [docs/architecture/README.md](./README.md)

## Layers

### 1. Host Layer

Fedora Workstation itself: base OS packages, DNF configuration, shell
environment, SSH client/server, Git. Configured directly on the host because
these are prerequisites for everything else (including running Ansible
itself).

### 2. Tooling Layer

Developer tooling installed on the host via Ansible roles: language
runtimes (Python, Node.js, Java), cloud CLIs (AWS, Azure, GCP), IaC tools
(Terraform, OpenTofu, `kubectl`), and IDEs (VS Code, JetBrains Toolbox).
Installed on the host (not containerized) because they are the primary
interface the developer interacts with daily.

### 3. Services Layer

Backing services used during development, run as containers via Docker
Compose (Podman Compose as an optional alternative): PostgreSQL, MySQL,
MongoDB, Cassandra, Redis, RabbitMQ, Neo4j, Qdrant, Ollama, Open WebUI.
Containerized to keep the host clean, allow multiple versions side by side,
and make teardown/rebuild trivial.

## Component Map

```text
┌─────────────────────────────────────────────────────────┐
│ Host Layer: Fedora, shell, SSH, Git                      │
│  ┌─────────────────────────────────────────────────────┐ │
│  │ Tooling Layer: Python/Node/Java, AWS/Azure/GCP CLI,  │ │
│  │ Terraform/OpenTofu, kubectl, VS Code, JetBrains       │ │
│  │  ┌───────────────────────────────────────────────┐   │ │
│  │  │ Services Layer (Docker/Podman Compose):        │   │ │
│  │  │ Postgres · MySQL · MongoDB · Cassandra · Redis  │   │ │
│  │  │ RabbitMQ · Neo4j · Qdrant · Ollama · Open WebUI │   │ │
│  │  └───────────────────────────────────────────────┘   │ │
│  └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## Orchestration Boundary

Kubernetes is used for workloads the developer wants to run/test in a
cluster-like environment (e.g. a local `kind`/`minikube` cluster), separate
from the always-on local services managed by Docker Compose. This boundary
is documented further in [docs/setup/kubernetes.md](../setup/kubernetes.md).

## References

- [C4 Model](https://c4model.com/)

## Related Documents

- [docs/architecture/networking.md](./networking.md)
- [docs/architecture/storage.md](./storage.md)
- [docs/setup/README.md](../setup/README.md)
- [docs/decisions/README.md](../decisions/README.md)
