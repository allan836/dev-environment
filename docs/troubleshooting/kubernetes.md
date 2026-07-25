# Troubleshooting: Kubernetes

## Purpose

Capture known `kubectl` and local-cluster issues on this workstation and
their resolutions.

## Scope

Covers local development cluster issues (`kind`/`minikube`) and `kubectl`
configuration. Does not cover production cluster operations, which are
project-specific and out of scope for this repository.

## Prerequisites

- [docs/setup/kubernetes.md](../setup/kubernetes.md)

## Known Issues

### `kubectl` cannot connect to the cluster

- **Symptom:** `The connection to the server localhost:8080 was refused`.
- **Cause:** No `KUBECONFIG` context set, or the local cluster is not
  running.
- **Resolution:** Confirm the cluster is up (`kind get clusters`), and that
  `kubectl config current-context` points to it.
- **Prevention:** Always run the verification step in
  [docs/setup/kubernetes.md](../setup/kubernetes.md) after creating a
  cluster.

### Local cluster cannot pull images

- **Symptom:** Pods stuck in `ImagePullBackOff` for locally built images.
- **Cause:** `kind`/`minikube` runs its own container runtime, isolated from
  the host Docker daemon; a locally built image is not automatically visible
  inside the cluster.
- **Resolution:** Load the image explicitly, e.g. `kind load docker-image
  <image>:<tag> --name dev`.
- **Prevention:** Document image-loading as a required step in any workflow
  that builds and deploys locally.

## Template for New Entries

```markdown
### <Short symptom description>

- **Symptom:**
- **Cause:**
- **Resolution:**
- **Prevention:**
```

## References

- [kind documentation](https://kind.sigs.k8s.io/)

## Related Documents

- [docs/setup/kubernetes.md](../setup/kubernetes.md)
- [docs/troubleshooting/docker.md](./docker.md)
