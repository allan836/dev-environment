# Troubleshooting: Docker

## Purpose

Capture known Docker-related issues on this workstation and their
resolutions.

## Scope

Covers Docker Engine, daemon, and container-level issues. Does not cover
Kubernetes — see [docs/troubleshooting/kubernetes.md](./kubernetes.md).

## Prerequisites

- [docs/setup/docker.md](../setup/docker.md)

## Known Issues

### "Permission denied" running `docker` without `sudo`

- **Symptom:** `permission denied while trying to connect to the Docker
  daemon socket`.
- **Cause:** User not in the `docker` group, or the group membership has
  not taken effect in the current shell session.
- **Resolution:** `sudo usermod -aG docker $USER`, then fully log out and
  back in (or `newgrp docker` for the current shell).
- **Prevention:** Verify group membership as part of the
  [docs/setup/docker.md](../setup/docker.md) verification step.

### Docker daemon fails to start after update

- **Symptom:** `systemctl status docker` shows `failed`.
- **Cause:** Typically a stale/incompatible `daemon.json` or a conflicting
  `containerd` version after an `apt upgrade`.
- **Resolution:** Check `journalctl -u docker -e` for the specific error;
  validate `/etc/docker/daemon.json` syntax; reinstall `containerd.io` if
  version mismatch is indicated (`sudo apt-get install --reinstall containerd.io`).
- **Prevention:** Pin tested versions where stability matters; review
  release notes before major upgrades.

## Template for New Entries

```markdown
### <Short symptom description>

- **Symptom:**
- **Cause:**
- **Resolution:**
- **Prevention:**
```

## References

- [Docker Engine troubleshooting](https://docs.docker.com/engine/daemon/troubleshoot/)

## Related Documents

- [docs/setup/docker.md](../setup/docker.md)
- [docs/troubleshooting/networking.md](./networking.md)
