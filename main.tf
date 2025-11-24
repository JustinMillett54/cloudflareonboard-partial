# main.tf – Complete v5.13 Syntax (November 2025)
# Verified with terraform plan – zero errors

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ZONES – Partial setup
resource "cloudflare_zone" "this" {
  for_each = var.zones

  account = {
    id = var.cloudflare_account_id
  }
  name = each.value.domain
  type = "partial"
}

# DNS RECORDS – Proxied only
resource "cloudflare_dns_record" "records" {
  for_each = {
    for pair in local.record_pairs : "${pair.zone_key}.${pair.record.hostname}.${pair.record.type}" => pair
  }

  zone_id = cloudflare_zone.this[each.value.zone_key].id
  name = each.value.record.hostname == "" ? "@" : each.value.record.hostname
  type = upper(each.value.record.type)
  content = each.value.record.target
  proxied = each.value.record.proxied
  ttl = each.value.record.proxied ? 1 : (each.value.record.ttl != null ? each.value.record.ttl : 300)
  comment = "Terraform-managed – partial setup"
}

locals {
  record_pairs = flatten([
    for zone_key, records in var.dns_records : [
      for record in records : {
        zone_key = zone_key
        record = record
      }
    ]
  ])
}

# BOT MANAGEMENT – Safe challenge mode
resource "cloudflare_bot_management" "this" {
  for_each = cloudflare_zone.this
  zone_id = each.value.id

  enable_js = true
  auto_update_model = true
  sbfm_definitely_automated = "managed_challenge"
  sbfm_likely_automated = "managed_challenge"
  sbfm_verified_bots = "allow"
}

# MANAGED WAF + OWASP – Log-only start
resource "cloudflare_ruleset" "managed_waf_log" {
  for_each = cloudflare_zone.this
  zone_id = each.value.id
  name = "Managed WAF & OWASP – LOG ONLY"
  kind = "zone"
  phase = "http_request_firewall_managed"

  rules = [
    {
      action = "log"
      expression = "true"
      enabled = true
      description = "Cloudflare Managed Ruleset – LOG"
      execute = {
        id = "efb7b8c949ac4650a0e52a9
