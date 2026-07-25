# Terraform and OpenTofu Setup

## Purpose

Install both Terraform and OpenTofu CLIs so infrastructure-as-code projects
can be authored and applied regardless of which tool a given project
standardizes on.

## Scope

Covers CLI installation only. Does not cover any specific IaC project or
state backend configuration, which is out of scope for this workstation
repository. Does not cover Kubernetes itself — see
[docs/setup/kubernetes.md](./kubernetes.md).

## Prerequisites

- [docs/setup/fedora-base-setup.md](./fedora-base-setup.md) completed.

## Manual Installation Steps

1. Install Terraform via the HashiCorp repository:
   ```bash
   sudo dnf install -y dnf-plugins-core
   sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
   sudo dnf install -y terraform
   ```
2. Install OpenTofu via its official install script or RPM release:
   ```bash
   curl -fsSL https://get.opentofu.org/install-opentofu.sh -o install-opentofu.sh
   chmod +x install-opentofu.sh
   ./install-opentofu.sh --install-method rpm
   rm install-opentofu.sh
   ```

## Configuration

- No global configuration is required for either CLI on this workstation.
- Provider credentials (AWS/Azure/GCP) are covered in
  [docs/setup/cloud-clis.md](./cloud-clis.md) and
  [docs/security/secrets-management.md](../security/secrets-management.md).

## Verification

```bash
terraform -version
tofu -version
```

## Automation Status

Not yet automated. Planned as an Ansible role installing both binaries side
by side — see [ROADMAP.md](../../ROADMAP.md).

## References

- [Terraform install docs](https://developer.hashicorp.com/terraform/install)
- [OpenTofu install docs](https://opentofu.org/docs/intro/install/)

## Related Documents

- [docs/setup/kubernetes.md](./kubernetes.md)
- [docs/setup/cloud-clis.md](./cloud-clis.md)
- [docs/security/secrets-management.md](../security/secrets-management.md)
