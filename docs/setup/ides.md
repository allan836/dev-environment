# IDE Setup

## Purpose

Reference guide for development environments installed inside the developer VM.

## Scope

Covers VS Code (installed automatically) and JetBrains IDEs (manual install
after provisioning).

## Prerequisites

- Developer VM is running (`./provision.sh` completed).
- SSH into the VM: `ssh -i ~/.ssh/dev-env ubuntu@<VM_IP>`.

## VS Code

### Automation Status

**Fully automated** by the Ansible `developer_tools` role.
Source: [`ansible/roles/developer_tools/tasks/main.yml`](../../ansible/roles/developer_tools/tasks/main.yml).

VS Code is installed inside the VM via the Microsoft apt repository. Because
the VM is headless, the recommended way to use VS Code is via the **Remote
SSH extension** on your host laptop:

1. Install the "Remote - SSH" extension in VS Code on your laptop.
2. Connect to the VM: `ssh -i ~/.ssh/dev-env ubuntu@<VM_IP>` (IP is printed by `provision.sh`).
3. Open any folder inside the VM — all editing, terminals, and extensions
   run inside the VM.

### Verify

```bash
code --version
```

### Manual Install (fallback only)

```bash
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
  | sudo gpg --dearmor -o /etc/apt/keyrings/microsoft-vscode.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft-vscode.gpg] \
  https://packages.microsoft.com/repos/code stable main" \
  | sudo tee /etc/apt/sources.list.d/vscode.list
sudo apt-get update && sudo apt-get install -y code
```

## JetBrains IDEs

JetBrains Toolbox is not automated. Install it manually inside the VM after
provisioning if needed:

```bash
# Download JetBrains Toolbox
curl -fsSL "https://www.jetbrains.com/toolbox-app/" \
  # Download the .tar.gz for Linux from the JetBrains website
  # Extract and run the jetbrains-toolbox binary
```

For a headless VM, IntelliJ IDEA and other JetBrains IDEs also support
**Remote Development via SSH** — connect from the IDE on your host laptop
to the VM without a GUI inside the VM.

## References

- [VS Code Remote SSH](https://code.visualstudio.com/docs/remote/ssh)
- [JetBrains Remote Development](https://www.jetbrains.com/remote-development/)

## Related Documents

- [ansible/roles/developer_tools](../../ansible/roles/developer_tools/tasks/main.yml)
