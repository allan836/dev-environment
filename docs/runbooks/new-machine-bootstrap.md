# Runbook: New Machine Bootstrap

## Purpose

Provide the end-to-end procedure for turning any laptop or workstation into
a fully configured developer environment using this repository. This runbook
reflects the current automated setup — no manual OS installation or
tool-by-tool configuration is required.

## Scope

Covers the complete provisioning sequence from a bare laptop (any supported
host OS) to a running Ubuntu 24.04 developer VM with all tools installed.
Does not cover recovering from data loss — see
[disaster-recovery.md](./disaster-recovery.md).

## Prerequisites

The host machine (the laptop running `provision.sh`) needs only two things:

| Requirement | How to check |
|---|---|
| `git` installed | `git --version` |
| Internet access | `curl -I https://github.com` |

Everything else — Vagrant, the hypervisor, Ubuntu itself, all developer
tools — is installed automatically by `provision.sh`.

**Supported host operating systems:**
- macOS (Homebrew must be installed: https://brew.sh)
- Ubuntu / Debian
- Fedora

## Procedure

### Step 1 — Clone the repository

```bash
git clone https://github.com/allan836/dev-environment.git
cd dev-environment
```

### Step 2 — Run the provisioner

```bash
./provision.sh
```

That is the entire procedure. The script handles everything from this point
forward:

| What happens | Detail |
|---|---|
| Vagrant installed on host | Via `apt`/`dnf`/`brew` or HashiCorp direct download |
| Hypervisor installed | VirtualBox tried first, then KVM/libvirt, then VMware |
| Ubuntu 24.04 VM created | No ISO needed — uses Ubuntu cloud image |
| cloud-init runs | Creates developer user, sets timezone, installs base packages |
| Ansible playbook runs | Installs Docker, Java, Node, Python, Terraform, kubectl, AWS/Azure/gcloud CLIs, VS Code, GitHub CLI, openfortivpn, DBeaver |
| SSH key generated | Inside the VM — printed to screen |
| kv-backend cloned | Requires GitHub SSH key (see Step 3) |
| Docker services started | `make kv-up` — MySQL, RabbitMQ, Cassandra, Solr, Memcached, Tomcat |
| Verification printed | All tools and services reported with versions |

### Step 3 — Add SSH key to GitHub (only manual step)

During provisioning `provision.sh` pauses and prints the VM's public SSH
key. Add it to your GitHub account before pressing Enter:

1. Copy the `ssh-ed25519 ...` line printed on screen.
2. Go to GitHub → Settings → SSH and GPG keys → New SSH key.
3. Paste the key and save.
4. Press Enter in the terminal to continue.

This is the only step that cannot be automated — GitHub requires you to
authenticate as yourself.

### Step 4 — Verify

Verification runs automatically at the end of provisioning. To re-run it
manually:

```bash
cd vm
vagrant ssh -c "~/dev-environment/workstation-bootstrap/scripts/verify.sh"
```

### Provisioner options

```bash
./provision.sh --cpu 6 --ram 12288    # more resources (default: 4 CPU, 8 GB)
./provision.sh --destroy              # wipe VM and reprovision from scratch
./provision.sh --skip-ansible         # boot VM only, no tool install
./provision.sh --help                 # full usage
```

## Day-to-day VM use

```bash
cd vm

vagrant ssh          # open a shell inside the VM
vagrant suspend      # pause VM (saves state, frees RAM)
vagrant resume       # wake the VM back up
vagrant halt         # shut the VM down cleanly
vagrant up           # start the VM (if halted or after a reboot)
vagrant destroy -f   # delete the VM entirely (re-run provision.sh to rebuild)
```

## Architecture summary

```
Laptop (any OS)
    │
    ▼
provision.sh
    │  installs Vagrant
    │  installs hypervisor (VirtualBox → KVM → VMware)
    ▼
Ubuntu 24.04 VM (via Vagrant)
    │
    ├── cloud-init  → user, SSH, timezone, base packages
    │
    └── Ansible playbook
            ├── Docker Engine + Compose
            ├── Java 8 + 17 (SDKMAN), Maven
            ├── Node 18/20/22/24 (nvm), pnpm
            ├── Python (pyenv), pipenv, uv
            ├── Terraform + OpenTofu
            ├── kubectl, Helm, k9s
            ├── AWS CLI v2, Azure CLI, gcloud
            ├── VS Code, GitHub CLI, openfortivpn, DBeaver
            └── kv-backend clone + Docker services
```

## Existing workstation (no VM needed)

If you are already running Ubuntu, Debian, macOS, or Fedora and do not need
a VM, use `workstation-bootstrap/` directly:

```bash
cd workstation-bootstrap
./setup.sh      # installs all tools on the host
make kv-up      # starts kv-backend docker-compose stack
make kv-init    # first-time DB/Cassandra/Solr init
make kv-verify  # checks all services are reachable
```

## References

- [provision.sh](../../provision.sh)
- [vm/Vagrantfile](../../vm/Vagrantfile)
- [ansible/playbook.yml](../../ansible/playbook.yml)

## Related Documents

- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [docs/runbooks/disaster-recovery.md](./disaster-recovery.md)
- [docs/runbooks/service-lifecycle.md](./service-lifecycle.md)
- [workstation-bootstrap/README.md](../../workstation-bootstrap/README.md)
