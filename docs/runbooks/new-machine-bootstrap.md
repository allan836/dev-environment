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

Everything else — the virtualization provider (Multipass, libvirt, or
Incus), Ansible, Ubuntu itself, all developer tools — is installed
automatically by `provision.sh`.

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
| Host OS detected | `lib/detect.sh` identifies macOS, Ubuntu, Debian, or Fedora |
| Provider probed and installed | Multipass → libvirt → Incus (first available wins); auto-installed if missing |
| Ubuntu 24.04 VM created | Uses Ubuntu cloud image — no ISO needed |
| cloud-init runs | Creates `ubuntu` and `developer` users, sets timezone, installs base packages |
| SSH readiness confirmed | Polls SSH port until the VM is accessible |
| Ansible playbook runs | Installs Docker, Java, Tomcat, Node, Python, Terraform, kubectl, AWS/Azure/gcloud CLIs, VS Code, GitHub CLI, openfortivpn, DBeaver |
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
ssh -i ~/.ssh/dev-env ubuntu@<VM_IP> \
  "~/dev-environment/workstation-bootstrap/scripts/verify.sh"
```

### Provisioner options

```bash
./provision.sh --cpu 6 --ram 12288    # more resources (default: 4 CPU, 8 GB)
./provision.sh --disk 100             # larger disk (default: 40 GB)
./provision.sh --provider libvirt     # force a specific provider
./provision.sh --destroy              # wipe VM and reprovision from scratch
./provision.sh --skip-ansible         # boot VM only, no tool install
./provision.sh --help                 # full usage
```

## Day-to-day VM use

After provisioning, SSH into the VM using the IP address printed by
`provision.sh`:

```bash
ssh -i ~/.ssh/dev-env ubuntu@<VM_IP>
```

VM lifecycle commands are provider-specific:

| Action | Multipass | libvirt | Incus |
|---|---|---|---|
| Stop VM | `multipass stop dev-env` | `sudo virsh shutdown dev-env` | `incus stop dev-env` |
| Start VM | `multipass start dev-env` | `sudo virsh start dev-env` | `incus start dev-env` |
| Delete VM | `multipass delete --purge dev-env` | `sudo virsh destroy dev-env && sudo virsh undefine dev-env` | `incus delete --force dev-env` |
| Get VM IP | `multipass info dev-env` | `sudo virsh domifaddr dev-env` | `incus list dev-env` |

The easiest way to destroy and reprovision:

```bash
./provision.sh --destroy
```

## Architecture summary

```
Laptop (any OS)
    │
    ▼
provision.sh
    │  probes providers: Multipass → libvirt → Incus
    │  installs selected provider (if not present)
    ▼
Ubuntu 24.04 VM (via selected provider)
    │
    ├── cloud-init  → user, SSH, timezone, base packages
    │
    └── Ansible playbook (over SSH from host)
            ├── Docker Engine + Compose
            ├── Java 8 + 17 (apt), Maven
            ├── Tomcat 9
            ├── Node 18/20/22 (nvm), pnpm
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
- [config.env](../../config.env)
- [ansible/playbook.yml](../../ansible/playbook.yml)
- [docs/decisions/0003-replace-vagrant-with-multipass-libvirt-incus.md](../decisions/0003-replace-vagrant-with-multipass-libvirt-incus.md)

## Related Documents

- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [docs/runbooks/disaster-recovery.md](./disaster-recovery.md)
- [docs/runbooks/service-lifecycle.md](./service-lifecycle.md)
- [workstation-bootstrap/README.md](../../workstation-bootstrap/README.md)
