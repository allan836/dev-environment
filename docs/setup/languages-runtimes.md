# Language Runtimes Setup

## Purpose

Install and manage the primary language runtimes used for development:
Python, Node.js, and Java.

## Scope

Covers runtime/version-manager installation for these three languages. Does
not cover project-level dependency management (`pip`, `npm`, `maven`, etc.),
which is project-specific and out of scope for this repository.

## Prerequisites

- [docs/setup/fedora-base-setup.md](./fedora-base-setup.md) completed.

## Manual Installation Steps

### Python

```bash
sudo dnf install -y python3 python3-pip python3-virtualenv pipx
```
A version manager (`pyenv`) is recommended for multi-version needs and is
installed per its upstream instructions rather than via `dnf`.

### Node.js

```bash
sudo dnf install -y nodejs npm
```
For multi-version needs, `nvm` (Node Version Manager) is recommended and
installed per its upstream instructions.

### Java

```bash
sudo dnf install -y java-21-openjdk java-21-openjdk-devel
```
For multi-version needs, `sdkman` is recommended for managing JDK
distributions and versions.

## Configuration

- `JAVA_HOME` and version-manager shims are configured via the managed
  shell dotfiles — see [dotfiles/README.md](../../dotfiles/README.md).

## Verification

```bash
python3 --version && pip3 --version
node --version && npm --version
java -version
```

## Automation Status

Not yet automated. Planned as three focused Ansible roles (one per
language) — see [docs/automation/ansible.md](../automation/ansible.md).

## References

- [pyenv](https://github.com/pyenv/pyenv)
- [nvm](https://github.com/nvm-sh/nvm)
- [SDKMAN!](https://sdkman.io/)

## Related Documents

- [docs/setup/fedora-base-setup.md](./fedora-base-setup.md)
- [dotfiles/README.md](../../dotfiles/README.md)
- [docs/setup/ides.md](./ides.md)
