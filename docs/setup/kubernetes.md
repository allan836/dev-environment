# Kubernetes Setup

## Purpose

Reference guide for Kubernetes tooling installed inside the developer VM.

## Scope

Covers `kubectl`, Helm, and k9s. Does not cover production cluster
provisioning — that is project-specific.

## Prerequisites

- Developer VM is running (`./provision.sh` completed).
- SSH into the VM: `ssh -i ~/.ssh/dev-env ubuntu@<VM_IP>`.

## Automation Status

**Fully automated** by the Ansible `kubectl` role.
Source: [`ansible/roles/kubectl/tasks/main.yml`](../../ansible/roles/kubectl/tasks/main.yml).

| Tool | What is installed |
|---|---|
| `kubectl` | Kubernetes CLI via official Kubernetes apt repo (v1.30) |
| `helm` | Kubernetes package manager via get-helm-3 script |
| `k9s` | Terminal UI for Kubernetes clusters |

## Verification

```bash
kubectl version --client
helm version
k9s version
```

## Local cluster (optional)

For running a local Kubernetes cluster for testing:

```bash
# kind (Kubernetes in Docker)
curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
chmod +x kind && sudo mv kind /usr/local/bin/

kind create cluster
kubectl cluster-info --context kind-kind
```

## Manual Install (fallback only)

```bash
# kubectl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && sudo apt-get install -y kubectl

# helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## References

- [kubectl documentation](https://kubernetes.io/docs/reference/kubectl/)
- [Helm documentation](https://helm.sh/docs/)
- [k9s documentation](https://k9scli.io/)

## Related Documents

- [ansible/roles/kubectl](../../ansible/roles/kubectl/tasks/main.yml)
- [docs/troubleshooting/kubernetes.md](../troubleshooting/kubernetes.md)
