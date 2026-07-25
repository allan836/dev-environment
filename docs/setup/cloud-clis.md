# Cloud CLIs Setup

## Purpose

Install and authenticate the command-line interfaces for the three major
cloud providers used across projects: AWS, Azure, and Google Cloud.

## Scope

Covers CLI installation and the general authentication approach. Does not
cover cloud infrastructure provisioning (Terraform/OpenTofu project
concern) or storage of long-lived credentials — see
[docs/security/secrets-management.md](../security/secrets-management.md).

## Prerequisites

- [docs/setup/fedora-base-setup.md](./fedora-base-setup.md) completed.
- Cloud provider accounts already exist (out of scope to provision here).

## Manual Installation Steps

### AWS CLI

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip aws/
```
Authenticate with `aws configure` or `aws configure sso`, per your
organization's IAM setup.

### Azure CLI

```bash
sudo dnf install -y azure-cli
```
Authenticate with `az login`.

### Google Cloud CLI

```bash
sudo dnf install -y https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-x86_64/google-cloud-cli-latest.x86_64.rpm
```
(Adjust repo path to the current Fedora/EL compatibility target per Google's
docs.) Authenticate with `gcloud auth login`.

## Configuration

- Credential files (`~/.aws/credentials`, `~/.azure/`, `~/.config/gcloud/`)
  are machine-local and **never** committed to this repository — see
  [docs/security/secrets-management.md](../security/secrets-management.md).
- Preferred use of SSO/temporary credentials over long-lived static keys.

## Verification

```bash
aws --version && aws sts get-caller-identity
az --version && az account show
gcloud --version && gcloud auth list
```

## Automation Status

Not yet automated. Planned as Ansible roles for CLI installation only;
authentication remains a manual, human-in-the-loop step by design.

## References

- [AWS CLI install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Azure CLI install guide](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux)
- [gcloud CLI install guide](https://cloud.google.com/sdk/docs/install)

## Related Documents

- [docs/setup/terraform-opentofu.md](./terraform-opentofu.md)
- [docs/security/secrets-management.md](../security/secrets-management.md)
