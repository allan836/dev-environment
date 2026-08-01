# Setup Guides

## Purpose

Index of reference guides documenting how each tool and service is
configured in this developer environment. These guides serve two purposes:

1. **Reference** — understand what was installed and why, and how to
   configure a tool after provisioning.
2. **Manual fallback** — if automation fails for a specific tool, the guide
   documents how to install it by hand.

## Important: automation handles installation

**You do not need to follow these guides to set up a new machine.**
Run `./provision.sh` from the repository root — it installs everything
automatically. See
[docs/runbooks/new-machine-bootstrap.md](../runbooks/new-machine-bootstrap.md)
for the full provisioning procedure.

These guides are relevant when:
- You need to understand what was installed inside the VM.
- You are troubleshooting a specific tool that Ansible failed to install.
- You are configuring a tool after provisioning (e.g. signing into GitHub
  CLI, configuring AWS credentials).
- You are using `workstation-bootstrap/setup.sh` directly on an existing
  machine without the VM.

## Scope

Covers installation and initial configuration of tools inside the Ubuntu
VM (or on a supported host OS when using `workstation-bootstrap/` directly).
Does not cover ongoing operations — see
[docs/runbooks](../runbooks/README.md).

## Contents

| Guide | Covers | Ansible role |
|---|---|---|
| [git-github-ssh.md](./git-github-ssh.md) | Git config, GitHub CLI auth, SSH key management | `developer_tools` |
| [docker.md](./docker.md) | Docker Engine and Docker Compose | `docker` |
| [kubernetes.md](./kubernetes.md) | `kubectl`, Helm, k9s | `kubectl` |
| [terraform-opentofu.md](./terraform-opentofu.md) | Terraform and OpenTofu CLIs | `terraform` |
| [languages-runtimes.md](./languages-runtimes.md) | Python (pyenv), Node.js (nvm), Java (apt) | `python`, `node`, `java` |
| [cloud-clis.md](./cloud-clis.md) | AWS CLI v2, Azure CLI, Google Cloud CLI | `cloud_clis` |
| [ides.md](./ides.md) | VS Code (automated), JetBrains (manual) | `developer_tools` |
| [databases-services.md](./databases-services.md) | MySQL, Cassandra, Solr, RabbitMQ, Memcached, MailHog, Tomcat | `kv_backend` (Compose) |

## Automation status

All tools listed above are installed automatically by the Ansible playbook
when you run `./provision.sh`. The "Ansible role" column above shows which
role is responsible. Source: [`ansible/roles/`](../../ansible/roles/).

## References

- [ansible/playbook.yml](../../ansible/playbook.yml)

## Related Documents

- [docs/automation/README.md](../automation/README.md)
- [docs/runbooks/new-machine-bootstrap.md](../runbooks/new-machine-bootstrap.md)
- [docs/architecture/overview.md](../architecture/overview.md)
