variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_account_id" {
  type        = string
  description = "Your Cloudflare Account ID"
}

variable "zones" {
  type = map(object({
    domain = string
  }))
}

variable "dns_records" {
  type = map(list(object({
    hostname = string
    type     = string
    target   = string
    proxied  = optional(bool, true)   # default = true for partial setups
    ttl      = optional(number)
  })))
}
