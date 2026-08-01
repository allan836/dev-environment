# Developer Environment Provisioner

A single command provisions a complete, reproducible Ubuntu development environment on any laptop.

```bash
git clone https://github.com/<your-org>/dev-environment.git
cd dev-environment
./provision.sh
```

That is all. Everything else is automated.

---

## What happens

`provision.sh` runs in order:

1. Detects your host OS (macOS, Ubuntu, Debian, Fedora)
2. Probes available virtualization providers — **Multipass** → **libvirt** → **Incus** — and selects the first one that works
3. Installs the selected provider if it is not already present
4. Creates an Ubuntu 24.04 LTS VM with the chosen provider
5. Waits for SSH readiness
6. Runs an Ansible playbook over SSH that installs all developer tools inside the VM
7. Pauses once to show the VM's SSH public key — add it to GitHub (the only manual step)
8. Clones kv-backend, starts Docker services
9. Verifies the environment and prints a summary

Total time: approximately 15–25 minutes on first run.

---

## Prerequisites

| What | Required |
|------|----------|
| git  | Yes — you used it to clone this repo |
| curl or wget | Yes |
| Internet access | Yes |

The provider (Multipass, libvirt, or Incus), Ansible, Ubuntu, and every developer tool are installed by the script.

---

## Options

```bash
./provision.sh --cpu 6 --ram 12288   # more resources (default: 4 vCPU / 8 GB)
./provision.sh --disk 100             # larger disk (default: 40 GB)
./provision.sh --provider libvirt     # force a specific provider
./provision.sh --skip-ansible         # boot the VM only, skip tool installation
./provision.sh --destroy              # wipe the VM and reprovision from scratch
./provision.sh --help                 # full usage
```

---

## After provisioning

```bash
# SSH into the VM (IP is printed by provision.sh)
ssh -i ~/.ssh/dev-env ubuntu@<VM_IP>

# Stop / start the VM (provider-specific)
multipass stop dev-env                # Multipass
sudo virsh shutdown dev-env           # libvirt
incus stop dev-env                    # Incus

# Destroy and reprovision from scratch
./provision.sh --destroy
```

Inside the VM, the kv-backend services are managed via:

```bash
cd ~/dev-environment/workstation-bootstrap
make kv-up      # start MySQL, Cassandra, Solr, RabbitMQ, Memcached, Tomcat
make kv-init    # first-time DB initialisation (run once)
make kv-verify  # check all services are reachable
make kv-down    # stop services
```

---

## What is installed inside the VM

| Category | Tools |
|---|---|
| Version control | Git, GitHub CLI |
| Containers | Docker, Docker Compose |
| Java (kv-backend) | OpenJDK **8** and OpenJDK **17** — both coexist; switch with `sudo update-alternatives --config java` |
| Build tool | Maven 3.9.x |
| App server | **Tomcat 9** (Tomcat 10/11 are NOT installed — kv-backend compatibility) |
| Node.js | nvm with Node 18, 20, 22 (default: 20); pnpm |
| Python | pyenv with Python 3.12; pipenv, uv |
| IaC | Terraform, OpenTofu |
| Kubernetes | kubectl, Helm, k9s |
| Cloud CLIs | AWS CLI, Azure CLI, Google Cloud CLI |
| Other | VS Code, tmux, fzf, ripgrep, openfortivpn, DBeaver |

---

## Supported host platforms

| Host OS | Preferred Provider | Fallback |
|---------|-------------------|----------|
| macOS   | Multipass | — |
| Ubuntu / Debian | Multipass | libvirt (native KVM, faster), Incus |
| Fedora  | Multipass | libvirt (native KVM, faster), Incus |

The provisioner detects what is available and selects automatically.
You can force a specific provider with `--provider`.
You do not need to install or configure any provider manually.

---

## Running without a VM (existing machine)

If you are already on Ubuntu, macOS, or Fedora and do not need a VM:

```bash
cd workstation-bootstrap
./setup.sh
make kv-up
make kv-init
make kv-verify
```

---

## Version configuration

All software versions are in one place: [`config.env`](./config.env).

To upgrade a tool, change its version there.
Ansible reads versions from [`ansible/group_vars/all/versions.yml`](./ansible/group_vars/all/versions.yml) — keep both files in sync.

---

## Documentation

| Topic | Link |
|---|---|
| Architecture and design | [docs/architecture/README.md](./docs/architecture/README.md) |
| Per-tool setup guides | [docs/setup/README.md](./docs/setup/README.md) |
| Operational runbooks | [docs/runbooks/README.md](./docs/runbooks/README.md) |
| Troubleshooting | [docs/troubleshooting/README.md](./docs/troubleshooting/README.md) |
| Security and secrets | [docs/security/README.md](./docs/security/README.md) |
| Architecture decisions | [docs/decisions/README.md](./docs/decisions/README.md) |
| Direct host install | [workstation-bootstrap/README.md](./workstation-bootstrap/README.md) |

---

## Idempotency

Re-running `./provision.sh` is safe. The provisioner:

- reuses an existing VM if it is already running
- skips tools that are already installed
- never duplicates installations
- never destroys user data unless `--destroy` is passed explicitly
