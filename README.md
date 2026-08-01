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
2. Installs Vagrant (if not present or version too old)
3. Detects available hypervisors — VirtualBox → KVM → VMware — and selects the best one
4. Creates an Ubuntu 24.04 LTS VM with the chosen hypervisor
5. Runs an Ansible playbook that installs all developer tools inside the VM
6. Pauses once to show the VM's SSH public key — add it to GitHub (the only manual step)
7. Clones kv-backend, starts Docker services
8. Verifies the environment and prints a summary

Total time: approximately 15–25 minutes on first run.

---

## Prerequisites

| What | Required |
|------|----------|
| git  | Yes — you used it to clone this repo |
| curl or wget | Yes |
| Internet access | Yes |

Vagrant, the hypervisor, Ubuntu, and every developer tool are installed by the script.

---

## Options

```bash
./provision.sh --cpu 6 --ram 12288   # more resources (default: 4 vCPU / 8 GB)
./provision.sh --destroy             # wipe the VM and reprovision from scratch
./provision.sh --skip-ansible        # boot the VM only, skip tool installation
./provision.sh --help                # full usage
```

---

## After provisioning

```bash
cd vm && vagrant ssh          # SSH into the VM
cd vm && vagrant suspend      # suspend the VM
cd vm && vagrant halt         # shut the VM down cleanly
./provision.sh --destroy      # destroy and reprovision from scratch
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
| IaC | Terraform, kubectl, Helm |
| Cloud CLIs | AWS CLI, Azure CLI, Google Cloud CLI |
| Other | tmux, fzf, ripgrep, bat, httpie |

---

## Supported host platforms

| Host OS | Hypervisor |
|---------|-----------|
| macOS   | VirtualBox (default), VMware Fusion |
| Ubuntu / Debian | VirtualBox, KVM/libvirt (native, faster), VMware Workstation |
| Fedora  | VirtualBox, KVM/libvirt (native, faster), VMware Workstation |

The provisioner detects what is available and selects automatically.
You do not need to install or configure any hypervisor manually.

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
