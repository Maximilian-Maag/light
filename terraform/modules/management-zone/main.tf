# Management zone module — deploys the full set of management services
# (Jumphost, Foreman, Puppet, Ansible, Checkmk, Pulp, DNS, NTP) on any provider.
# Outputs IPs consumed by the vm module and Ansible playbooks.

variable "provider_name" {}
variable "env" {}
variable "location" {}
variable "domain" {}
variable "mgmt_zone_cidr" {}
variable "workload_cidr" {}
variable "admin_ssh_key" {}

locals {
  name_prefix = "${var.env}-${var.location}"
  # Fixed offsets within the management zone subnet
  cidr_base   = cidrhost(var.mgmt_zone_cidr, 0)
  ip_jumphost = cidrhost(var.mgmt_zone_cidr, 10)
  ip_foreman  = cidrhost(var.mgmt_zone_cidr, 20)
  ip_puppet   = cidrhost(var.mgmt_zone_cidr, 21)
  ip_ansible  = cidrhost(var.mgmt_zone_cidr, 22)
  ip_checkmk  = cidrhost(var.mgmt_zone_cidr, 23)
  ip_pulp     = cidrhost(var.mgmt_zone_cidr, 24)
  ip_dns_pri  = cidrhost(var.mgmt_zone_cidr, 30)
  ip_dns_sec  = cidrhost(var.mgmt_zone_cidr, 31)
  ip_ntp_pri  = cidrhost(var.mgmt_zone_cidr, 32)
  ip_ntp_sec  = cidrhost(var.mgmt_zone_cidr, 33)

  services = {
    jumphost = { func = "vpn", seq = "001", ip = local.ip_jumphost }
    foreman  = { func = "frm", seq = "001", ip = local.ip_foreman }
    puppet   = { func = "bas", seq = "001", ip = local.ip_puppet }
    ansible  = { func = "ans", seq = "001", ip = local.ip_ansible }
    checkmk  = { func = "mon", seq = "001", ip = local.ip_checkmk }
    pulp     = { func = "upd", seq = "001", ip = local.ip_pulp }
    dns_pri  = { func = "dns", seq = "001", ip = local.ip_dns_pri }
    dns_sec  = { func = "dns", seq = "002", ip = local.ip_dns_sec }
    ntp_pri  = { func = "ntp", seq = "001", ip = local.ip_ntp_pri }
    ntp_sec  = { func = "ntp", seq = "002", ip = local.ip_ntp_sec }
  }
}

# Provider-specific VM resources are instantiated via the vm module.
# This module acts as a composition root — each service gets a VM.
module "service_vms" {
  source   = "../vm"
  for_each = local.services

  provider_name  = var.provider_name
  env            = var.env
  location       = var.location
  domain         = var.domain
  vm_type        = "srv"
  vm_function    = each.value.func
  vm_seq         = each.value.seq
  static_ip      = each.value.ip
  network_cidr   = var.mgmt_zone_cidr
  mgmt_zone_cidr = var.mgmt_zone_cidr
  workload_cidr  = var.workload_cidr
  puppet_server  = local.ip_puppet
  admin_ssh_key  = var.admin_ssh_key
}

output "jumphost_ip" { value = local.ip_jumphost }
output "foreman_ip" { value = local.ip_foreman }
output "puppet_ip" { value = local.ip_puppet }
output "ansible_ip" { value = local.ip_ansible }
output "checkmk_ip" { value = local.ip_checkmk }
output "pulp_ip" { value = local.ip_pulp }
output "dns_primary" { value = local.ip_dns_pri }
output "dns_secondary" { value = local.ip_dns_sec }
