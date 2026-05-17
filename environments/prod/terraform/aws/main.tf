terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region"     { default = "eu-central-1" }
variable "domain"         { default = "simple-test.org" }
variable "env"            { default = "prod" }
variable "location"       { default = "aws-eu" }
variable "mgmt_zone_cidr" { default = "10.10.0.0/24" }
variable "workload_cidr"  { default = "10.20.0.0/24" }
variable "admin_ssh_key"  {}

module "management_zone" {
  source = "../../../../terraform/modules/management-zone"

  provider_name  = "aws"
  env            = var.env
  location       = var.location
  domain         = var.domain
  mgmt_zone_cidr = var.mgmt_zone_cidr
  workload_cidr  = var.workload_cidr
  admin_ssh_key  = var.admin_ssh_key
}

module "workload_web" {
  source = "../../../../terraform/modules/vm"

  provider_name  = "aws"
  env            = var.env
  location       = var.location
  domain         = var.domain
  vm_type        = "srv"
  vm_function    = "web"
  vm_seq         = "001"
  network_cidr   = var.workload_cidr
  mgmt_zone_cidr = var.mgmt_zone_cidr
  puppet_server  = module.management_zone.puppet_ip
  admin_ssh_key  = var.admin_ssh_key
  # Production sizing
  cpu_count      = 4
  memory_mb      = 8192
  disk_gb        = 100
}

module "workload_db" {
  source = "../../../../terraform/modules/vm"

  provider_name  = "aws"
  env            = var.env
  location       = var.location
  domain         = var.domain
  vm_type        = "srv"
  vm_function    = "db"
  vm_seq         = "001"
  network_cidr   = var.workload_cidr
  mgmt_zone_cidr = var.mgmt_zone_cidr
  puppet_server  = module.management_zone.puppet_ip
  admin_ssh_key  = var.admin_ssh_key
  cpu_count      = 4
  memory_mb      = 16384
  disk_gb        = 200
}
