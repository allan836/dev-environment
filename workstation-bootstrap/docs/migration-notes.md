# Migration Notes: From Manual Checklist to Automated Bootstrap

## What changed

| Original doc | Now |
|---|---|
| ~70 manual copy/paste steps, macOS + Homebrew only | `./setup.sh` (one command), OS-detected (mac/Fedora) |
| MySQL, MongoDB, Cassandra, RabbitMQ, Neo4j, nginx, Consul installed via `brew` | Defined in [`docker-compose.yml`](../docker-compose.yml), started with `docker compose up -d` |
| No version pinning for Cassandra (Homebrew always installs latest) | Cassandra image pinned to `cassandra:4.1` in `docker-compose.yml` |
| "TODO: Local GUI for Cassandra, MySQL and RabbitMQ" | DBeaver (SQL/Cassandra) + RabbitMQ's own management UI (`:15672`) cover this; no bespoke tooling needed |
| Desktop apps installed one-by-one manually | [`scripts/install-desktop-apps.sh`](../scripts/install-desktop-apps.sh), best-effort per OS |

## What stayed manual (by design)

Per [ARCHITECTURE.md](../README.md#principles), some steps remain
human-in-the-loop and are **not** scripted:

- Signing in to Google Workspace, 2FA setup, sharing Google Photos.
- Xcode Command Line Tools license acceptance (macOS requires interactive
  acceptance).
- FortiToken Mobile setup on a personal phone.
- SSH key generation (kept manual/reviewable, one key per machine).
- Screen/audio recording permission grants (macOS Privacy & Security pane).

These are listed as manual checklist items in [README.md](../README.md#manual-steps-not-automated)
rather than automated, because they require human judgment, out-of-band
verification (2FA, mobile app), or an interactive OS dialog.

## Non-steps carried over

The original doc's "Non-steps" section is preserved as-is — these were
already correctly identified as unnecessary and nothing in this migration
changes that:

- Installing Node.js 14.
- Installing a separate MySQL client (bundled with the `mysql` package).
- Installing `wget`.

## Open items from the original doc

- Cassandra version pinning issue (noted in original doc) is resolved here
  by pinning the Docker image tag instead of fighting Homebrew's formula.
- The original TODO for local GUIs for Cassandra/MySQL/RabbitMQ is resolved
  via DBeaver + RabbitMQ's built-in management UI (see table above).

## References

- Original onboarding checklist (source document).

## Related Documents

- [docs/classification.md](./classification.md)
- [docs/architecture.md](./architecture.md)
- [../README.md](../README.md)
