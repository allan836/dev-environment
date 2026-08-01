# Runbook: Backup & Restore

## Purpose

Define what must be backed up outside of Git, and the approach for backing
up and restoring stateful data from inside the developer VM.

## Scope

Covers backup targets and restore procedures for the VM and its services.
Does not cover disaster recovery sequencing — see
[disaster-recovery.md](./disaster-recovery.md).

## Prerequisites

- VM is running: `cd vm && vagrant up && vagrant ssh`

## What Is and Is Not Backed Up by Git

Everything in this repository is already backed up by being in Git/GitHub.
The following are **not** in Git and require a separate strategy:

| Item | Location inside VM | Backup approach |
|---|---|---|
| MySQL databases | Docker named volume | `mysqldump` → off-machine |
| Cassandra data | Docker named volume | `nodetool snapshot` or CQL export |
| Solr indexes | Docker named volume | Re-indexable from source; backup optional |
| RabbitMQ queues/definitions | Docker named volume | Management API export |
| SSH private key | `~/.ssh/id_ed25519` | Secure password manager (1Password, Bitwarden, etc.) |
| `.env` credentials | `workstation-bootstrap/.env` | Secure password manager |
| Uploaded/built WARs | `kv-backend/` dir | Re-buildable from source |

## VM snapshot (simplest full backup)

Before any risky change (migration, clean-slate, upgrade), take a VM
snapshot. This preserves the entire VM state — all Docker volumes, configs,
and tool state — and can be restored in seconds.

```bash
cd vm

# Save snapshot
vagrant snapshot save before-migration

# List snapshots
vagrant snapshot list

# Restore snapshot
vagrant snapshot restore before-migration
```

Vagrant snapshots live on the host disk. They do not survive `vagrant
destroy`. For off-machine backup, use database dumps instead.

## MySQL backup and restore

```bash
# Inside the VM — dump all databases
docker exec mysql-container mysqldump \
  -u root -p<password> --all-databases \
  > ~/backups/mysql-$(date +%Y%m%d).sql

# Restore
docker exec -i mysql-container mysql \
  -u root -p<password> < ~/backups/mysql-<date>.sql
```

Replace `mysql-container`, `<password>` with values from
`workstation-bootstrap/.env`.

## Docker volume export (generic)

```bash
# Dump a named volume to a tar archive
docker run --rm \
  -v <volume-name>:/data \
  -v ~/backups:/backup \
  ubuntu \
  tar czf /backup/<volume-name>-$(date +%Y%m%d).tar.gz -C /data .

# Restore
docker run --rm \
  -v <volume-name>:/data \
  -v ~/backups:/backup \
  ubuntu \
  tar xzf /backup/<volume-name>-<date>.tar.gz -C /data
```

## SSH key backup

Never commit SSH private keys to Git. Back them up in a password manager:

```bash
# Inside VM — print the private key to copy to a password manager
cat ~/.ssh/id_ed25519
```

When recovering on a new machine, restore the file before running
`provision.sh`:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
# Paste the key back:
nano ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
```

Then when `provision.sh` pauses for SSH key setup, the key is already
present and no new GitHub key addition is needed.

## Automation status

Backup scripts are planned under [scripts/README.md](../../scripts/README.md)
— see [ROADMAP.md](../../ROADMAP.md) Phase 5.

## References

- [Docker volumes documentation](https://docs.docker.com/storage/volumes/#back-up-restore-or-migrate-data-volumes)
- [Vagrant snapshots](https://developer.hashicorp.com/vagrant/docs/cli/snapshot)

## Related Documents

- [disaster-recovery.md](./disaster-recovery.md)
- [service-lifecycle.md](./service-lifecycle.md)
- [docs/security/secrets-management.md](../security/secrets-management.md)
