# Runbooks

## Purpose

Index of operational procedures for this developer environment: provisioning
it from scratch, recovering from failure, backing up state, and managing the
lifecycle of containerized services.

## Scope

Covers operational, task-oriented procedures. Does not cover installation
rationale or step-by-step tool setup — see [docs/setup](../setup/README.md).
Does not cover issue diagnosis — see [docs/troubleshooting](../troubleshooting/README.md).

## Prerequisites

- [docs/architecture/README.md](../architecture/README.md) for system
  design context.

## Contents

| Runbook | When to use |
|---|---|
| [new-machine-bootstrap.md](./new-machine-bootstrap.md) | Setting up a brand-new developer environment on any host OS — `./provision.sh` |
| [disaster-recovery.md](./disaster-recovery.md) | Full recovery after VM loss, hardware failure, or data corruption |
| [backup-restore.md](./backup-restore.md) | Backing up and restoring stateful Docker service volumes |
| [service-lifecycle.md](./service-lifecycle.md) | Starting, stopping, and updating kv-backend Docker services |

## Quick Reference

```bash
# Provision from scratch (first time or rebuild)
./provision.sh

# SSH into the running VM
cd vm && vagrant ssh

# Suspend / resume the VM
cd vm && vagrant suspend
cd vm && vagrant resume

# Destroy and reprovision
./provision.sh --destroy

# Verify all tools inside VM
vagrant ssh -c "~/dev-environment/workstation-bootstrap/scripts/verify.sh"
```

## References

- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [provision.sh](../../provision.sh)

## Related Documents

- [docs/setup/README.md](../setup/README.md)
- [docs/troubleshooting/README.md](../troubleshooting/README.md)
- [docs/security/README.md](../security/README.md)
