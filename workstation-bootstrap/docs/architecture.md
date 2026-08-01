# Workstation Bootstrap — Architecture

## Principle

> The machine is thin. The project defines the environment.

The host (or VM) carries only what is needed to *run* a project's environment.
Everything project-specific is declared in the project's own repository.

## Two paths to the same outcome

### Path A — VM provisioner (recommended for new developers)

```
Laptop (any OS)
    │
    ▼
provision.sh                       ← root of dev-environment repo
    │
    ├── Probes providers: Multipass → libvirt → Incus
    ├── Installs selected provider on host
    │
    └── Ubuntu 24.04 VM
            │
            ├── cloud-init         ← first-boot OS config
            │
            └── Ansible over SSH   ← installs all developer tools
                    │
                    └── kv_backend role calls workstation-bootstrap/
                            make kv-up, kv-init, kv-verify
```

Path A produces a fully isolated, reproducible Ubuntu VM. The developer
interacts with the VM via SSH (`ssh -i ~/.ssh/dev-env ubuntu@<VM_IP>`).
The host laptop is untouched.

### Path B — Direct host install (existing machine)

```
Existing Ubuntu / macOS / Fedora machine
    │
    ▼
workstation-bootstrap/setup.sh     ← installs tools directly on host
    │
    ▼
make kv-up → kv-backend Docker Compose stack starts
```

Path B is for developers who already have a supported OS and do not want
a VM. The same tools are installed, the same Makefile targets are used.

## Layer responsibilities

| Layer | Where | What |
|---|---|---|
| Core tools | Host (Path B) or VM (Path A) | Git, Docker, GitHub CLI, AWS CLI, Terraform, kubectl |
| Language runtimes | Host or VM | Node/nvm, Python/pyenv, Java/apt, Maven, pnpm |
| kv-backend services | Docker Compose (inside VM or host) | MySQL, RabbitMQ, Cassandra, Solr, Memcached, MailHog, Tomcat |
| Desktop apps | Host or VM | VS Code, DBeaver, Slack, Zoom (best-effort) |

## Idempotency

Every install step checks whether the tool already exists before installing.
Every `make` target is safe to re-run. `make kv-clean-slate` is the escape
hatch when state is unknown — it wipes and rebuilds from zero.

## Related Documents

- [provision.sh](../../provision.sh)
- [config.env](../../config.env)
- [ansible/playbook.yml](../../ansible/playbook.yml)
- [docs/runbooks/new-machine-bootstrap.md](../../docs/runbooks/new-machine-bootstrap.md)
- [docs/runbooks/service-lifecycle.md](../../docs/runbooks/service-lifecycle.md)
