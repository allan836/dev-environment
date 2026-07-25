# Fedora Base Setup

## Purpose

Establish the baseline Fedora Workstation configuration that all other setup
guides assume: an updated system, sane DNF configuration, and required base
packages.

## Scope

Covers OS-level updates, DNF tuning, and base package groups. Does not cover
any specific developer tool — see the other guides in [docs/setup](./README.md).

## Prerequisites

- Fresh Fedora Workstation installation with network access.
- A non-root user with `sudo` privileges.

## Manual Installation Steps

1. Update the system:
   ```bash
   sudo dnf upgrade --refresh -y
   ```
2. Enable RPM Fusion (free and non-free) for broader package availability:
   ```bash
   sudo dnf install -y \
     https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
     https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
   ```
3. Install base development tools:
   ```bash
   sudo dnf groupinstall -y "Development Tools"
   sudo dnf install -y curl wget git gnupg2 dnf-plugins-core
   ```
4. Enable `firewalld` (enabled by default on Workstation) and confirm status:
   ```bash
   sudo systemctl status firewalld
   ```

## Configuration

- Set the hostname if not already meaningful:
  ```bash
  sudo hostnamectl set-hostname <hostname>
  ```
- Confirm locale and timezone are correct via `localectl` and `timedatectl`.

## Verification

```bash
cat /etc/fedora-release
dnf repolist enabled
git --version
```
Confirms the OS version, active repositories, and base tooling are present.

## Automation Status

Not yet automated. Planned as an Ansible base role — see
[docs/automation/ansible.md](../automation/ansible.md) and [ROADMAP.md](../../ROADMAP.md).
Manual steps above remain the fallback per [ARCHITECTURE.md](../../ARCHITECTURE.md).

## References

- [Fedora Quick Docs](https://docs.fedoraproject.org/en-US/quick-docs/)
- [RPM Fusion](https://rpmfusion.org/)

## Related Documents

- [docs/setup/README.md](./README.md)
- [docs/setup/git-github-ssh.md](./git-github-ssh.md)
- [docs/runbooks/new-machine-bootstrap.md](../runbooks/new-machine-bootstrap.md)
