provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# <<< ONLY DIFFERENCE FROM FULL TEMPLATE >>>
resource "cloudflare_zone" "this" {
  for_each   = var.zones
  account_id = var.cloudflare_account_id
  zone       = each.value.domain
  type       = "partial"          # ← Partial / CNAME setup – no NS change
}

resource "cloudflare_record" "records" {
  for_each = {
    for pair in local.record_pairs : "${pair.zone_key}.${pair.record.hostname}.${pair.record.type}" => pair
  }

  zone_id = cloudflare_zone.this[each.value.zone_key].id
  name    = each.value.record.hostname == "" ? "@" : each.value.record.hostname
  type    = upper(each.value.record.type)
  value   = each.value.record.target
  proxied = each.value.record.proxied
  ttl     = each.value.record.proxied ? 1 : (each.value.record.ttl != null ? each.value.record.ttl : 300)
  comment = "Terraform-managed – partial log-first"
}

locals {
  record_pairs = flatten([
    for zone_key, records in var.dns_records : [
      for record in records : {
        zone_key = zone_key
        record   = record
      }
    ]
  ])
}

# Bot Management – safe start
resource "cloudflare_bot_management" "this" {
  for_each = cloudflare_zone.this
  zone_id  = each.value.id
  enable_js                   = true
  auto_update_model           = true
  static_resource_protection  = true
  definitely_automated_action = "managed_challenge"
  likely_automated_action     = "managed_challenge"
  verified_bots_action        = "allow"
}

# Managed WAF + OWASP – LOG only
resource "cloudflare_ruleset" "managed_waf_log" {
  for_each = cloudflare_zone.this
  zone_id  = each.value.id
  name     = "Managed WAF – LOG ONLY (safe start)"
  kind     = "zone"
  phase    = "http_request_firewall_managed"

  rule {
    action      = "log"      # ← change to "execute" when ready
    expression  = "true"
    enabled     = true
    description = "Cloudflare Managed Ruleset – LOG"
    ref         = "efb7b8c949ac4650a0e52a9c2d13d3bb"
  }

  rule {
    action      = "log"
    expression  = "true"
    enabled     = true
    description = "OWASP Core Ruleset – LOG"
    ref         = data.cloudflare_rulesets.owasp[each.key].rulesets.0.id
  }
}

data "cloudflare_rulesets" "owasp" {
  for_each = cloudflare_zone.this
  zone_id  = each.value.id
  filter {
    kind  = "managed"
    name  = "Cloudflare OWASP Core Ruleset"
    phase = "http_request_firewall_managed"
  }
}

# Disable noisy rules here
resource "cloudflare_ruleset" "waf_exceptions" {
  for_each = cloudflare_zone.this
  zone_id  = each.value.id
  name     = "WAF Exceptions – false positives"
  kind     = "zone"
  phase    = "http_request_firewall_managed"

  # rule {
  #   action      = "skip"
  #   expression  = "true"
  #   description = "Skip rule 981173 – Wordpress false positive"
  #   enabled     = true
  #   ref         = "981173"
  #   skip { ruleset = "current" }
  # }
}

# Rate limiting – LOG only
resource "cloudflare_ruleset" "rate_limiting" {
  for_each = cloudflare_zone.this
  zone_id  = each.value.id
  name     = "Rate Limiting – LOG only"
  kind     = "zone"
  phase    = "http_ratelimit"

  rule {
    enabled     = true
    description = "Login protection"
    expression  = "(http.request.uri.path contains \"/login\")"
    action      = "log"        # ← change to "block" when ready
    ratelimit {
      characteristics     = ["ip.src"]
      period              = 60
      requests_per_period = 15
      mitigation_timeout  = 600
    }
  }
}

resource "cloudflare_zone_settings_override" "this" {
  for_each = cloudflare_zone.this
  zone_id  = each.value.id
  settings {
    ssl                      = "strict"
    always_use_https         = "on"
    min_tls_version          = "1.3"
    tls_1_3                  = "on"
    automatic_https_rewrites = "on"
    security_level           = "high"
    brotli                   = "on"
  }
}
