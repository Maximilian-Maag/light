#!/usr/bin/env bash
# Generate a complete firewall rule submission document for the network team.
# Covers: per-host UFW rules, NSX DFW rules (on-prem), cloud security group rules.
#
# Usage: ./scripts/gen-firewall-rules.sh [output-file]
#   output-file defaults to docs/firewall-rules-{env}-{provider}-{date}.md

set -euo pipefail

LIGHT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${LIGHT_ROOT}/lib/common.sh"
load_config

DATE="$(date +%Y-%m-%d)"
DEFAULT_OUT="${LIGHT_ROOT}/docs/firewall-rules-${LIGHT_ENV}-${LIGHT_PROVIDER}-${DATE}.md"
OUT="${1:-${DEFAULT_OUT}}"

mkdir -p "$(dirname "${OUT}")"

# ── Convenience aliases from config ──────────────────────────────────────────
MGMT="${MGMT_ZONE_CIDR}"
WORK="${WORKLOAD_CIDR}"
J="${IP_JUMPHOST}"
FRM="${IP_FOREMAN}"
PUP="${IP_PUPPET}"
ANS="${IP_ANSIBLE}"
CMK="${IP_CHECKMK}"
PULP="${IP_PULP}"
DNS1="${IP_DNS_PRIMARY}"
DNS2="${IP_DNS_SECONDARY}"
NTP1="${IP_NTP_PRIMARY}"
NTP2="${IP_NTP_SECONDARY}"

# ── Build hostname labels ─────────────────────────────────────────────────────
h_jump="$(build_hostname srv vpn 001) (${J})"
h_frm="$(build_hostname srv frm 001) (${FRM})"
h_pup="$(build_hostname srv bas 001) (${PUP})"
h_ans="$(build_hostname srv ans 001) (${ANS})"
h_cmk="$(build_hostname srv mon 001) (${CMK})"
h_pulp="$(build_hostname srv upd 001) (${PULP})"
h_dns1="$(build_hostname srv dns 001) (${DNS1})"
h_dns2="$(build_hostname srv dns 002) (${DNS2})"
h_ntp1="$(build_hostname srv ntp 001) (${NTP1})"
h_ntp2="$(build_hostname srv ntp 002) (${NTP2})"

# ─────────────────────────────────────────────────────────────────────────────
generate() {
cat <<DOCUMENT
# Firewall Rule Submission — light infrastructure

| Field       | Value |
|-------------|-------|
| Environment | \`${LIGHT_ENV}\` |
| Provider    | \`${LIGHT_PROVIDER}\` |
| Domain      | \`${LIGHT_DOMAIN}\` |
| Generated   | ${DATE} |
| Tool        | light (https://github.com/your-org/light) |

> Submit this document to your network team before deploying to **${LIGHT_ENV}/${LIGHT_PROVIDER}**.
> Rules are listed in order of priority. Default policy is **DENY ALL** on all hosts.

---

## Network Zones

| Zone | CIDR | Description |
|------|------|-------------|
| Management Zone | \`${MGMT}\` | Internal management services — not reachable from external |
| Workload Zone   | \`${WORK}\` | Application workload nodes |
| External        | \`0.0.0.0/0\` | Internet / corporate WAN |

## Management Zone Hosts

| Hostname | IP | Role |
|----------|----|------|
| ${h_jump}  | Jumphost — sole external SSH entry point |
| ${h_frm}   | Foreman — inventory & lifecycle management |
| ${h_pup}   | Puppet server — baseline enforcement |
| ${h_ans}   | Ansible controller — application deployment |
| ${h_cmk}   | Checkmk — monitoring |
| ${h_pulp}  | Pulp — package mirror (only host with internet egress) |
| ${h_dns1}  | DNS primary |
| ${h_dns2}  | DNS secondary |
| ${h_ntp1}  | NTP primary |
| ${h_ntp2}  | NTP secondary |

---

## 1 · North–South Rules (External ↔ Infrastructure)

_Firewall device: perimeter firewall / NSX T0 Gateway / Cloud Security Group boundary_

| # | Direction | Source | Destination | Protocol | Port(s) | Service | Justification |
|---|-----------|--------|-------------|----------|---------|---------|---------------|
| NS-01 | INBOUND  | \`0.0.0.0/0\`    | \`${J}\`    | TCP | 22      | SSH          | Operator access — only entry point |
| NS-02 | OUTBOUND | \`${PULP}\`      | \`0.0.0.0/0\` | TCP | 80,443 | HTTP/HTTPS  | Ubuntu/Debian package sync (Pulp) |
| NS-03 | OUTBOUND | \`${PULP}\`      | \`0.0.0.0/0\` | TCP | 443    | HTTPS       | Container registry sync (Docker Hub, Quay.io, ECR) |
| NS-04 | OUTBOUND | \`${PULP}\`      | \`0.0.0.0/0\` | TCP | 443    | HTTPS       | Language registries (PyPI, npm, Maven, Helm) |
| NS-05 | DENY ALL | \`0.0.0.0/0\`    | \`${MGMT}\` | —   | —       | —           | Block all other external inbound to management zone |
| NS-06 | DENY ALL | \`0.0.0.0/0\`    | \`${WORK}\` | —   | —       | —           | Block all external inbound to workload zone |

---

## 2 · East–West Rules: Management Zone Internal

_Firewall device: host-level UFW (enforced by Puppet) + NSX Distributed Firewall_

| # | Source | Destination | Protocol | Port(s) | Service |
|---|--------|-------------|----------|---------|---------|
| EW-01 | \`${MGMT}\` | \`${DNS1}\`  | UDP+TCP | 53   | DNS queries — primary |
| EW-02 | \`${MGMT}\` | \`${DNS2}\`  | UDP+TCP | 53   | DNS queries — secondary (failover) |
| EW-03 | \`${MGMT}\` | \`${NTP1}\`  | UDP     | 123  | NTP — primary |
| EW-04 | \`${MGMT}\` | \`${NTP2}\`  | UDP     | 123  | NTP — secondary (failover) |
| EW-05 | \`${FRM}\`  | \`${PUP}\`   | TCP     | 8140 | Foreman → Puppet API (ENC) |
| EW-06 | \`${ANS}\`  | \`${FRM}\`   | TCP     | 443  | Ansible → Foreman HTTPS (dynamic inventory) |
| EW-07 | \`${ANS}\`  | \`${FRM}\`   | TCP     | 9090 | Ansible → Foreman Smart Proxy |
| EW-08 | \`${J}\`    | \`${MGMT}\`  | TCP     | 22   | Jumphost → mgmt zone SSH (operator access) |

---

## 3 · East–West Rules: Management Zone → Workload Zone

_Firewall device: NSX DFW inter-segment rule / Cloud Security Group / UFW on workload hosts_

| # | Source | Destination | Protocol | Port(s) | Service | Note |
|---|--------|-------------|----------|---------|---------|------|
| MW-01 | \`${J}\`   | \`${WORK}\` | TCP | 22   | Jumphost SSH to workload nodes | bastion access |
| MW-02 | \`${ANS}\` | \`${WORK}\` | TCP | 22   | Ansible SSH to workload nodes | app deployment |
| MW-03 | \`${CMK}\` | \`${WORK}\` | TCP | 6556 | Checkmk agent polling | active monitoring pull |

---

## 4 · East–West Rules: Workload Zone → Management Zone

_Firewall device: NSX DFW inter-segment rule / Cloud Security Group / UFW on mgmt hosts_

| # | Source | Destination | Protocol | Port(s) | Service | Note |
|---|--------|-------------|----------|---------|---------|------|
| WM-01 | \`${WORK}\` | \`${PUP}\`  | TCP     | 8140   | Puppet agent pull | every 30 min |
| WM-02 | \`${WORK}\` | \`${PULP}\` | TCP     | 80,443 | Package mirror (apt/dnf) | no direct internet |
| WM-03 | \`${WORK}\` | \`${DNS1}\` | UDP+TCP | 53     | DNS — primary |
| WM-04 | \`${WORK}\` | \`${DNS2}\` | UDP+TCP | 53     | DNS — secondary (failover) |
| WM-05 | \`${WORK}\` | \`${NTP1}\` | UDP     | 123    | NTP — primary |
| WM-06 | \`${WORK}\` | \`${NTP2}\` | UDP     | 123    | NTP — secondary (failover) |
| WM-07 | \`${WORK}\` | \`${CMK}\`  | TCP     | 443    | Checkmk agent registration & alerts |

---

## 5 · East–West Rules: Workload Zone Internal

_Adjust ports to match your application stack. These are defaults._

| # | Source | Destination | Protocol | Port(s) | Service |
|---|--------|-------------|----------|---------|---------|
| WW-01 | Web servers | DB servers | TCP | 5432 | PostgreSQL |
| WW-02 | Web servers | DB servers | TCP | 3306 | MySQL / MariaDB |
| WW-03 | DENY ALL    | \`${WORK}\` | —   | —    | Block all other intra-workload traffic |

---

## 6 · Per-Host UFW Rules (enforced by Puppet — 30 min pull cycle)

_These are applied on every host by the Puppet baseline class.
They do not replace the zone-level rules above — they are an additional host-level enforcement layer._

### ${h_jump}
\`\`\`
ufw default deny incoming
ufw default allow outgoing
ufw allow in  proto tcp from 0.0.0.0/0     to ${J}    port 22    # NS-01 operator SSH
ufw allow out proto tcp from ${J}           to ${MGMT} port 22    # EW-08 mgmt SSH
ufw allow out proto tcp from ${J}           to ${WORK} port 22    # MW-01 workload SSH
\`\`\`

### ${h_frm}
\`\`\`
ufw default deny incoming
ufw default allow outgoing
ufw allow in  proto tcp  from ${MGMT}  to ${FRM}  port 443   # Foreman HTTPS UI
ufw allow in  proto tcp  from ${MGMT}  to ${FRM}  port 9090  # Smart Proxy
ufw allow in  proto tcp  from ${J}     to ${FRM}  port 22    # SSH via jumphost
\`\`\`

### ${h_pup}
\`\`\`
ufw default deny incoming
ufw default allow outgoing
ufw allow in  proto tcp  from ${MGMT}  to ${PUP}  port 8140  # EW-05 Foreman ENC
ufw allow in  proto tcp  from ${WORK}  to ${PUP}  port 8140  # WM-01 agent pull
ufw allow in  proto tcp  from ${J}     to ${PUP}  port 22    # SSH via jumphost
\`\`\`

### ${h_ans}
\`\`\`
ufw default deny incoming
ufw default allow outgoing
ufw allow in  proto tcp  from ${J}     to ${ANS}  port 22    # SSH via jumphost
# Ansible only initiates outbound connections — no inbound application ports needed
\`\`\`

### ${h_cmk}
\`\`\`
ufw default deny incoming
ufw default allow outgoing
ufw allow in  proto tcp  from ${MGMT}  to ${CMK}  port 443   # Checkmk web UI
ufw allow in  proto tcp  from ${WORK}  to ${CMK}  port 443   # WM-07 agent registration
ufw allow in  proto tcp  from ${J}     to ${CMK}  port 22    # SSH via jumphost
\`\`\`

### ${h_pulp}
\`\`\`
ufw default deny incoming
ufw default allow outgoing
ufw allow in  proto tcp  from ${MGMT}  to ${PULP} port 80    # Pulp HTTP
ufw allow in  proto tcp  from ${MGMT}  to ${PULP} port 443   # Pulp HTTPS
ufw allow in  proto tcp  from ${WORK}  to ${PULP} port 80    # WM-02 package mirror
ufw allow in  proto tcp  from ${WORK}  to ${PULP} port 443   # WM-02 package mirror
ufw allow in  proto tcp  from ${J}     to ${PULP} port 22    # SSH via jumphost
# Outbound internet access for sync: allowed (NS-02, NS-03, NS-04)
\`\`\`

### ${h_dns1} / ${h_dns2}
\`\`\`
ufw default deny incoming
ufw default allow outgoing
ufw allow in  proto udp  from ${MGMT}  to any      port 53    # EW-01/02 DNS mgmt
ufw allow in  proto tcp  from ${MGMT}  to any      port 53    # EW-01/02 DNS mgmt (TCP)
ufw allow in  proto udp  from ${WORK}  to any      port 53    # WM-03/04 DNS workload
ufw allow in  proto tcp  from ${WORK}  to any      port 53    # WM-03/04 DNS workload (TCP)
ufw allow in  proto tcp  from ${J}     to any      port 22    # SSH via jumphost
\`\`\`

### ${h_ntp1} / ${h_ntp2}
\`\`\`
ufw default deny incoming
ufw default allow outgoing
ufw allow in  proto udp  from ${MGMT}  to any  port 123  # EW-03/04 NTP mgmt
ufw allow in  proto udp  from ${WORK}  to any  port 123  # WM-05/06 NTP workload
ufw allow in  proto tcp  from ${J}     to any  port 22   # SSH via jumphost
\`\`\`

### Workload nodes (all)
\`\`\`
ufw default deny incoming
ufw default allow outgoing
ufw allow in  proto tcp  from ${J}     to any  port 22    # MW-01 SSH via jumphost
ufw allow in  proto tcp  from ${ANS}   to any  port 22    # MW-02 Ansible deployment
ufw allow in  proto tcp  from ${CMK}   to any  port 6556  # MW-03 Checkmk agent poll
# Application ports (add per workload type):
#   Web:  ufw allow in proto tcp from 0.0.0.0/0 to any port 80,443
#   DB:   ufw allow in proto tcp from ${WORK} to any port 5432   (WW-01)
\`\`\`

---

## 7 · NSX Distributed Firewall Rule Summary (On-Prem only)

_Create these as named rules in the NSX DFW policy. Apply to the relevant segments._

| Priority | Name | Source | Destination | Service | Action |
|----------|------|--------|-------------|---------|--------|
| 100 | allow-operator-ssh-jumphost | External | ${h_jump} | SSH (TCP/22) | ALLOW |
| 110 | allow-pulp-internet-egress | ${h_pulp} | External | HTTP+HTTPS | ALLOW |
| 200 | allow-dns-from-mgmt | Management-Zone-Segment | DNS Group | DNS (TCP+UDP/53) | ALLOW |
| 210 | allow-dns-from-workload | Workload-Segment | DNS Group | DNS (TCP+UDP/53) | ALLOW |
| 220 | allow-ntp-from-mgmt | Management-Zone-Segment | NTP Group | NTP (UDP/123) | ALLOW |
| 230 | allow-ntp-from-workload | Workload-Segment | NTP Group | NTP (UDP/123) | ALLOW |
| 300 | allow-jumphost-to-mgmt | ${h_jump} | Management-Zone-Segment | SSH (TCP/22) | ALLOW |
| 310 | allow-jumphost-to-workload | ${h_jump} | Workload-Segment | SSH (TCP/22) | ALLOW |
| 320 | allow-ansible-to-workload | ${h_ans} | Workload-Segment | SSH (TCP/22) | ALLOW |
| 330 | allow-checkmk-to-workload | ${h_cmk} | Workload-Segment | TCP/6556 | ALLOW |
| 400 | allow-puppet-pull | Workload-Segment | ${h_pup} | TCP/8140 | ALLOW |
| 410 | allow-pulp-from-workload | Workload-Segment | ${h_pulp} | HTTP+HTTPS | ALLOW |
| 420 | allow-checkmk-registration | Workload-Segment | ${h_cmk} | HTTPS (TCP/443) | ALLOW |
| 500 | allow-workload-web-internal | Web-Group | DB-Group | TCP/5432,3306 | ALLOW |
| 900 | deny-external-to-mgmt | External | Management-Zone-Segment | Any | DENY |
| 910 | deny-external-to-workload | External | Workload-Segment | Any | DENY |
| 999 | default-deny-all | Any | Any | Any | DENY |

---

## 8 · Pulp Internet Egress Allowlist

_The following URLs must be reachable from \`${PULP}\` for package synchronization.
Submit to the firewall/proxy team separately if using URL-based filtering._

### Linux packages
- \`archive.ubuntu.com\` — Ubuntu package mirror
- \`security.ubuntu.com\` — Ubuntu security updates
- \`deb.debian.org\` — Debian packages
- \`security.debian.org\` — Debian security updates

### Container registries
- \`registry-1.docker.io\` / \`index.docker.io\` — Docker Hub
- \`quay.io\` — Red Hat / Quay
- \`public.ecr.aws\` — Amazon ECR Public
- \`gcr.io\` / \`ghcr.io\` — Google / GitHub container registries

### Language registries (enable only what your workloads need)
- \`pypi.org\` / \`files.pythonhosted.org\` — Python (PyPI)
- \`registry.npmjs.org\` — Node.js (npm)
- \`repo.maven.apache.org\` — Java (Maven Central)

---

_Generated by **light** — https://github.com/your-org/light_
_Regenerate: \`./scripts/gen-firewall-rules.sh\`_
DOCUMENT
}
# ─────────────────────────────────────────────────────────────────────────────

generate > "${OUT}"
log::ok "Firewall rules written to ${OUT}"

# Also print to stdout so it can be piped
generate
