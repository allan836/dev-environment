# KV Backend — Developer Environment Modernisation
## Status Report & Proposal
**Date:** July 2026
**Prepared by:** Engineering

---

## 1. Where We Are Today

### 1.1 What Has Been Built

Two repositories now form the foundation of the modernised developer workflow:

**`kv-backend/preload-docker-compose/`** *(inside the application repo)*
Contains the Docker Compose stack that runs all local services the portal depends on. This was the starting point and is where the day-to-day running environment lives. Key changes already made to make it work on the current development machine:

- All Docker volume mounts updated with `:Z` SELinux labels — required on Fedora to allow containers to read host-mounted files
- MailHog added as a local mail catcher (email testing without a real SMTP server)
- Portal dependency on MailHog wired in
- `quick-setup.sh` and `local-rebuild.sh` made executable
- Documented in `README.md`

**`dev-environment/workstation-bootstrap/`** *(separate infrastructure repo)*
A self-contained, OS-aware bootstrap that provisions a brand-new machine from zero to a working KV development environment. This is where all new automation lives so that `kv-backend` itself is never modified for setup purposes.

| Script / File | Purpose |
|---|---|
| `setup.sh` | Entry point — detects OS, runs all install stages |
| `scripts/install-core.sh` | Installs Git, Docker, GitHub CLI, OpenVPN, AWS CLI, Terraform, kubectl |
| `scripts/install-runtimes.sh` | Installs Node (nvm), Python (pyenv), Java 17 + Maven (SDKMAN), pnpm |
| `scripts/install-desktop-apps.sh` | VS Code, DBeaver, Slack, Zoom (best-effort) |
| `scripts/kv-backend.sh` | Loads Docker images, starts services, runs first-time DB init, verifies |
| `scripts/kv-clean-slate.sh` | **New** — wipes and rebuilds databases from a known clean state |
| `scripts/verify.sh` | Checks all tools and service ports are reachable |
| `Makefile` | `make kv-up`, `make kv-init`, `make kv-clean-slate`, `make kv-verify`, etc. |
| `.env.example` | Template for developer-specific config (paths, optional remote seed DB) |
| `assets/preload_kv.tar.gz` | Pre-built Docker images (754 MB) — no manual build required |

### 1.2 Current Status by Area

| Area | Status | Notes |
|---|---|---|
| OS detection (Fedora / macOS / Ubuntu / Debian) | Done | Automatic, no developer input needed |
| Tool installation (git, docker, java, maven, node, python) | Done | Idempotent — safe to re-run |
| Docker preload images | Done | 754 MB tarball in repo, auto-loaded on first run |
| `docker compose up` orchestration | Done | All 7 services start with one command |
| First-time DB init (MySQL + Cassandra) | Done | `make kv-init` |
| Clean-slate rebuild | Done | `make kv-clean-slate` |
| Remote seed from Uniserver | Built, not yet configured | Requires `.env` with Uniserver credentials |
| VPN (openfortivpn) in bootstrap | **Gap** | `openfortivpn` is installed manually; not yet in `install-core.sh` |
| Auto-clone of `kv-backend` | **Gap** | Requires SSH key → GitHub auth (human step) |
| Git credential setup guidance | **Gap** | No automated SSH key generation step yet |

---

## 2. How the Environment Actually Works

### 2.1 Architecture

```
Developer Machine
┌─────────────────────────────────────────────────────────────┐
│  Host OS (Fedora / macOS)                                    │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Docker Engine                                          │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │  │
│  │  │  MySQL   │ │Cassandra │ │RabbitMQ  │ │   Solr   │  │  │
│  │  │  :43306  │ │  :59042  │ │  :35672  │ │  :58983  │  │  │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘  │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐               │  │
│  │  │Memcached │ │ MailHog  │ │  Portal  │               │  │
│  │  │  :41211  │ │  :8025   │ │  :8080   │               │  │
│  │  └──────────┘ └──────────┘ └──────────┘               │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  Developer Tools (host-installed)                            │
│  Git · Java 17 · Maven · Node.js · VS Code · openfortivpn   │
└─────────────────────────────────────────────────────────────┘
            │ VPN tunnel (openfortivpn OTP)
            ▼
   Uniserver Datacenter (existing)
   ┌─────────────────────────────┐
   │  Production / Staging       │
   │  Shared dev services (TBD)  │
   └─────────────────────────────┘
```

Everything inside the Docker network communicates by service name (`kv-mysql8`, `kv-cassandra`, etc.). The developer accesses the portal at `http://localhost:8080/portal`. All services are isolated to the developer's own machine and do not share state with any other developer.

### 2.2 What Is and Is Not Hosted

| Component | Currently hosted | Where |
|---|---|---|
| Portal / Tomcat | Developer's own machine | Docker container |
| MySQL | Developer's own machine | Docker container |
| Cassandra | Developer's own machine | Docker container |
| RabbitMQ | Developer's own machine | Docker container |
| Solr | Developer's own machine | Docker container |
| Memcached | Developer's own machine | Docker container |
| MailHog | Developer's own machine | Docker container |
| Production databases | Uniserver datacenter | Managed |
| Staging environment | Uniserver datacenter | Managed |
| Source code (git) | GitHub (Klantenvertellen-NextGen org) | Remote |
| Docker preload images | `dev-environment` repo (`assets/`) | Git LFS / included |

Nothing in the local dev environment connects to production. The VPN is used to access internal tools and staging — not for local development itself.

---

## 3. What a New Developer Must Do

### 3.1 What They Must Provide

| Credential / Item | Who provides it | Notes |
|---|---|---|
| FortiVPN OTP (FortiToken) | Developer's own phone | FortiToken Mobile app, issued per person |
| FortiVPN username + password | IT / onboarding | Personal credentials, not shared |
| GitHub account | Developer's own | Must be added to the `Klantenvertellen-NextGen` org |
| SSH key pair | Auto-generated by setup | Public key must be added to GitHub manually (one-time) |
| PC meeting minimum spec | Developer | See section 5 |

### 3.2 Step-by-Step New Developer Onboarding

```
Step 1 — Get access (one-time, requires IT)
  • Receive FortiVPN credentials + FortiToken Mobile app
  • Get added to Klantenvertellen-NextGen GitHub org

Step 2 — Bootstrap the machine (automated, ~20 min)
  git clone <dev-environment-repo> ~/workspace/repos/dev-environment
  cd ~/workspace/repos/dev-environment/workstation-bootstrap
  ./setup.sh

Step 3 — Set up SSH key for GitHub (one-time manual step)
  ssh-keygen -t ed25519 -C "your.name@company.com"
  cat ~/.ssh/id_ed25519.pub   # copy this, add to GitHub → Settings → SSH Keys

Step 4 — Clone kv-backend
  git clone git@github.com:Klantenvertellen-NextGen/kv-backend.git \
    ~/workspace/repos/kv-backend

Step 5 — Configure local settings (one-time)
  cp .env.example .env
  # edit .env if kv-backend is not at the default path

Step 6 — Load Docker images and start services
  make kv-up        # loads 754 MB image tarball + docker compose up

Step 7 — Initialise databases (first time only)
  make kv-init

Step 8 — Verify everything is running
  make kv-verify

Step 9 — Connect VPN when needed (for internal tools / staging)
  sudo openfortivpn --otp=<FortiToken code>
```

After step 8: `http://localhost:8080/portal` — username `system_2`, password `admin`.

---

## 4. The Data Drift Problem

### 4.1 What It Is

Every developer runs their own local MySQL and Cassandra. There is no mechanism today to ensure those databases are in the same state. Over time:

- Developer A runs a migration that changes a table structure
- Developer B is on a different branch and has not run that migration
- Developer A's bug cannot be reproduced on B's machine
- A new migration has a Flyway checksum mismatch because the SQL file was edited after it was first committed — this is already happening (see `V1.0.0.22` in `quick-setup.sh`)

The project currently has **170 Flyway migration scripts** spanning versions V1.0.0.x through V1.7.0.x. Each one is checksummed. An edited migration causes every developer who already ran it to have a broken database that requires manual intervention.

### 4.2 The Fix: Clean-Slate Rebuild

`make kv-clean-slate` solves this by treating the local database as disposable:

1. Wipes MySQL and Cassandra volumes
2. Starts services and waits for genuine readiness (not just port open)
3. Runs all 170 Flyway migrations from scratch — clean schema every time
4. Seeds data from the bundled SQL dump OR from Uniserver (see section 6)
5. Re-initialises Cassandra
6. Runs post-migration scripts
7. Restarts portal

A developer with a broken or diverged local DB runs one command and is back to a known good state in under 10 minutes. The hardcoded Flyway checksum patch that was in `quick-setup.sh` is eliminated — Flyway checksums are always correct because the schema is always built from scratch.

**Rule that must accompany this:** Never edit a committed migration file. If a migration needs changing, write a new one. This is enforced by code review, not tooling.

---

## 5. Minimum PC Requirements

Based on measured RAM usage of the running stack plus IDE and Maven build load:

| Resource | Minimum | Recommended |
|---|---|---|
| RAM | 16 GB | 32 GB |
| CPU | 4-core (Intel i5 / AMD Ryzen 5, 2020+) | 8-core |
| Storage | 50 GB free SSD space | 100 GB free NVMe |
| OS | Fedora 40+, macOS 13+, Ubuntu 22.04+ | Fedora 44 |
| Internet | Broadband | — |

**Measured RAM in use (idle, full stack running):**

| Service | RAM |
|---|---|
| Portal (Tomcat) | 925 MB |
| Cassandra | 689 MB (ceiling configured at 2 GB) |
| MySQL | 127 MB |
| Solr | 139 MB |
| RabbitMQ | ~150 MB |
| Memcached + MailHog | ~3 MB |
| **Stack total (idle)** | **~2.0 GB** |
| Stack total (under load) | ~4–5 GB |
| IDE (VS Code / IntelliJ) | 1–2 GB |
| Maven build (peak) | 2–3 GB |
| **Total peak demand** | **~9–10 GB** |

A 16 GB machine runs this but has little headroom. 32 GB is comfortable and leaves room for a browser, Slack, and other tools open simultaneously.

---

## 6. Hosting Options

### Option A — Individual Developer PCs (Recommended for Phase 1)

Each developer runs the full stack on their own machine. The `dev-environment` bootstrap provisions everything automatically.

**Advantages:**
- Zero infrastructure cost
- Fully independent — one developer's broken environment does not affect anyone else
- Works offline and without VPN (for local development)
- Scales by adding developers, not servers

**Disadvantages:**
- Data diverges over time (addressed by `clean-slate` + discipline on migrations)
- Initial setup requires 754 MB image download + Maven build (~20–30 min first time)
- Developers need a machine meeting minimum spec (see section 5)

**Cost:** €0/month infrastructure. Developer PC is developer's own responsibility.

---

### Option B — Shared Services on Uniserver + Local Portal (Phase 2 Proposal)

The stateful services (MySQL, Cassandra, RabbitMQ, Solr) run once on a shared Uniserver VM. Each developer only runs their own Portal/Tomcat container locally, pointed at the shared services via VPN.

```
Uniserver VM (shared)          Developer Machine (own laptop)
MySQL ─────────────────── VPN ──── Portal / Tomcat
Cassandra ──────────────────────── IDE + Maven
RabbitMQ                           (no local databases)
Solr
```

**Advantages:**
- Per-developer RAM drops from ~10 GB to ~3 GB (portal + IDE only)
- All developers share the same data — no divergence
- Database migrations are applied once, not 12 times
- Developers on older / lower-spec machines can participate

**Disadvantages:**
- Shared database = one developer's bad migration affects everyone
- VPN required at all times during development (not just for internal tools)
- Uniserver VM is a single point of failure for all developers
- Requires per-developer database schema separation (`kv_dev_alice`, `kv_dev_bob`) to prevent data conflicts between developers working simultaneously

**Cost:** One additional Uniserver VM (managed VMware VCF — price via TCO discussion with Uniserver). Comparable market rate: €60–120/month for a 4-core, 16 GB RAM VM.

---

### Option C — Full Cloud VMs Per Developer

Each developer gets a dedicated cloud VM (Hetzner, OVH, or Uniserver) sized to run the full stack independently.

| Provider | Spec | Cost per dev/month | 12 devs/month |
|---|---|---|---|
| Hetzner CPX41 | 8 vCPU, 16 GB RAM, 240 GB SSD | €21 | €252 |
| Hetzner CPX51 | 16 vCPU, 32 GB RAM, 360 GB SSD | €63 | €756 |
| AWS t3.2xlarge (on-demand) | 8 vCPU, 32 GB RAM | ~$240 | ~$2,880 |
| AWS t3.2xlarge (reserved 1yr) | 8 vCPU, 32 GB RAM | ~$115 | ~$1,380 |

**Advantages:**
- No laptop spec requirement — developer needs only a browser or SSH client
- Identical environment guaranteed across all developers

**Disadvantages:**
- Ongoing infrastructure cost
- VPN required to reach the VM + VPN again from VM to Uniserver
- Higher operational overhead (VM maintenance, backups)
- Data drift between VMs is the same problem as individual laptops

**Verdict:** Higher cost with no meaningful advantage over individual laptops for a team of this size. Not recommended unless remote / thin-client working is a hard requirement.

---

## 7. Phased Adoption Plan

### Phase 1 — Now: Standardise on Individual PCs
*Target: all active developers onboarded within 2 weeks*

**Actions:**
1. Share `dev-environment` repo with all developers
2. Define minimum PC spec (16 GB RAM, SSD) as a hiring/onboarding requirement
3. Issue FortiToken to all developers who do not have it
4. Add `openfortivpn` to `install-core.sh` (small script change)
5. Add SSH key auto-generation step to `setup.sh` (small script change)
6. Document the "never edit a committed migration" rule in the contributing guide
7. Each developer runs `./setup.sh` + `make kv-up` + `make kv-init`

**Outcome:** 12 developers, fully independent local environments, zero infrastructure cost, setup in under 30 minutes.

**Risk:** Data diverges over time as developers accumulate local changes. Mitigated by `make kv-clean-slate` — any developer can reset to a known state in under 10 minutes.

---

### Phase 2 — Next: Shared Dev Seed on Uniserver
*Target: 1–2 months after Phase 1*

**Actions:**
1. Provision one shared MySQL schema on Uniserver specifically for dev seeding (read-only access for developers, not a shared working database)
2. Configure `DEV_SEED_HOST` in onboarding documentation
3. Developers use `make kv-clean-slate-remote` to reset to Uniserver data instead of the bundled static dump
4. Implement per-developer database schemas (`kv_dev_<username>`) if working databases need to be shared

**Outcome:** All developers start from the same data. Data drift is eliminated at reset time. The bundled SQL dump in the repo is still available as a fallback for offline work.

---

### Phase 3 — Future: Shared Infrastructure on Uniserver
*Target: when team grows beyond 12 or PC spec becomes a constraint*

**Actions:**
1. TCO discussion with Uniserver for a dedicated dev VM
2. Migrate MySQL, Cassandra, RabbitMQ, Solr to the shared VM
3. Update `configuration-override.properties` template in `dev-environment` to point at Uniserver IPs
4. Each developer's `docker-compose.yml` is replaced with a portal-only compose file
5. VPN becomes a hard development requirement (not optional)

**Outcome:** Per-developer machine requirement drops to 8 GB RAM. Consistent data for all developers. One migration run affects all developers simultaneously (coordination required).

---

## 8. Open Items Requiring Decision

| Item | Decision needed | Who |
|---|---|---|
| FortiVPN — individual credentials for all 12 developers | Confirm all developers have personal FortiToken accounts | IT / Management |
| Uniserver access permissions | Confirm read access to dev MySQL for seed dump | DevOps / Management |
| Minimum PC spec enforcement | Define as a hiring requirement | Management / HR |
| "Never edit committed migrations" policy | Adopt as a team rule, enforce in PR review | Engineering Lead |
| Phase 2 timing | When to provision shared Uniserver seed DB | Management |

---

*End of report*
