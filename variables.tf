# variables.tf – All user-configurable options with defaults
# Options: Set in terraform.tfvars; use defaults for quick starts
# For advanced: Add vars for more zones, custom WAF expressions, etc.

variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "Scoped API token with Zone:Edit, Account:Edit permissions – create in Cloudflare dashboard"
}

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare account ID from dashboard – required for all resources"
}

variable "zones" {
  type = map(object({
    domain = string
  }))
  description = "Map of zones to onboard (e.g., { main = { domain = \"example.com\" } }) – add more for multi-zone setups"
}

variable "dns_records" {
  type = map(list(object({
    hostname = string               # "" for apex, "www" for subdomains
    type     = string               # "A", "CNAME", etc.
    target   = string               # Origin IP or hostname
    proxied  = optional(bool, true) # True = orange cloud (proxy through Cloudflare)
    ttl      = optional(number)     # Auto if proxied; set for gray cloud
  })))
  description = "Proxied records per zone – only managed in CF for partial setup"
}

variable "itar_restricted_countries" {
  type        = list(string)
  default     = ["CU", "IR", "KP", "SY", "RU", "BY", "VE"]
  description = "ISO codes for ITAR blocks – customize for compliance; applies to LB rules"
}

variable "enable_tunnel" {
  type        = bool
  default     = true
  description = "Enable zero-trust tunnel – set false to skip"
}

variable "tunnel_public_hostname" {
  type        = string
  default     = "time.faithtechinc.com"
  description = "Public hostname for the tunnel (e.g., app.example.com) – must be proxied"
}

variable "app_port" {
  type        = number
  default     = 80
  description = "Local port the app listens on – used in tunnel config and HAProxy"
}

variable "proxy_vm_app_server_ips" {
  type        = list(string)
  default     = ["10.0.1.10", "10.0.1.11"]
  description = "Private IPs of the two app servers – HAProxy balances to these"
}

variable "enable_advanced_cert" {
  type        = bool
  default     = true
  description = "Enable advanced cert pack – set false for standard Universal SSL"
}

variable "primary_zone_key" {
  type        = string
  default     = "main"
  description = "Key from zones map for LB/CNAME placement – change if multiple zones"
}
