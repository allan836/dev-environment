# IDE Setup

## Purpose

Install the primary development environments used on this workstation:
Visual Studio Code and JetBrains IDEs (via JetBrains Toolbox).

## Scope

Covers installation only. Does not cover editor extension lists or IDE
settings sync configuration in detail — a summary pointer is given below,
full settings live under [configs](../../configs/README.md) once captured.

## Prerequisites

- [docs/setup/fedora-base-setup.md](./fedora-base-setup.md) completed.

## Manual Installation Steps

### Visual Studio Code

```bash
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo dnf config-manager --add-repo https://packages.microsoft.com/yumrepos/vscode
sudo dnf install -y code
```

### JetBrains IDEs

Install via JetBrains Toolbox (recommended, manages updates for all
JetBrains products):
```bash
# Download the latest Toolbox App tarball from JetBrains and extract to
# a local applications directory, then run the installer binary once.
```
Individual IDEs (IntelliJ IDEA, PyCharm, GoLand, etc.) are then installed
and updated through Toolbox rather than `dnf`.

## Configuration

- VS Code extensions and settings, once standardized, are tracked as a
  managed configuration under [configs](../../configs/README.md).
- JetBrains IDE settings sync uses the built-in "Settings Sync" feature
  backed by a JetBrains account or GitHub Gist.

## Verification

```bash
code --version
```
For JetBrains IDEs, confirm launch and license/account status manually
through the Toolbox App.

## Automation Status

Not yet automated. Planned as an Ansible role for VS Code (package + `code
--install-extension` list); JetBrains Toolbox installation is likely to
remain a documented manual step due to its self-updating nature.

## References

- [VS Code Linux install docs](https://code.visualstudio.com/docs/setup/linux)
- [JetBrains Toolbox App](https://www.jetbrains.com/toolbox-app/)

## Related Documents

- [docs/setup/languages-runtimes.md](./languages-runtimes.md)
- [configs/README.md](../../configs/README.md)
