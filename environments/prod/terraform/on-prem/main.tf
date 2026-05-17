terraform {
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "~> 2.0"
    }
  }
}

provider "vsphere" {
  vsphere_server       = var.vsphere_server
  user                 = var.vsphere_user
  password             = var.vsphere_password
  allow_unverified_ssl = false
}

variable "vsphere_server" {}
variable "vsphere_user" {}
variable "vsphere_password" { sensitive = true }
variable "vsphere_datacenter" {}
variable "vsphere_cluster" {}
variable "vsphere_datastore" {}
variable "domain" { default = "simple-test.org" }
variable "env" { default = "prod" }
variable "location" { default = "vie" }
variable "mgmt_zone_cidr" { default = "10.10.0.0/24" }
variable "workload_cidr" { default = "10.20.0.0/24" }
variable "admin_ssh_key" {}

module "management_zone" {
  source = "../../../../terraform/modules/management-zone"

  provider_name  = "vsphere"
  env            = var.env
  location       = var.location
  domain         = var.domain
  mgmt_zone_cidr = var.mgmt_zone_cidr
  workload_cidr  = var.workload_cidr
  admin_ssh_key  = var.admin_ssh_key
}

module "workload_web" {
  source = "../../../../terraform/modules/vm"

  provider_name = "vsphere"
  env           = var.env
  location      = var.location
  domain        = var.domain
  vm_type       = "srv"
  vm_function   = "web"
  vm_seq        = "001"
  network_cidr  = var.workload_cidr
  puppet_server = module.management_zone.puppet_ip
  admin_ssh_key = var.admin_ssh_key
}

module "workload_db" {
  source = "../../../../terraform/modules/vm"

  provider_name = "vsphere"
  env           = var.env
  location      = var.location
  domain        = var.domain
  vm_type       = "srv"
  vm_function   = "db"
  vm_seq        = "001"
  network_cidr  = var.workload_cidr
  puppet_server = module.management_zone.puppet_ip
  admin_ssh_key = var.admin_ssh_key
}
