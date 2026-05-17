# Generic VM module — provider-agnostic interface.
# Each provider block is conditionally activated based on provider_name.
# Hostname follows: {env}-{location}-{type}-{function}-{seq}.{domain}

variable "provider_name" {}
variable "env" {}
variable "location" {}
variable "domain" {}
variable "vm_type" { default = "srv" }
variable "vm_function" {}
variable "vm_seq" {}
variable "network_cidr" {}
variable "mgmt_zone_cidr" { default = "" }
variable "workload_cidr" { default = "" }
variable "puppet_server" {}
variable "admin_ssh_key" {}
variable "static_ip" { default = "" }

# Sizing defaults — override per environment via tfvars
variable "cpu_count" { default = 2 }
variable "memory_mb" { default = 2048 }
variable "disk_gb" { default = 40 }
variable "image" { default = "ubuntu-24-04" } # Linode label; overridden per provider

locals {
  hostname = "${var.env}-${var.location}-${var.vm_type}-${var.vm_function}-${var.vm_seq}"
  fqdn     = "${local.hostname}.${var.domain}"

  default_mgmt_cidr = var.mgmt_zone_cidr != "" ? var.mgmt_zone_cidr : var.network_cidr
  workload_cidrs    = var.workload_cidr != "" ? [var.workload_cidr] : []

  service_ingress = concat(
    [
      {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = var.vm_function == "vpn" ? ["0.0.0.0/0"] : [local.default_mgmt_cidr]
        description = "SSH access"
      },
      {
        from_port   = 6556
        to_port     = 6556
        protocol    = "tcp"
        cidr_blocks = [local.default_mgmt_cidr]
        description = "Checkmk agent polling"
      },
    ],
    var.vm_function == "frm" ? [
      {
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = [local.default_mgmt_cidr]
        description = "Foreman HTTPS"
      },
      {
        from_port   = 9090
        to_port     = 9090
        protocol    = "tcp"
        cidr_blocks = [local.default_mgmt_cidr]
        description = "Foreman Smart Proxy"
      },
    ] : [],
    var.vm_function == "bas" ? [
      {
        from_port   = 8140
        to_port     = 8140
        protocol    = "tcp"
        cidr_blocks = distinct(concat([local.default_mgmt_cidr], local.workload_cidrs))
        description = "Puppet ENC and agent pull"
      },
    ] : [],
    var.vm_function == "mon" ? [
      {
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = distinct(concat([local.default_mgmt_cidr], local.workload_cidrs))
        description = "Checkmk web UI"
      },
      {
        from_port   = 6556
        to_port     = 6556
        protocol    = "tcp"
        cidr_blocks = distinct(concat([local.default_mgmt_cidr], local.workload_cidrs))
        description = "Checkmk agent polling"
      },
    ] : [],
    var.vm_function == "upd" ? [
      {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = distinct(concat([local.default_mgmt_cidr], local.workload_cidrs))
        description = "Pulp HTTP"
      },
      {
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = distinct(concat([local.default_mgmt_cidr], local.workload_cidrs))
        description = "Pulp HTTPS"
      },
    ] : [],
    var.vm_function == "dns" ? [
      {
        from_port   = 53
        to_port     = 53
        protocol    = "tcp"
        cidr_blocks = distinct(concat([local.default_mgmt_cidr], local.workload_cidrs))
        description = "DNS TCP"
      },
      {
        from_port   = 53
        to_port     = 53
        protocol    = "udp"
        cidr_blocks = distinct(concat([local.default_mgmt_cidr], local.workload_cidrs))
        description = "DNS UDP"
      },
    ] : [],
    var.vm_function == "ntp" ? [
      {
        from_port   = 123
        to_port     = 123
        protocol    = "udp"
        cidr_blocks = distinct(concat([local.default_mgmt_cidr], local.workload_cidrs))
        description = "NTP"
      },
    ] : [],
    var.vm_function == "db" ? [
      {
        from_port   = 5432
        to_port     = 5432
        protocol    = "tcp"
        cidr_blocks = [var.network_cidr]
        description = "PostgreSQL"
      },
      {
        from_port   = 3306
        to_port     = 3306
        protocol    = "tcp"
        cidr_blocks = [var.network_cidr]
        description = "MySQL/MariaDB"
      },
    ] : []
  )

  gcp_firewall_rules = { for rule in local.service_ingress :
    "${rule.protocol}-${rule.from_port}-${rule.to_port}-${replace(join("-", rule.cidr_blocks), "/", ".")}" => rule
  }

  # Cloud-init user-data: installs Puppet agent and points it at the Puppet server.
  # This is the only bootstrap step — Puppet handles everything after first run.
  user_data = <<-EOT
    #cloud-config
    hostname: ${local.hostname}
    fqdn: ${local.fqdn}
    manage_etc_hosts: true
    package_update: true
    packages:
      - curl
      - ca-certificates
    runcmd:
      - curl -fsSL https://apt.puppet.com/puppet8-release-$(lsb_release -cs).deb -o /tmp/puppet.deb
      - dpkg -i /tmp/puppet.deb
      - apt-get update -q
      - apt-get install -y puppet-agent
      - /opt/puppetlabs/bin/puppet config set server ${var.puppet_server} --section agent
      - /opt/puppetlabs/bin/puppet agent --onetime --no-daemonize --waitforcert 120
    ssh_authorized_keys:
      - ${var.admin_ssh_key}
  EOT
}

# ── Linode ──────────────────────────────────────────────────────────────────
resource "linode_instance" "vm" {
  count = var.provider_name == "linode" ? 1 : 0

  label     = local.hostname
  region    = "eu-central"
  type      = "g6-standard-2"
  image     = "linode/ubuntu24.04"
  user_data = base64encode(local.user_data)

  authorized_keys = [var.admin_ssh_key]

  tags = [var.env, var.vm_function, "light"]

  lifecycle {
    ignore_changes = [user_data]
  }
}

# ── AWS ─────────────────────────────────────────────────────────────────────
resource "aws_instance" "vm" {
  count = var.provider_name == "aws" ? 1 : 0

  ami                    = data.aws_ami.ubuntu[0].id
  instance_type          = "t3.small"
  user_data              = local.user_data
  key_name               = aws_key_pair.light[0].key_name
  vpc_security_group_ids = [aws_security_group.light[0].id]

  tags = {
    Name      = local.hostname
    Env       = var.env
    Function  = var.vm_function
    ManagedBy = "light"
  }
}

data "aws_ami" "ubuntu" {
  count       = var.provider_name == "aws" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "light" {
  count      = var.provider_name == "aws" ? 1 : 0
  key_name   = "light-${var.env}-${var.vm_function}-${var.vm_seq}"
  public_key = var.admin_ssh_key
}

resource "aws_security_group" "light" {
  count = var.provider_name == "aws" ? 1 : 0
  name  = "light-${local.hostname}"

  dynamic "ingress" {
    for_each = var.provider_name == "aws" ? local.service_ingress : []
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
      description = ingress.value.description
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "light-${local.hostname}" }
}

# ── GCP ─────────────────────────────────────────────────────────────────────
resource "google_compute_instance" "vm" {
  count        = var.provider_name == "gcp" ? 1 : 0
  name         = local.hostname
  machine_type = "e2-small"
  zone         = "europe-west3-a"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts"
      size  = var.disk_gb
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  metadata = {
    user-data = local.user_data
    ssh-keys  = "admin:${var.admin_ssh_key}"
  }

  tags = [local.hostname, "light"]

  labels = {
    env        = var.env
    function   = var.vm_function
    managed-by = "light"
  }
}

resource "google_compute_firewall" "light" {
  for_each = var.provider_name == "gcp" ? local.gcp_firewall_rules : {}

  name          = "${local.hostname}-${each.key}"
  network       = "default"
  target_tags   = [local.hostname]
  source_ranges = each.value.cidr_blocks

  allow {
    protocol = each.value.protocol
    ports    = each.value.from_port == each.value.to_port ? [tostring(each.value.from_port)] : [format("%d-%d", each.value.from_port, each.value.to_port)]
  }

  description = each.value.description
}

# ── Outputs ──────────────────────────────────────────────────────────────────
output "hostname" { value = local.hostname }
output "fqdn" { value = local.fqdn }
output "ip" {
  value = coalesce(
    var.provider_name == "linode" ? try(linode_instance.vm[0].ip_address, "") : "",
    var.provider_name == "aws" ? try(aws_instance.vm[0].private_ip, "") : "",
    var.provider_name == "gcp" ? try(google_compute_instance.vm[0].network_interface[0].network_ip, "") : "",
    var.static_ip
  )
}
