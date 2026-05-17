# light

**L**inux **I**nfrastructure **G**eneral **H**arness **T**ool

A Bash harness that ties together Terraform, Ansible, Puppet, Foreman, and Checkmk to spin up a fully isolated enterprise infrastructure stack — locally on your laptop or on a cloud/on-prem provider — with a single command.

```bash
sudo ./startup.sh --install-requirements  # install Docker, VirtualBox, Vagrant, Terraform, Ansible
./startup.sh --init                       # generate config/light.env with defaults + random secrets
./startup.sh dev                          # full stack on your laptop
./startup.sh staging aws                  # full stack on AWS
./startup.sh prod on-prem                 # full stack on vSphere/NSX
./teardown.sh dev                         # destroy everything
```

Every environment runs the **identical** service topology. A workload VM cannot tell whether it is running in dev, staging, or production.

---

## Table of Contents

- [Architecture](#architecture)
- [Service Bubbles](#service-bubbles)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [Quick Start — Dev](#quick-start--dev)
- [Quick Start — Staging](#quick-start--staging)
- [Quick Start — Production](#quick-start--production)
- [Monitoring the Stack](#monitoring-the-stack)
- [Firewall Rules — Network Team Submission](#firewall-rules--network-team-submission)
- [SSH Access Patterns](#ssh-access-patterns)
- [Custom Domain](#custom-domain)
- [Developer Workflows](#developer-workflows)
- [Troubleshooting](#troubleshooting)
- [Project Structure](#project-structure)

---

## Architecture

### Two-Zone Network Model

```
┌─────────────────────────────────────────────────────────────────┐
│  External / Internet                                             │
│                                                                  │
│  Operator SSH ────────────────────────────────┐                  │
│  (only allowed inbound)                       │                  │
└───────────────────────────────────────────────│──────────────────┘
                                                ▼
┌──────────────────── Management Zone (10.10.0.0/24) ─────────────┐
│                                                                  │
│  Jumphost    10.10.0.10   SSH bastion — sole external entry      │
│  Foreman     10.10.0.20   Inventory & host lifecycle (SSOT)      │
│  Puppet      10.10.0.21   Baseline enforcement (pull / 30 min)   │
│  Ansible     10.10.0.22   Application deployment (push)          │
│  Checkmk     10.10.0.23   Monitoring & alerting                  │
│  Pulp        10.10.0.24   Package mirror (only internet egress)  │
│  DNS primary 10.10.0.30   Internal name resolution               │
│  DNS secondary 10.10.0.31 Failover DNS                           │
│  NTP primary 10.10.0.32   Time synchronisation                   │
│  NTP secondary 10.10.0.33 Failover NTP                           │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
         │ Jumphost, Ansible, Checkmk        ▲ Puppet pull (8140)
         │ bridge into bubble networks       │ Pulp packages (80/443)
         ▼                                   │ DNS / NTP queries
┌─── Bubble: nextcloud (10.20.1.0/24) ───┐  ┌─── Bubble: gitlab (10.20.2.0/24) ──┐
│  app    10.20.1.11  nginx / Nextcloud  │  │  app   10.20.2.11  GitLab            │
│  db     10.20.1.12  PostgreSQL         │  │  db    10.20.2.12  PostgreSQL         │
│  redis  10.20.1.13  Redis cache        │  │  redis 10.20.2.13  Redis              │
│                                        │  │                                       │
│  ✗ No direct internet access           │  │  ✗ No direct internet access          │
│  ✗ Cannot reach other bubbles          │  │  ✗ Cannot reach other bubbles         │
└────────────────────────────────────────┘  └───────────────────────────────────────┘
```

Each **service bubble** is a self-contained network segment. Bubble members can reach each other and the management zone. They cannot reach other bubbles or the internet directly.

### Dev runtime — hybrid mode

In the default **hybrid** runtime, management services run as Docker containers and workload VMs in each bubble run as real VirtualBox VMs provisioned by Vagrant. The Docker host acts as a router between the two:

```
Your laptop
├── Docker (management zone bridge 10.10.0.0/24)
│     ├── Foreman, Puppet, Ansible, Checkmk, …  (containers)
│     └── Jumphost, Ansible, Checkmk ──────────────┐  routes injected at startup
│                                                   │
└── VirtualBox (host-only networks per bubble)      │
      ├── nextcloud bubble  10.20.1.0/24  ◄─────────┘
      │     ├── dev-local-srv-nextcloud-app    (VM)
      │     ├── dev-local-srv-nextcloud-db     (VM)
      │     └── dev-local-srv-nextcloud-redis  (VM)
      └── …
```

Workload VMs are provisioned with a route to `10.10.0.0/24` via the VirtualBox host-only gateway, so they can reach Puppet, Pulp, DNS, and NTP without any Docker involvement. Developers can `vagrant ssh` or `ssh` through the Jumphost exactly as they would in production.

### How the tools fit together

| Tool | Role | Model |
|------|------|-------|
| **Terraform** | Provisions VMs / containers / networks | One-shot |
| **Foreman** | Single source of truth for inventory and host lifecycle | Continuous |
| **Ansible** | Deploys and configures applications | Push, on-demand |
| **Puppet** | Enforces security baseline — SSH, UFW, NTP, Checkmk agent | Pull, every 30 min |
| **Checkmk** | Monitors all hosts, alerts on drift or failure | Active polling |
| **Pulp** | Serves all OS packages — workload VMs have no internet | Mirror/proxy |

Ansible and Puppet do not conflict: Puppet owns the baseline (immutable config that drifts back automatically), Ansible owns the application layer.

---

## Service Bubbles

A **service bubble** is a group of VMs that form a logical service (e.g. Nextcloud = app + db + Redis). Bubbles are:

- **Network-isolated** from each other — a Nextcloud VM cannot reach a GitLab VM
- **Connected to the management zone** — Puppet, Pulp, DNS, NTP, Ansible, Checkmk all work normally
- **Declared in `config/topology.json`** before you run `startup.sh`

### Defining bubbles

Edit `config/topology.json`:

```json
{
  "bubbles": {
    "nextcloud": {
      "description": "Nextcloud collaboration suite",
      "cidr": "10.20.1.0/24",
      "members": [
        { "name": "app",   "function": "web",   "ip": "10.20.1.11", "role": "nextcloud",       "expose": [{"port": 443}] },
        { "name": "db",    "function": "db",    "ip": "10.20.1.12", "role": "nextcloud-db",    "expose": [] },
        { "name": "redis", "function": "cache", "ip": "10.20.1.13", "role": "nextcloud-redis", "expose": [] }
      ]
    },
    "gitlab": {
      "description": "GitLab CE",
      "cidr": "10.20.2.0/24",
      "members": [
        { "name": "app", "function": "web", "ip": "10.20.2.11", "role": "gitlab", "expose": [{"port": 443}, {"port": 22}] },
        { "name": "db",  "function": "db",  "ip": "10.20.2.12", "role": "gitlab-db", "expose": [] }
      ]
    }
  }
}
```

Then run `./startup.sh dev` — the harness generates all required artefacts automatically.

### What gets generated from `topology.json`

Running `./scripts/gen-topology.sh` (called automatically by `startup.sh`) produces:

| Artefact | Path | Used by |
|----------|------|---------|
| Vagrantfile for workload VMs | `environments/dev/vagrant/Vagrantfile.topology` | hybrid mode |
| Docker Compose overlay | `environments/dev/docker/docker-compose.topology.yml` | docker mode |
| DNS zone fragment | `environments/dev/docker/config/dns/zones/db.topology` | BIND9 ($INCLUDE) |
| Ansible group vars | `ansible/group_vars/bubble_<name>.yml` | bubble-deploy playbook |
| Static inventory | `ansible/inventory/topology.ini` | Ansible (before Foreman) |

### Hostnames

All VMs follow the pattern `{env}-{location}-srv-{bubble}-{member}.{domain}`:

```
dev-local-srv-nextcloud-app.simple-test.org   10.20.1.11
dev-local-srv-nextcloud-db.simple-test.org    10.20.1.12
dev-local-srv-nextcloud-redis.simple-test.org 10.20.1.13
```

### Ansible roles for bubble members

The `role` field in `topology.json` maps to an Ansible role. Place bubble-specific roles in `bubbles/<bubble-name>/ansible/roles/` or in the shared `ansible/roles/` directory. The `bubble-deploy.yml` playbook applies the correct role to each member automatically.

---

## Prerequisites

Run `./startup.sh --install-requirements` to install everything automatically on Arch, Manjaro, Ubuntu, or Debian. For other systems, install the tools below manually.

### Dev — hybrid mode (default)

| Tool | Minimum version |
|------|----------------|
| Bash | 4.0+ |
| Python 3 | 3.8+ |
| Docker + Docker Compose v2 | 24.0+ |
| VirtualBox | 7.0+ |
| Vagrant | 2.3+ |

### Dev — docker mode (no VirtualBox needed)

| Tool | Minimum version |
|------|----------------|
| Docker + Docker Compose v2 | 24.0+ |

### Staging / production

| Tool | Minimum version |
|------|----------------|
| Terraform | 1.5+ |
| Ansible | 2.14+ |
| Cloud provider CLI or vSphere access | — |

### SSH key pair

All environments require an Ed25519 key pair. `--init` defaults to `~/.ssh/id_ed25519.pub`; generate one if it doesn't exist:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "light-admin"
```

Update `ADMIN_SSH_KEY_PATH` in `config/light.env` if you use a different key path.

---

## Configuration

### Quickest path — `--init`

```bash
./startup.sh --init
```

Generates `config/light.env` with all defaults pre-filled and **random 24-character passwords** for Foreman, Checkmk, and Pulp. The generated passwords are printed to stdout once — save them.

```
[  OK ] Created config/light.env

        Generated secrets (save these):
          Foreman:  wOaqH7z0SQQmkBKJPQx8qgpO
          Checkmk:  G0zZLb8PNyimDoToMn08Ljmw
          Pulp:     vkgwDQHash9c7FfOi9D27TNp

        Domain: localhost  (edit LIGHT_DOMAIN to use your own)
```

Prompts before overwriting an existing `config/light.env`. Safe to re-run.

### Manual path — copy the example

```bash
cp config/light.env.example config/light.env
$EDITOR config/light.env
```

**`config/light.env` is gitignored** — it contains credentials and must never be committed.

### Key variables

```bash
# Domain — all hostnames are {env}-{location}-{type}-{function}-{seq}.{LIGHT_DOMAIN}
LIGHT_DOMAIN="localhost"           # --init default; change to your domain

# Environment and provider (overridden by startup.sh arguments)
LIGHT_ENV="dev"
LIGHT_PROVIDER="local"
LIGHT_RUNTIME="hybrid"             # hybrid (default) | docker | vagrant
LIGHT_LOCATION="local"             # used in hostname prefix

# Network
MGMT_ZONE_CIDR="10.10.0.0/24"     # management zone (Docker bridge)
MGMT_GATEWAY="10.10.0.1"          # Docker bridge gateway — hybrid mode router

# Management zone service IPs (must fall within MGMT_ZONE_CIDR)
IP_JUMPHOST="10.10.0.10"
IP_FOREMAN="10.10.0.20"
# ... see config/light.env.example for all IPs

# Credentials (--init generates these randomly)
ADMIN_SSH_KEY_PATH="${HOME}/.ssh/id_ed25519.pub"
FOREMAN_ADMIN_PASS="..."
CHECKMK_ADMIN_PASS="..."
PULP_ADMIN_PASS="..."
```

> Cloud provider credentials (Linode token, AWS keys, GCP project) are also set here — see `config/light.env.example` for the full list.

---

## Quick Start — Dev

### 1. Install host tools (once per machine)

```bash
sudo ./startup.sh --install-requirements
```

Installs Docker, VirtualBox, Vagrant, Terraform, Ansible, and supporting tools. Skips anything already present. Supports **Arch, Manjaro, Ubuntu, Debian**.

After it completes:
- Log out and back in (or run `newgrp docker`) so the `docker` group takes effect
- Reboot if VirtualBox kernel modules were just installed

### 2. Generate config

```bash
./startup.sh --init
```

Creates `config/light.env` with `localhost` as the domain and random passwords for all services. The passwords are printed once — save them.

To use a custom domain or adjust any value, edit the file:

```bash
$EDITOR config/light.env
```

### 3. Declare your service bubbles (optional)

Edit `config/topology.json` to define which VMs to deploy and in which bubbles. If you skip this, only the management zone starts.

### 4. Start

```bash
./startup.sh dev
```

`startup.sh dev` runs in order:

**Hybrid mode (default — Docker mgmt zone + Vagrant workload VMs):**
1. Generates topology artefacts (Vagrantfile, DNS fragment, Ansible vars) from `topology.json`
2. Builds and starts the Docker management zone (DNS, Puppet, Foreman, Ansible, Checkmk, Pulp, Jumphost)
3. Waits for each management service to pass its health check
4. Reloads BIND to pick up bubble DNS records
5. Runs Puppet baseline on management zone via Ansible
6. Injects routes into Ansible/Checkmk/Jumphost containers so they can reach bubble VMs
7. Runs `vagrant up` to start all workload VMs (one VirtualBox VM per bubble member)
8. For each bubble: waits for SSH, runs Puppet baseline, applies application roles, registers in Foreman and Checkmk

### 5. Watch services come up

```bash
./scripts/dev-status.sh --watch
```

### 6. Destroy when done

```bash
./teardown.sh dev
```

### Runtimes

| Runtime | Command | Workloads | Requires |
|---------|---------|-----------|---------|
| `hybrid` (default) | `./startup.sh dev` | Real VirtualBox VMs — SSH-able like prod | Docker + VirtualBox + Vagrant |
| `docker` | `LIGHT_RUNTIME=docker ./startup.sh dev` | Docker containers | Docker only |
| `vagrant` | `LIGHT_RUNTIME=vagrant ./startup.sh dev` | VirtualBox VMs (all services) | VirtualBox + Vagrant |

In **hybrid** mode developers get real VMs they can `vagrant ssh` into or reach through the Jumphost, while management services start quickly as containers.

In **docker** mode everything is a container — useful for CI or machines without VirtualBox.

### Service access (dev)

| Service | Local URL | Credentials |
|---------|-----------|-------------|
| Checkmk | http://localhost:5000/cmk/ | `cmkadmin` / `CHECKMK_ADMIN_PASS` |
| Foreman | https://localhost:9443 | `admin` / `FOREMAN_ADMIN_PASS` |
| Pulp | http://localhost:8080/pulp/api/v3/ | `admin` / `PULP_ADMIN_PASS` |
| Jumphost | `ssh -p 2222 admin@localhost` | SSH key |

> All local ports bind to `127.0.0.1` only — nothing exposed on the external interface.

---

## Quick Start — Staging

```bash
# Set your cloud credentials in config/light.env, then:

./startup.sh staging linode    # or: aws | gcp
./teardown.sh staging linode
```

After `startup.sh` completes, Terraform outputs the Jumphost public IP:

```bash
terraform -chdir=environments/staging/terraform/linode output jumphost_ip
```

---

## Quick Start — Production

```bash
# On-prem (vSphere/NSX):
./startup.sh prod on-prem
./teardown.sh prod on-prem

# Cloud:
./startup.sh prod aws          # or: gcp | linode
./teardown.sh prod aws
```

`teardown.sh` always prompts you to type the environment name before destroying anything:

```
About to DESTROY the 'prod' environment. This is irreversible.
Type the environment name to confirm: prod
```

---

## Monitoring the Stack

### Live status dashboard

```bash
./scripts/dev-status.sh           # one-shot snapshot
./scripts/dev-status.sh --watch   # refreshes every 15 seconds
```

Shows health state, uptime, network isolation check, and Puppet last-run summary for every service.

### Tail logs for a specific service

```bash
./scripts/dev-status.sh --logs checkmk
./scripts/dev-status.sh --logs puppet
./scripts/dev-status.sh --logs foreman
```

### Checkmk monitoring UI

Open http://localhost:5000/cmk/ — login with `cmkadmin` and the password from `CHECKMK_ADMIN_PASS`.

All management zone and bubble hosts are registered automatically during `startup.sh`. Checkmk polls the agent on port 6556 from the management zone.

---

## Firewall Rules — Network Team Submission

Before deploying to staging or production, generate the full firewall rule document:

```bash
./scripts/gen-firewall-rules.sh
# writes to: docs/firewall-rules-{env}-{provider}-{date}.md
```

For a specific environment/provider:

```bash
LIGHT_ENV=staging LIGHT_PROVIDER=aws ./scripts/gen-firewall-rules.sh
LIGHT_ENV=prod    LIGHT_PROVIDER=on-prem ./scripts/gen-firewall-rules.sh
```

The document covers:
- **North–South rules** — external ingress/egress (perimeter firewall / NSX T0 / cloud security groups)
- **East–West rules** — management ↔ bubble zone (NSX DFW / AWS security groups)
- **Per-bubble UFW rules** — host-level isolation applied by Ansible
- **NSX DFW rule summary** — ready-to-paste table for on-prem deployments
- **Pulp internet egress allowlist** — URL list for proxy/URL-filter teams

---

## SSH Access Patterns

All SSH access goes through the Jumphost. Direct connections to management zone or workload VMs are blocked by UFW.

### Dev environment — hybrid mode

Workload VMs have real IPs from `topology.json`. You can reach them via the Jumphost or directly via `vagrant ssh`.

```bash
# SSH to the Jumphost itself
ssh -p 2222 -i ~/.ssh/light_ed25519 admin@localhost

# SSH to a bubble VM through the Jumphost
ssh -i ~/.ssh/light_ed25519 \
    -o ProxyJump="admin@localhost:2222" \
    admin@10.20.1.11

# Or by FQDN (resolved by the internal DNS)
ssh -i ~/.ssh/light_ed25519 \
    -o ProxyJump="admin@localhost:2222" \
    admin@dev-local-srv-nextcloud-app.simple-test.org

# Direct Vagrant SSH (dev convenience — bypasses Jumphost)
cd environments/dev/vagrant
VAGRANT_VAGRANTFILE=Vagrantfile.topology vagrant ssh dev-local-srv-nextcloud-app
```

### Recommended `~/.ssh/config` block (dev)

```
Host light-jump-dev
    HostName localhost
    Port 2222
    User admin
    IdentityFile ~/.ssh/light_ed25519
    StrictHostKeyChecking no

Host dev-local-srv-*.simple-test.org
    User admin
    IdentityFile ~/.ssh/light_ed25519
    ProxyJump light-jump-dev
    StrictHostKeyChecking no
```

Then simply:

```bash
ssh dev-local-srv-nextcloud-app.simple-test.org
ssh dev-local-srv-nextcloud-db.simple-test.org
```

### Staging / production (Jumphost on public IP)

```
Host light-jump-staging
    HostName <jumphost-public-ip>
    Port 22
    User admin
    IdentityFile ~/.ssh/light_ed25519

Host staging-*-srv-*.your-domain.com
    User admin
    IdentityFile ~/.ssh/light_ed25519
    ProxyJump light-jump-staging
```

---

## Custom Domain

The default domain is `simple-test.org`. To use your own:

**1. Set it in `config/light.env`:**

```bash
LIGHT_DOMAIN="infra.your-company.com"
```

**2. Update the dev DNS zone file:**

```
environments/dev/docker/config/dns/zones/db.simple-test.org
environments/dev/docker/config/dns/zones/db.10.10.0
environments/dev/docker/config/dns/zones/db.10.20.0
```

Replace every occurrence of `simple-test.org` with your domain and update the `SOA` record accordingly.

**3. Update Puppet Hiera data** if you change IP ranges:

```yaml
# puppet/data/common.yaml
baseline::checkmk_server: "10.10.0.23"   # update if MGMT_ZONE_CIDR changes
baseline::mgmt_zone_cidr: "10.10.0.0/24"
```

For staging/prod, register your domain with your DNS provider and point it at the Jumphost public IP.

---

## Developer Workflows

### Add a new service bubble

**1. Add the bubble to `config/topology.json`:**

```json
"my-app": {
  "description": "My application",
  "cidr": "10.20.3.0/24",
  "members": [
    { "name": "app", "function": "web", "ip": "10.20.3.11", "role": "my-app",    "expose": [{"port": 443}] },
    { "name": "db",  "function": "db",  "ip": "10.20.3.12", "role": "my-app-db", "expose": [] }
  ]
}
```

**2. Create Ansible roles for each member:**

```
bubbles/my-app/ansible/roles/my-app/tasks/main.yml
bubbles/my-app/ansible/roles/my-app-db/tasks/main.yml
```

**3. Run `./startup.sh dev`** — the harness generates the Vagrantfile, DNS records, group vars, and inventory, then starts the VMs and runs your roles.

To re-deploy a single bubble after startup:

```bash
docker exec dev-local-srv-ans-001 \
    ansible-playbook \
        -i /opt/ansible/inventory/foreman.yml \
        -i /opt/ansible/inventory/topology.ini \
        /opt/ansible/playbooks/bubble-deploy.yml \
        -e bubble_name=my-app \
        --limit bubble_my-app
```

### Re-generate topology artefacts without restarting

```bash
./scripts/gen-topology.sh
```

This updates the Vagrantfile, Docker Compose overlay, DNS fragment, and Ansible vars in place. Run `rndc reload` on the DNS container to pick up new records:

```bash
docker exec dev-local-srv-dns-001 rndc reload
```

### Add a workload role to the shared library

Place generic roles (e.g. `postgresql`, `redis`, `nginx`) in `ansible/roles/` and bubble-specific roles in `bubbles/<name>/ansible/roles/`. Both are searched by the `bubble-deploy.yml` playbook.

### Test network isolation

From inside a workload VM (via Jumphost or `vagrant ssh`):

```bash
# Should succeed — management zone is reachable
curl -fs http://10.10.0.24/pulp/api/v3/status/ && echo "Pulp: OK"
nc -z 10.10.0.21 8140 && echo "Puppet: OK"

# Should fail — no direct internet access
timeout 3 curl -fs https://1.1.1.1 || echo "Internet: blocked (correct)"

# Should fail — cannot reach a different bubble (e.g. 10.20.2.x from nextcloud bubble)
timeout 3 nc -z 10.20.2.11 443 || echo "Cross-bubble: blocked (correct)"
```

---

## Troubleshooting

### Management services not starting / health checks failing

```bash
# Live status with colour-coded health
./scripts/dev-status.sh --watch

# Tail a specific management service log
./scripts/dev-status.sh --logs puppet
./scripts/dev-status.sh --logs foreman

# Full Docker Compose logs
docker compose -f environments/dev/docker/docker-compose.yml logs -f
```

Puppet and Foreman take up to 2 minutes on first start — this is normal. The startup script waits for health checks before proceeding.

### Vagrant VMs not starting (hybrid mode)

```bash
# Check VirtualBox and Vagrant are installed
VBoxManage --version
vagrant --version

# Inspect the generated Vagrantfile
cat environments/dev/vagrant/Vagrantfile.topology

# Bring up a single bubble VM manually
cd environments/dev/vagrant
VAGRANT_VAGRANTFILE=Vagrantfile.topology vagrant up dev-local-srv-nextcloud-app

# Check Vagrant VM status
VAGRANT_VAGRANTFILE=Vagrantfile.topology vagrant status
```

### Cannot SSH to workload VM via Jumphost

```bash
# 1. Confirm Jumphost is up
ssh -p 2222 -i ~/.ssh/light_ed25519 admin@localhost

# 2. Check the route was injected into the Jumphost container
docker exec dev-local-srv-vpn-001 ip route show

# 3. Test reachability from Jumphost to VM
ssh -p 2222 -i ~/.ssh/light_ed25519 admin@localhost \
    "nc -z 10.20.1.11 22 && echo reachable"

# 4. Confirm VM is up and SSH is listening
cd environments/dev/vagrant
VAGRANT_VAGRANTFILE=Vagrantfile.topology vagrant status
VAGRANT_VAGRANTFILE=Vagrantfile.topology vagrant ssh dev-local-srv-nextcloud-app
```

### Route injection not working (hybrid mode)

The Ansible, Checkmk, and Jumphost containers need a route to each bubble CIDR. Routes are injected at startup via `ip route add`. To check or fix manually:

```bash
# Check routes in the Ansible container
docker exec dev-local-srv-ans-001 ip route show

# Inject a missing route (MGMT_GATEWAY defaults to 10.10.0.1)
docker exec dev-local-srv-ans-001 ip route add 10.20.1.0/24 via 10.10.0.1
docker exec dev-local-srv-mon-001 ip route add 10.20.1.0/24 via 10.10.0.1
docker exec dev-local-srv-vpn-001 ip route add 10.20.1.0/24 via 10.10.0.1
```

If `10.10.0.1` is not the Docker bridge gateway on your machine, set `MGMT_GATEWAY` in `config/light.env` to the correct IP:

```bash
docker network inspect $(docker network ls --filter name=mgmt-zone -q) \
    --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}'
```

### Puppet not enforcing baseline on a workload VM

```bash
# Run puppet manually on the VM (via Jumphost or vagrant ssh)
ssh -J admin@localhost:2222 admin@10.20.1.11 \
    "sudo /opt/puppetlabs/bin/puppet agent --test"

# Check Puppet server health
curl -fsk https://localhost:8140/status/v1/simple
```

### Foreman inventory out of sync

```bash
# Re-run the registration playbook
docker exec dev-local-srv-ans-001 \
    ansible-playbook \
        -i /opt/ansible/inventory/foreman.yml \
        /opt/ansible/playbooks/foreman-register.yml

# Query Foreman API directly
curl -u admin:${FOREMAN_ADMIN_PASS} \
     -k https://localhost:9443/api/v2/hosts | python3 -m json.tool
```

### Checkmk not showing a bubble host

```bash
# Re-run Checkmk registration
docker exec dev-local-srv-ans-001 \
    ansible-playbook \
        -i /opt/ansible/inventory/topology.ini \
        /opt/ansible/playbooks/checkmk-register.yml \
        --limit bubble_nextcloud

# Verify the route from Checkmk to the VM
docker exec dev-local-srv-mon-001 nc -z 10.20.1.11 6556 && echo "agent reachable"
```

### DNS not resolving bubble hostnames

```bash
# Test bubble hostname resolution from a management container
docker exec dev-local-srv-ans-001 \
    dig dev-local-srv-nextcloud-app.simple-test.org @10.10.0.30

# Reload DNS after topology changes
docker exec dev-local-srv-dns-001 rndc reload

# Check the generated zone fragment
cat environments/dev/docker/config/dns/zones/db.topology
```

---

## Project Structure

```
light/
├── startup.sh                        # Entry: ./startup.sh <env> [provider/runtime]
├── teardown.sh                       # Teardown: ./teardown.sh <env> [provider/runtime]
│
├── config/
│   ├── light.env.example             # Copy to light.env and fill in credentials
│   └── topology.json                 # Service bubble declaration (VMs, IPs, roles)
│
├── lib/
│   ├── common.sh                     # Shared helpers (config loader, hostname builder)
│   ├── logging.sh                    # log::info / log::warn / log::error / log::section
│   └── preflight.sh                  # Pre-flight checks per runtime and environment
│
├── scripts/
│   ├── dev-status.sh                 # Live dev stack status and log tailing
│   ├── gen-firewall-rules.sh         # Generate firewall rule document for network team
│   ├── gen-topology.sh               # Generate all artefacts from topology.json
│   └── lib/
│       └── gen_topology.py           # Python generator: Vagrantfile, Compose, DNS, Ansible vars
│
├── bubbles/                          # One directory per service bubble
│   └── nextcloud/
│       ├── bubble.yml                # Bubble metadata
│       └── ansible/roles/            # Bubble-specific Ansible roles
│           ├── nextcloud/
│           ├── nextcloud-db/
│           └── nextcloud-redis/
│
├── environments/
│   ├── dev/
│   │   ├── startup.sh / teardown.sh
│   │   ├── docker/
│   │   │   ├── docker-compose.yml           # Management zone only (Docker)
│   │   │   ├── docker-compose.topology.yml  # Auto-generated: bubble containers (docker mode)
│   │   │   ├── build/                       # Dockerfiles: workload, jumphost, ansible
│   │   │   └── config/dns/                  # BIND9 named.conf + zone files
│   │   └── vagrant/
│   │       ├── Vagrantfile                  # Full-Vagrant mode (all services as VMs)
│   │       └── Vagrantfile.topology         # Auto-generated: bubble VMs (hybrid mode)
│   ├── staging/
│   │   ├── startup.sh / teardown.sh
│   │   └── terraform/{linode,aws,gcp}/
│   └── prod/
│       ├── startup.sh / teardown.sh
│       └── terraform/{on-prem,aws,gcp,linode}/
│
├── terraform/
│   └── modules/
│       ├── vm/                       # Provider-agnostic VM (Linode/AWS/GCP/vSphere)
│       └── management-zone/          # Deploys all 10 management services
│
├── ansible/
│   ├── inventory/
│   │   ├── foreman.yml               # Dynamic inventory from Foreman (theforeman collection)
│   │   └── topology.ini              # Auto-generated static inventory (used before Foreman)
│   ├── group_vars/
│   │   └── bubble_<name>.yml         # Auto-generated per-bubble vars (IPs, member list)
│   ├── playbooks/
│   │   ├── baseline.yml              # Puppet baseline via Ansible
│   │   ├── bubble-deploy.yml         # UFW isolation + application roles per bubble
│   │   ├── foreman-register.yml      # Register hosts in Foreman
│   │   ├── checkmk-register.yml      # Register hosts in Checkmk
│   │   └── pulp-sync.yml             # Trigger Pulp package sync
│   └── roles/
│       ├── common/                   # UFW, DNS, NTP, Pulp APT source
│       ├── bubble-ufw/               # Cross-bubble isolation rules
│       ├── puppet-agent/             # Install and configure Puppet agent
│       ├── checkmk/                  # Install Checkmk agent, open port 6556
│       ├── webserver/                # nginx
│       ├── database/                 # PostgreSQL
│       ├── foreman/                  # Post-start Foreman configuration
│       └── jumphost/                 # SSH hardening, fail2ban, UFW
│
└── puppet/
    ├── manifests/site.pp             # node default { include baseline }
    ├── modules/baseline/             # SSH, UFW, NTP, Checkmk agent, Puppet cron
    ├── hiera.yaml                    # Hiera config (data/ directory)
    └── data/common.yaml              # Default values (IPs, CIDRs) — override per env
```

---

## License

See [LICENSE](LICENSE).
