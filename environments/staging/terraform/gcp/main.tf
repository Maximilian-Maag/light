terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

variable "gcp_project" {}
variable "gcp_region" { default = "europe-west3" }
variable "domain" { default = "simple-test.org" }
variable "env" { default = "staging" }
variable "location" { default = "gcp-eu" }
variable "mgmt_zone_cidr" { default = "10.10.0.0/24" }
variable "workload_cidr" { default = "10.20.0.0/24" }
variable "admin_ssh_key" {}

module "management_zone" {
  source = "../../../../terraform/modules/management-zone"

  provider_name  = "gcp"
  env            = var.env
  location       = var.location
  domain         = var.domain
  mgmt_zone_cidr = var.mgmt_zone_cidr
  workload_cidr  = var.workload_cidr
  admin_ssh_key  = var.admin_ssh_key
}

module "workload_web" {
  source = "../../../../terraform/modules/vm"

  provider_name = "gcp"
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

  provider_name = "gcp"
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
