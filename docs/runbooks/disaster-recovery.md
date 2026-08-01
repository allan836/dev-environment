# Runbook: Disaster Recovery

## Purpose

Describe how to recover full developer productivity after catastrophic loss
of the VM or the host machine (hardware failure, theft, accidental VM
deletion).

## Scope

Covers the recovery sequence and its dependencies on backups and this
repository. Does not duplicate provisioning instructions — see
[new-machine-bootstrap.md](./new-machine-bootstrap.md). Does not define
backup mechanics — see [backup-restore.md](./backup-restore.md).

## Prerequisites

- Off-machine backups exist for anything not in Git (per
  [backup-restore.md](./backup-restore.md)):
  - Docker named volumes (databases, queues)
  - SSH private key from inside the VM (`~/.ssh/id_ed25519`)
  - Any secrets stored in `workstation-bootstrap/.env`
- Access to this repository from another device or via GitHub.

## Scenario A — VM destroyed or corrupted (host is fine)

The VM is a disposable artefact. Destroying it and reprovisioning is the
normal recovery path.

```bash
cd dev-environment

# Reprovision from scratch (destroy + rebuild)
./provision.sh --destroy
```

This takes approximately 10–15 minutes. After reprovisioning:
1. Add the new VM's SSH public key to GitHub (printed during provisioning).
2. Restore Docker volume data per [backup-restore.md](./backup-restore.md).
3. Run `make kv-init` if databases are empty.
4. Run `make kv-verify` to confirm services are healthy.

## Scenario B — Host machine lost (new laptop)

1. **Get the new machine running** — any OS with `git` and internet access.
2. **Recover secrets** from your secure store (password manager or vault):
   - SSH private key (if you backed it up — see [backup-restore.md](./backup-restore.md))
   - `workstation-bootstrap/.env` values (DB credentials, remote seed config)
3. **Clone this repository and provision:**

   ```bash
   git clone https://github.com/allan836/dev-environment.git
   cd dev-environment
   ./provision.sh
   ```

4. **Add the new VM's SSH key to GitHub** when prompted.
5. **Restore stateful data** per [backup-restore.md](./backup-restore.md).
6. **Verify** — `make kv-verify` inside the VM.

## Scenario C — VM snapshot restore

If you took a VM snapshot before a breaking change, restore it directly
using your provider's snapshot command:

### Multipass

```bash
multipass restore dev-env <snapshot-name>
```

### libvirt

```bash
sudo virsh snapshot-restore dev-env <snapshot-name>
```

### Incus

```bash
incus snapshot restore dev-env <snapshot-name>
```

Taking a snapshot before risky changes is recommended. See
[backup-restore.md](./backup-restore.md) for snapshot commands per provider.

## Recovery Time Expectations

| Scenario | Expected time |
|---|---|
| VM reprovision (fast internet) | ~10–15 min |
| New host + full reprovision | ~20–30 min (includes provider install) |
| DB volume restore (depends on dump size) | Variable |

## References

- [provision.sh](../../provision.sh)
- [backup-restore.md](./backup-restore.md)

## Related Documents

- [new-machine-bootstrap.md](./new-machine-bootstrap.md)
- [backup-restore.md](./backup-restore.md)
- [docs/security/secrets-management.md](../security/secrets-management.md)
