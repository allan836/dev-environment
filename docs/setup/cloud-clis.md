# Cloud CLIs

## Purpose

Reference guide for the cloud provider CLIs installed inside the developer VM.

## Scope

Covers AWS CLI v2, Azure CLI, and Google Cloud CLI — installation and initial
authentication. Does not cover cloud infrastructure provisioning, which is
project-specific.

## Prerequisites

- Developer VM is running (`./provision.sh` completed).
- SSH into the VM: `ssh -i ~/.ssh/dev-env ubuntu@<VM_IP>`.
- Cloud provider accounts already exist.

## Automation Status

**Fully automated** by the Ansible `cloud_clis` role.
Source: [`ansible/roles/cloud_clis/tasks/main.yml`](../../ansible/roles/cloud_clis/tasks/main.yml).

All three CLIs are installed with `ignore_errors: true` — a failure on one
does not block provisioning. Check which ones were installed:

```bash
aws --version
az --version
gcloud --version
```

## Post-install authentication (manual — cannot be automated)

### AWS CLI

```bash
aws configure
# Prompts for: Access Key ID, Secret Access Key, region, output format
# Or for SSO:
aws configure sso
```

### Azure CLI

```bash
az login
# Opens browser for interactive sign-in
```

### Google Cloud CLI

```bash
gcloud auth login
gcloud config set project <your-project-id>
```

## Manual Install (fallback only)

If Ansible failed for a specific CLI, run the relevant Ansible role tag:

```bash
ssh -i ~/.ssh/dev-env ubuntu@<VM_IP> \
  "cd ~/dev-environment/ansible && ansible-playbook playbook.yml -i inventory/hosts.yml --tags aws"
```

Or install manually inside the VM:

```bash
# AWS CLI v2
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip && sudo ./aws/install && rm -rf awscliv2.zip aws/

# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Google Cloud CLI
sudo apt-get install -y google-cloud-cli
```

## References

- [AWS CLI documentation](https://docs.aws.amazon.com/cli/latest/userguide/)
- [Azure CLI documentation](https://learn.microsoft.com/en-us/cli/azure/)
- [Google Cloud CLI documentation](https://cloud.google.com/sdk/docs)

## Related Documents

- [ansible/roles/cloud_clis](../../ansible/roles/cloud_clis/tasks/main.yml)
- [docs/security/secrets-management.md](../security/secrets-management.md)
