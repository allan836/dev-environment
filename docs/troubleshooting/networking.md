# Troubleshooting: Networking

## Purpose

Capture known networking issues (port conflicts, container networking,
firewall) on this workstation and their resolutions.

## Scope

Covers local host and container networking. Does not cover cloud networking,
which is project-specific and out of scope for this repository.

## Prerequisites

- [docs/architecture/networking.md](../architecture/networking.md)

## Known Issues

### Port already in use when starting a service

- **Symptom:** `Error starting userland proxy: listen tcp 127.0.0.1:5432:
  bind: address already in use`.
- **Cause:** Another process (often a natively installed service or a
  different Compose stack) is already bound to the same port.
- **Resolution:** Identify the owner with `sudo ss -ltnp | grep <port>`;
  stop the conflicting service or remap the port, following the port table
  in [docs/setup/databases-services.md](../setup/databases-services.md).
- **Prevention:** Never install a database natively on the host alongside
  its containerized equivalent — see
  [ARCHITECTURE.md](../../ARCHITECTURE.md) principle on containerized
  services.

### Containers in different Compose stacks cannot reach each other

- **Symptom:** Connection refused/timeout between two containers expected
  to communicate (e.g. Open WebUI to Qdrant).
- **Cause:** Containers are on different Docker networks (each `docker
  compose` project creates its own network by default).
- **Resolution:** Ensure dependent services are defined in the same Compose
  stack/network per [docs/automation/docker-compose.md](../automation/docker-compose.md),
  or explicitly attach an external shared network.
- **Prevention:** Group services that must communicate into the same stack
  file at design time.

## Template for New Entries

```markdown
### <Short symptom description>

- **Symptom:**
- **Cause:**
- **Resolution:**
- **Prevention:**
```

## References

- [Docker networking overview](https://docs.docker.com/network/)

## Related Documents

- [docs/architecture/networking.md](../architecture/networking.md)
- [docs/setup/databases-services.md](../setup/databases-services.md)
- [docs/automation/docker-compose.md](../automation/docker-compose.md)
