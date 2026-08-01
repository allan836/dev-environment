# Terraform and OpenTofu

## Purpose

Reference guide for IaC CLIs installed inside the developer VM.

## Scope

Covers Terraform and OpenTofu CLI installation. Does not cover specific IaC
projects or state backend configuration, which are project-specific.

## Prerequisites

- Developer VM is running (`./provision.sh` completed or `cd vm && vagrant up`).
- SSH into the VM: `cd vm && vagrant ssh`.

## Automation Status

**Fully automated** by the Ansible `terraform` role.
Source: [`ansible/roles/terraform/tasks/main.yml`](../../ansible/roles/terraform/tasks/main.yml).

Both Terraform and OpenTofu are installed via their official apt repositories.
OpenTofu install has `ignore_errors: true` — it does not block provisioning
if the repo is temporarily unavailable.

## Verification

```bash
terraform version
tofu version    # OpenTofu
```

## Manual Install (fallback only)

```bash
# Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform

# OpenTofu
curl -fsSL https://get.opentofu.org/install-opentofu.sh | sudo sh -s -- --install-method deb
```

## References

- [Terraform documentation](https://developer.hashicorp.com/terraform/docs)
- [OpenTofu documentation](https://opentofu.org/docs/)

## Related Documents

- [ansible/roles/terraform](../../ansible/roles/terraform/tasks/main.yml)
