# Runbook: New Machine Bootstrap

## Purpose

Provide the end-to-end procedure for turning a fresh Fedora Workstation
install into a fully configured developer workstation using this
repository.

## Scope

Covers the sequence of steps and links to the relevant guides. Does not
duplicate installation instructions themselves — each linked guide is the
source of truth for its tool. Does not cover recovering from data loss —
see [docs/runbooks/disaster-recovery.md](./disaster-recovery.md).

## Prerequisites

- Fedora Workstation ISO written and installed on the target machine.
- Network connectivity.
- Access to this Git repository (via HTTPS clone initially, before SSH is
  configured).

## Procedure

1. **Base OS** — follow [docs/setup/fedora-base-setup.md](../setup/fedora-base-setup.md).
2. **Git & SSH** — follow [docs/setup/git-github-ssh.md](../setup/git-github-ssh.md),
   then re-clone this repository over SSH if it was initially cloned via
   HTTPS.
3. **Container runtime** — follow [docs/setup/docker.md](../setup/docker.md)
   (and optionally [docs/setup/podman.md](../setup/podman.md)).
4. **Language runtimes** — follow [docs/setup/languages-runtimes.md](../setup/languages-runtimes.md).
5. **Cloud CLIs** — follow [docs/setup/cloud-clis.md](../setup/cloud-clis.md).
6. **IaC & Kubernetes tooling** — follow
   [docs/setup/terraform-opentofu.md](../setup/terraform-opentofu.md) and
   [docs/setup/kubernetes.md](../setup/kubernetes.md).
7. **IDEs** — follow [docs/setup/ides.md](../setup/ides.md).
8. **Local services** — follow [docs/setup/databases-services.md](../setup/databases-services.md)
   to bring up required containerized services.
9. **Restore data (if applicable)** — if recovering from a previous
   machine, follow [docs/runbooks/backup-restore.md](./backup-restore.md)
   to restore volumes before considering the machine "warm".
10. **Verify** — run the verification steps listed in each guide above to
    confirm the machine is in a known-good state.

## Future Automation

Once implemented, steps 1–8 will be replaced by a single command:
```bash
./bootstrap/bootstrap.sh
```
See [bootstrap/README.md](../../bootstrap/README.md) and
[docs/automation/README.md](../automation/README.md) for status.

## References

- [ARCHITECTURE.md](../../ARCHITECTURE.md)

## Related Documents

- [docs/setup/README.md](../setup/README.md)
- [docs/runbooks/disaster-recovery.md](./disaster-recovery.md)
- [bootstrap/README.md](../../bootstrap/README.md)
