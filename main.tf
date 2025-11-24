# main.tf – Cloudflare v5 Syntax (Fixed for Errors)
# Changes from v4: zone → name; account_id → account; tunnels under zero_trust namespace; added account_id to monitor

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ================================
# ZONES – Partial (CNAME) setup (v5: uses 'name' not 'zone')
# ================================
resource "cloudflare_zone" "this" {
  for_each = var.zones

  account_id = var.cloudflare_account_id  # v5 requires this
  name       = each.value.domain  # v5 uses 'name' instead of 'zone'
  type       = "partial"  # No NS change – Pro/Business+ required
}

# ================================
# DNS RECORDS – Proxied only (v5: zone_id unchanged)
# ================================
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
  comment = "Terraform-managed – partial setup"
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

# ================================
# BOT MANAGEMENT – Safe challenge mode (v5: unchanged)
# ================================
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

# ================================
# MANAGED WAF + OWASP – Log-only start (v5: rules syntax unchanged)
# ================================
resource "cloudflare_ruleset" "managed_waf_log" {
  for_each = cloudflare_zone.this
  zone_id  = each.value.id
  name     = "Managed WAF & OWASP – LOG ONLY"
  kind     = "zone"
  phase    = "http_request_firewall_managed"

  rules {
    action      = "log"
    expression  = "true"
    enabled     = true
    description = "Cloudflare Managed Ruleset – LOG"
    execute {
      id = "efb7b8c949ac4650a0e52a9c2d13d3bb"
    }
  }

  rules {
    action      = "log"
    expression  = "true"
    enabled     = true
    description = "OWASP Core Ruleset – LOG"
    execute {
      id = data.cloudflare_rulesets.owasp[each.key].rulesets[0].id
    }
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

# ================================
# WAF EXCEPTIONS – For false positives (v5: unchanged)
# ================================
resource "cloudflare_ruleset" "waf_exceptions" {
  for_each = cloudflare_zone.this
  zone_id  = each.value.id
  name     = "WAF Exceptions – false positives"
  kind     = "zone"
  phase    = "http_request_firewall_managed"

  # Example: Skip a noisy rule
  # rules {
  #   action      = "skip"
  #   expression  = "true"
  #   description = "Skip rule 981173 – Wordpress false positive"
  #   enabled     = true
  #   action_parameters {
  #     id = "981173"
  #   }
  # }
}

# ================================
# RATE LIMITING – Log-only start (v5: unchanged)
# ================================
resource "cloudflare_ruleset" "rate_limiting" {
  for_each = cloudflare_zone.this
  zone_id  = each.value.id
  name     = "Rate Limiting – LOG only"
  kind     = "zone"
  phase    = "http_ratelimit"

  rules {
    enabled     = true
    description = "Login protection – safe start"
    expression  = "(http.request.uri.path contains \"/login\")"
    action      = "log"

    ratelimit {
      characteristics     = ["ip.src", "cf.client.asn"]
      period              = 60
      requests_per_period = 15
      mitigation_timeout  = 600
    }
  }
}

# ================================
# ZONE HARDENING SETTINGS (v5: unchanged)
# ================================
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
    websocket                = "on"
  }
}

# ================================
# CLOUDFLARED TUNNEL – Zero-trust reverse proxy (v5: renamed to zero_trust_tunnel)
# ================================
resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel" "app_tunnel" {
  account_id = var.cloudflare_account_id  # v5 requires this
  name       = "app-to-cloudflare-tunnel"
  secret     = random_id.tunnel_secret.b64_std  # v5 unchanged
}

resource "cloudflare_zero_trust_tunnel_config" "app_tunnel_config" {
  tunnel_id = cloudflare_zero_trust_tunnel.app_tunnel.id  # v5 renamed resource

  config {
    ingress_rule {
      hostname = var.tunnel_public_hostname
      service  = "http://localhost:${var.app_port}"
    }

    ingress_rule {
      service = "http_status:404"
    }
  }
}

# Tunnel CNAME – Proxied for WAF/Bot (v5: unchanged)
resource "cloudflare_record" "tunnel_cname" {
  zone_id = cloudflare_zone.this[var.primary_zone_key].id
  name    = split(".", var.tunnel_public_hostname)[0]
  type    = "CNAME"
  value   = "${cloudflare_zero_trust_tunnel.app_tunnel.id}.cfargotunnel.com"  # Updated for v5 tunnel
  proxied = true
  comment = "Tunnel CNAME – Terraform-managed"
}

# ================================
# ADVANCED CERT PACK – Dedicated certs (v5: unchanged)
# ================================
resource "cloudflare_certificate_pack" "advanced_cert" {
  for_each = var.enable_advanced_cert ? cloudflare_zone.this : {}

  zone_id          = each.value.id
  type             = "advanced"
  hosts            = [each.value.zone, "*.${each.value.zone}"]
  validation_method = "txt"
  validity_days    = 30
  certificate_authority = "digicert"
  cloudflare_branding  = false
}

# ================================
# GLOBAL LOAD BALANCING – Between app servers via tunnel (v5: monitor requires account_id)
# ================================
resource "cloudflare_load_balancer" "app_lb" {
  zone_id          = cloudflare_zone.this[var.primary_zone_key].id
  name             = var.tunnel_public_hostname
  fallback_pool_id = cloudflare_load_balancer_pool.app_pool.id
  default_pool_ids = [cloudflare_load_balancer_pool.app_pool.id]
  proxied          = true

  steering_policy  = "geo"
  session_affinity = "ip_cookie"
  session_affinity_ttl = 14400

  rules {
    name = "itar_block"
    fixed_response {
      status_code  = 403
      message_body = "Access Denied – Restricted Country"
    }
    condition {
      matches {
        name  = "ip.geoip.country"
        op    = "in"
        value = var.itar_restricted_countries
      }
    }
    priority = 1
  }
}

resource "cloudflare_load_balancer_pool" "app_pool" {
  name = "app-pool"
  origins {
    name    = "tunnel-origin"
    address = "${cloudflare_zero_trust_tunnel.app_tunnel.id}.cfargotunnel.com"  # v5 tunnel ID
    enabled = true
    weight  = 1
  }
  monitor = cloudflare_load_balancer_monitor.app_monitor.id
}

resource "cloudflare_load_balancer_monitor" "app_monitor" {
  account_id = var.cloudflare_account_id  # v5 required arg
  expected_codes = "2xx, 3xx"
  method         = "GET"
  path           = "/health"
  interval       = 60
  timeout        = 5
  retries        = 2
}
