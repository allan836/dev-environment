# Networking Architecture

## Purpose

Describe how host networking and container networking are organized,
including the port allocation strategy used to avoid collisions between
local services.

## Scope

Covers local workstation networking only: Docker/Podman networks, exposed
ports, and host firewall considerations. Does not cover cloud networking
(VPCs, subnets) — that belongs to individual cloud projects outside this
repository.

## Prerequisites

- [docs/architecture/overview.md](./overview.md)

## Container Networking

- Each Compose stack (see [docs/setup/databases-services.md](../setup/databases-services.md))
  defines its own Docker network to isolate services by concern.
- No service is exposed beyond `127.0.0.1` unless explicitly required,
  reducing exposure on shared or untrusted networks.

## Port Allocation

A fixed, documented port map avoids collisions across stacks. Authoritative
port assignments are maintained in [docs/setup/databases-services.md](../setup/databases-services.md)
per service, not duplicated here.

## Host Firewall

Fedora ships with `firewalld` enabled by default. Local container ports
bound to `127.0.0.1` do not require firewall changes. Any service
intentionally exposed on the LAN must be documented with the specific
`firewalld` rule added, in the relevant setup guide.

## References

- [Docker networking overview](https://docs.docker.com/network/)
- [firewalld documentation](https://firewalld.org/documentation/)

## Related Documents

- [docs/architecture/overview.md](./overview.md)
- [docs/setup/docker.md](../setup/docker.md)
- [docs/setup/databases-services.md](../setup/databases-services.md)
- [docs/troubleshooting/networking.md](../troubleshooting/networking.md)
