# Kubernetes Setup

## Purpose

Install the Kubernetes CLI (`kubectl`) and establish the approach for
running a local cluster for development and testing purposes.

## Scope

Covers `kubectl` installation and local cluster options (e.g. `kind`,
`minikube`). Does not cover production cluster provisioning — that is
handled per-project with Terraform/OpenTofu, not this repository. Does not
cover Docker itself — see [docs/setup/docker.md](./docker.md).

## Prerequisites

- [docs/setup/docker.md](./docker.md) completed (local clusters typically
  run on top of the container runtime).

## Manual Installation Steps

1. Install `kubectl`:
   ```bash
   sudo dnf install -y kubernetes-client
   ```
2. Choose and install a local cluster tool (one of):
   ```bash
   # kind
   sudo dnf install -y kind
   # or minikube (from upstream binary release)
   ```
3. Create a local cluster (example using `kind`):
   ```bash
   kind create cluster --name dev
   ```

## Configuration

- `kubectl` context and kubeconfig files are treated as machine-local state,
  not committed to this repository (may contain cluster credentials — see
  [docs/security/secrets-management.md](../security/secrets-management.md)).
- Local cluster manifests/examples, if added later, will live under
  [templates](../../templates/README.md).

## Verification

```bash
kubectl version --client
kind get clusters
kubectl cluster-info
```

## Automation Status

Not yet automated. Planned as an Ansible role for CLI installation; cluster
bootstrap scripting is tracked in [ROADMAP.md](../../ROADMAP.md) Phase 2/3.

## References

- [kubectl documentation](https://kubernetes.io/docs/reference/kubectl/)
- [kind documentation](https://kind.sigs.k8s.io/)

## Related Documents

- [docs/setup/docker.md](./docker.md)
- [docs/setup/terraform-opentofu.md](./terraform-opentofu.md)
- [docs/security/secrets-management.md](../security/secrets-management.md)
