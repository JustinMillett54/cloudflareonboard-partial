# versions.tf – Defines Terraform version and providers
# Options: Update provider versions as new releases come out (check registry.terraform.io)
# If adding VM automation, add providers like bpg/proxmox or hashicorp/vsphere here
terraform {
  required_version = ">= 1.8" # Minimum Terraform version – upgrade for new features like import blocks

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.13" # Locks to latest v5 series – check for updates quarterly
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6" # For generating tunnel secrets – optional but secure
    }
  }
}
