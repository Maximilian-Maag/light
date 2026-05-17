# Light Infrastructure - Usage Guide

**Light** (**L**inux **I**nfrastructure **G**eneral **H**arness **T**ool) is an enterprise infrastructure simulator that provisions and configures isolated VMs with strict firewall rules, service bubbles, and controlled access through a jumphost bastion. It leverages Terraform for infrastructure, Ansible for configuration, Puppet for baseline enforcement, and Foreman for inventory management.

## Architecture Overview

### Network Topology

- **Management Zone (10.10.0.0/24)**: Core services (Jumphost, Foreman, Puppet, Ansible, Checkmk, Pulp, DNS, NTP)
- **Workload Zone (10.20.0.0/24)**: Application VMs (databases, web servers)
- **Service Bubble Isolation**: Strict ingress/egress rules per service function
- **Single Entry Point**: Jumphost bastion (10.10.0.10) for all external SSH access

### Deployment Pipeline

```
Terraform (Infrastructure) 
  ↓
Ansible (Configuration & Hardening)
  ↓
Foreman (Dynamic Inventory & Lifecycle)
  ↓
Puppet (Continuous Baseline Enforcement)
```

## Prerequisites

### System Requirements

- Terraform 1.0+
- Ansible 2.9+
- Docker & Docker Compose (for dev environment)
- Vagrant (for dev environment alternative)
- SSH key pair for admin access
- Cloud provider credentials (AWS, GCP, Linode) or vSphere/NSX for on-prem

### Environment Variables

Create `.env` file in the `config/` directory (use `light.env.example` as template):

```bash
# Cloud Provider
PROVIDER=linode  # Options: aws, gcp, linode, vsphere

# SSH Configuration
ADMIN_SSH_KEY_PATH=/path/to/admin/ssh/key
ADMIN_SSH_USER=admin

# Foreman (optional, for inventory management)
FOREMAN_URL=https://foreman.example.com
FOREMAN_USER=admin
FOREMAN_PASSWORD=password

# Network Configuration (example values)
MGMT_ZONE_CIDR=10.10.0.0/24
WORKLOAD_ZONE_CIDR=10.20.0.0/24
```

## Quick Start

### Development Environment (Docker)

#### 1. Start Infrastructure

```bash
cd environments/dev
./startup.sh
```

This will:
- Build Docker images (Ansible controller, Jumphost, Workload)
- Create Docker Compose network with management and workload zones
- Deploy Jumphost as SSH bastion
- Configure hardened firewall rules
- Deploy a sample workload VM

#### 2. Wait for Readiness

```bash
# Check container status
docker ps

# Verify Jumphost is ready (should return SSH banner)
ssh -i /path/to/admin/key admin@jumphost.local -p 22
```

#### 3. SSH to Workload VM via Jumphost

```bash
# Method 1: Port forwarding through jumphost
ssh -i /path/to/admin/key \
    -o ProxyCommand="ssh -i /path/to/admin/key -W %h:%p admin@jumphost.local" \
    admin@workload-vm.local

# Method 2: Using ssh config (~/.ssh/config)
Host jumphost
    HostName jumphost.local
    User admin
    IdentityFile /path/to/admin/key
    StrictHostKeyChecking no

Host workload-vm
    HostName workload-vm.local
    User admin
    IdentityFile /path/to/admin/key
    ProxyJump jumphost
    StrictHostKeyChecking no

# Then simply:
ssh workload-vm
```

#### 4. Verify Network Isolation

From jumphost, test connectivity:

```bash
# Can reach management services
curl -k https://foreman.10-10-0-20.nip.io:9090

# Cannot reach internet (strict egress policy)
ping 8.8.8.8  # Should timeout
```

#### 5. Cleanup

```bash
./teardown.sh
```

---

### Staging Environment (Cloud Multi-Region)

#### 1. Configure Cloud Provider

Set credentials and provider in `.env`:

```bash
export PROVIDER=aws  # or gcp, linode
export AWS_ACCESS_KEY_ID=xxxxx
export AWS_SECRET_ACCESS_KEY=xxxxx
export AWS_REGION=us-east-1
```

#### 2. Start Infrastructure

```bash
cd environments/staging
./startup.sh
```

Terraform will provision:
- VPCs and security groups
- Management zone with core services
- Workload zone with example application tier
- Dynamic DNS records (if enabled)

#### 3. SSH to VMs

Get the Jumphost IP from Terraform output:

```bash
terraform -chdir=terraform/aws output jumphost_ip
```

SSH through jumphost to workload VMs:

```bash
ssh -i /path/to/admin/key \
    -o ProxyCommand="ssh -i /path/to/admin/key -W %h:%p admin@<JUMPHOST_IP>" \
    admin@<WORKLOAD_VM_IP>
```

#### 4. Cleanup

```bash
./teardown.sh
```

---

### Production Environment (On-Premises or Large Scale)

#### 1. Configure vSphere/NSX (for on-prem)

```bash
# In config/light.env:
export VSPHERE_SERVER=vcenter.example.com
export VSPHERE_USER=administrator@vsphere.local
export VSPHERE_PASSWORD=xxxxx
export VSPHERE_DATACENTER=Datacenter1
export VSPHERE_CLUSTER=Cluster1
export VSPHERE_NETWORK_MGMT=Management
export VSPHERE_NETWORK_WORKLOAD=Workload
export NSX_MANAGER=nsx-manager.example.com
export NSX_USERNAME=admin
export NSX_PASSWORD=xxxxx
```

#### 2. Apply Terraform

```bash
cd environments/prod/terraform/on-prem
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

#### 3. SSH to VMs

Same method as staging:

```bash
ssh -i /path/to/admin/key \
    -o ProxyCommand="ssh -i /path/to/admin/key -W %h:%p admin@<JUMPHOST_IP>" \
    admin@<WORKLOAD_VM_IP>
```

---

## Developer Workflows

### Running the Entire Stack Locally

```bash
# Start dev environment
cd environments/dev
./startup.sh

# Wait for services to be healthy (~2 minutes)
sleep 120

# SSH to workload VM
ssh -i ~/.ssh/admin-key admin@workload-vm.local -o ProxyCommand="ssh -i ~/.ssh/admin-key -W %h:%p admin@jumphost.local"

# On the workload VM, verify installed components
ansible --version
puppet --version
```

### Deploying a Workload

1. **Create workload role** in `ansible/roles/my-workload/`:

```yaml
# ansible/roles/my-workload/tasks/main.yml
---
- name: Install my application
  apt:
    name:
      - python3-flask
    state: present

- name: Start my service
  systemd:
    name: my-app
    state: started
    enabled: yes
```

2. **Add to playbook** `ansible/playbooks/site.yml`:

```yaml
- hosts: workload_servers
  roles:
    - common
    - my-workload
```

3. **Run deployment**:

```bash
ansible-playbook -i inventory/foreman.yml playbooks/site.yml --limit my-workload
```

### Testing Firewall Rules

```bash
# SSH to a workload VM
ssh -i ~/.ssh/admin-key admin@workload-vm.local -o ProxyCommand="..."

# Test allowed outbound (should succeed)
curl -I http://pulp.10-10-0-24.nip.io/pulp/api/v3/

# Test denied outbound (should timeout or fail)
timeout 2 curl -I http://google.com

# Test inbound from jumphost (should succeed)
# From jumphost:
ssh admin@workload-vm.local

# Test inbound from workload to management (should fail)
# From workload:
ssh admin@foreman.10-10-0-20.nip.io  # Should timeout (no reverse path)
```

### Debugging Issues

#### Check Foreman Inventory

```bash
# Access Foreman web UI (from jumphost)
# https://foreman.10-10-0-20.nip.io:9090
# Default credentials: admin/changeme

# Or query via API
curl -u admin:changeme \
  https://foreman.10-10-0-20.nip.io/api/v2/hosts \
  -k
```

#### Check Puppet Catalog

```bash
# SSH to workload VM
ssh -i ~/.ssh/admin-key admin@workload-vm.local -o ProxyCommand="..."

# View last Puppet run
puppet config print lastrunfile | xargs cat

# Manually trigger Puppet run
sudo puppet agent --test
```

#### Check Firewall Rules

```bash
# On workload VM, check UFW status
sudo ufw status verbose

# Check blocked connections
sudo tail -f /var/log/ufw.log
```

#### Check Ansible Logs

```bash
# On Ansible controller (in dev: ansible container)
cat /var/log/ansible.log

# Or in staging/prod:
journalctl -u ansible -n 100
```

---

## Key Service IPs (Management Zone)

| Service | IP | Port | Purpose |
|---------|----|----|---------|
| Jumphost | 10.10.0.10 | 22 | SSH bastion for external access |
| Foreman | 10.10.0.20 | 443/9090 | Infrastructure provisioning & inventory |
| Puppet Master | 10.10.0.21 | 8140 | Baseline enforcement (30-min pull cycle) |
| Ansible | 10.10.0.22 | 22 | Orchestration controller |
| Checkmk | 10.10.0.23 | 443/6556 | Monitoring & alerting |
| Pulp | 10.10.0.24 | 80/443 | Package mirror & content management |
| DNS | 10.10.0.30-31 | 53 | Name resolution |
| NTP | 10.10.0.32-33 | 123 | Time synchronization |

---

## Firewall Policy Summary

### Inbound (Ingress)

- **SSH from external**: Only via Jumphost (0.0.0.0/0 → 10.10.0.10:22)
- **Service APIs**: Only from authorized CIDR blocks (mgmt/workload)
- **Agent polling**: Checkmk (port 6556), Puppet (port 8140)

### Outbound (Egress)

**Management Zone** (restricted):
- DNS queries (port 53)
- NTP sync (port 123)
- Puppet updates (port 8140)
- Jumphost (port 22, for testing)
- Ansible (port 22)
- Pulp mirror (ports 80, 443)

**Workload Zone** (restricted):
- Same as management, plus:
- Limited egress to management services for monitoring

### East-West (Internal)

- Management ↔ Workload: Only allowed services (Puppet, Checkmk, Pulp)
- No cross-workload communication
- All internal traffic encrypted (mTLS for sensitive services)

---

## Troubleshooting

### Jumphost Connection Refused

```bash
# Ensure jumphost container is running (dev)
docker ps | grep jumphost

# Check SSH is listening
docker logs jumphost 2>&1 | grep "listening"

# Verify SSH key permissions
chmod 600 /path/to/admin/key
```

### Workload VM Unreachable via Jumphost

```bash
# Test from jumphost (dev, in container)
docker exec jumphost ssh -v admin@workload-vm.local

# Check UFW rules on workload VM
sudo ufw status verbose

# Check routing/DNS resolution
nslookup workload-vm.local
```

### Puppet Not Enforcing Baseline

```bash
# Check Puppet agent status
sudo systemctl status puppet

# Check puppet logs
sudo journalctl -u puppet -n 50

# Verify puppet server is reachable
telnet puppet.10-10-0-21.nip.io 8140

# Manually run puppet agent
sudo puppet agent --test --verbose
```

### Foreman Inventory Out of Sync

```bash
# Re-register host with Foreman
ansible-playbook -i inventory/hosts.yml playbooks/foreman-register.yml

# Check Foreman API for host details
curl -u admin:changeme https://foreman.local/api/v2/hosts/myhost -k
```

---

## Advanced Configuration

### Custom Service Functions

Add new service types by modifying `terraform/modules/vm/main.tf` locals:

```hcl
locals {
  service_ingress = concat(
    # ...existing services...
    var.vm_function == "cache" ? [{
      protocol = "tcp"
      from_port = 6379
      to_port = 6379
      cidr_blocks = [var.workload_cidr]
    }] : []
  )
}
```

### Multi-Cloud Deployment

Deploy same infrastructure across multiple clouds:

```bash
cd environments/staging

# AWS
terraform -chdir=terraform/aws apply

# GCP
terraform -chdir=terraform/gcp apply

# Linode
terraform -chdir=terraform/linode apply
```

---

## Support & Documentation

- **Terraform Modules**: See [terraform/modules/README.md](terraform/modules/README.md)
- **Ansible Roles**: See [ansible/roles/README.md](ansible/roles/README.md)
- **Puppet Manifests**: See [puppet/README.md](puppet/README.md)
- **Firewall Rules**: Run `scripts/gen-firewall-rules.sh` for production rule submission

---

## License

See [LICENSE](LICENSE) file.
