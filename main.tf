# main.tf – Core configuration
# Structure: Zones → Records → Security (WAF/Bot/Rate/ITAR) → Tunnel → Certs → LB
# Options: Toggle features with vars; change "log" to "execute" for production

provider "cloudflare" {
  api_token = var.cloudflare_api_token  # Auth for all Cloudflare resources
}

# ================================
# ZONES – Partial (CNAME) setup
# Options: Add more in vars.zones; change type = "full" if switching to full DNS later
# ================================
resource "cloudflare_zone" "this" {
  for_each   = var.zones
  account_id = var.cloudflare_account_id
  zone       = each.value.domain
  type       = "partial"  # Key for no NS change – only proxy specific hostnames
}

# ================================
# DNS RECORDS – Proxied only
# Options: Add non-proxied records in external DNS; proxied = true enables WAF/Bot
# ================================
resource "cloudflare_record" "records" {
  for_each = {
    for pair in local.record_pairs : "${pair.zone_key}.${pair.record.hostname}.${pair.record.type}" => pair
  }

  zone_id = cloudflare_zone.this[each.value.zone_key].id
  name    = each.value.record.hostname == "" ? "@" : each.value.record.hostname
  type    = upper(each.value.record.type)
  value   = each.value.record.target
  proxied = each.value.record.proxied  # True = orange cloud (recommended)
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
# BOT MANAGEMENT – Safe challenge mode
# Options: Change actions to "block" for production; enable_js = false if no JS needed
# ================================
resource "cloudflare_bot_management" "this" {
  for_each = cloudflare_zone.this
  zone_id  = each.value.id

  enable_js                   = true  # Invisible JS challenges – set false for API-only
  auto_update_model           = true  # Auto-update bot models – recommended
  static_resource_protection  = true  # Protect CSS/JS/images – optional
  definitely_automated_action = "managed_challenge"  # Score 1 – change to "block" when ready
  likely_automated_action     = "managed_challenge"  # Score 2-29 – change to "block" when ready
  verified_bots_action        = "allow"  # Always allow good bots like Googlebot
}

# ================================
# MANAGED WAF + OWASP – Log-only start
# Options: Change "log" to "execute" for blocking; add more rulesets like Exposed Credentials
# ================================
resource "cloudflare_ruleset" "managed_waf_log" {
  for_each = cloudflare_zone.this
  zone_id  = each.value.id
  name     = "Managed WAF & OWASP – LOG ONLY"
  kind     = "zone"
  phase    = "http_request_firewall_managed"

  rules {
    action      = "log"  # Change to "execute" when ready to block
    expression  = "true"
    enabled     = true
    description = "Cloudflare Managed Ruleset – LOG"
    execute {
      id = "efb7b8c949ac4650a0e52a9c2d13d3bb"
    }
  }

  rules {
    action      = "log"  # Change to "execute" when ready to block
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
# WAF EXCEPTIONS – For false positives
# Options: Uncomment and add rule IDs from dashboard events; use "skip" or "log"
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
# RATE LIMITING – Log-only start
# Options: Change "log" to "block"; add more rules for specific paths; adjust thresholds
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
    action      = "log"  # Change to "block" or "managed_challenge"

    ratelimit {
      characteristics     = ["ip.src", "cf.client.asn"]  # Add "http.request.headers[\"x-api-key\"]" for API
      period              = 60  # Seconds – adjust for burst vs sustained
      requests_per_period = 15  # Threshold – tune based on testing
      mitigation_timeout  = 600  # Ban duration in seconds
    }
  }
}

# ================================
# ZONE HARDENING SETTINGS
# Options: Adjust security_level to "high" or "under_attack"; add min_tls_version = "1.2" if needed
# ================================
resource "cloudflare_zone_settings_override" "this" {
  for_each = cloudflare_zone.this
  zone_id  = each.value.id

  settings {
    ssl                      = "strict"  # "full" or "flexible" for less secure origins
    always_use_https         = "on"
    min_tls_version          = "1.3"  # "1.2" for legacy clients
    tls_1_3                  = "on"
    automatic_https_rewrites = "on"
    security_level           = "high"  # "medium" or "under_attack" for DDoS
    brotli                   = "on"
    websocket                = "on"
  }
}

# ================================
# CLOUDFLARED TUNNEL – Zero-trust reverse proxy
# Options: Add more ingress_rules for additional hostnames/services (e.g., SSH)
# ================================
resource "random_id" "tunnel_secret" {
  byte_length = 32  # Increase for more security if needed
}

resource "cloudflare_tunnel" "app_tunnel" {
  account_id = var.cloudflare_account_id
  name       = "app-to-cloudflare-tunnel"
  secret     = random_id.tunnel_secret.b64_std
}

resource "cloudflare_tunnel_config" "app_tunnel_config" {
  tunnel_id = cloudflare_tunnel.app_tunnel.id

  config {
    ingress_rule {
      hostname = var.tunnel_public_hostname
      service  = "http://localhost:${var.app_port}"  # Points to local HAProxy on proxy VMs
    }

    ingress_rule {
      service = "http_status:404"  # Catch-all – customize for custom errors
    }
  }
}

# Tunnel CNAME – Proxied for WAF/Bot
resource "cloudflare_record" "tunnel_cname" {
  zone_id = cloudflare_zone.this[var.primary_zone_key].id
  name    = split(".", var.tunnel_public_hostname)[0]
  type    = "CNAME"
  value   = "${cloudflare_tunnel.app_tunnel.id}.cfargotunnel.com"
  proxied = true
  comment = "Tunnel CNAME – Terraform-managed"
}

# ================================
# ADVANCED CERT PACK – Dedicated certs
# Options: Change validity_days to 90/365; certificate_authority = "lets_encrypt" for free
# ================================
resource "cloudflare_certificate_pack" "advanced_cert" {
  for_each = var.enable_advanced_cert ? cloudflare_zone.this : {}

  zone_id          = each.value.id
  type             = "advanced"
  hosts            = [each.value.zone, "*.${each.value.zone}"]  # Add specific hosts if needed
  validation_method = "txt"  # "http" or "email" alternatives
  validity_days    = 30  # Shorter = more secure rotations
  certificate_authority = "digicert"  # "lets_encrypt" or "google"
  cloudflare_branding  = false  # True to show Cloudflare in cert
}

# ================================
# GLOBAL LOAD BALANCING – Between app servers via tunnel
# Options: steering_policy = "random" or "proximity"; add more origins for multi-DC
# ================================
resource "cloudflare_load_balancer" "app_lb" {
  zone_id          = cloudflare_zone.this[var.primary_zone_key].id
  name             = var.tunnel_public_hostname
  fallback_pool_id = cloudflare_load_balancer_pool.app_pool.id
  default_pool_ids = [cloudflare_load_balancer_pool.app_pool.id]
  proxied          = true  # Enables WAF/Bot

  steering_policy = "geo"  # Geo steering – change to "proximity" for latency-based
  session_affinity = "ip_cookie"  # Session affinity – "cookie" or "header" alternatives
  session_affinity_ttl = 14400  # 4 hours – adjust for app needs

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
        value = var.itar_restricted_countries  # Customize list in vars
      }
    }
    priority = 1  # Higher priority for more rules
  }
}

resource "cloudflare_load_balancer_pool" "app_pool" {
  name = "app-pool"
  origins {
    name    = "app-server-1"
    address = var.proxy_vm_app_server_ips[0]  # Direct to app IP or tunnel endpoint
    enabled = true
    weight  = 1  # Equal weight; adjust for weighted LB
  }
  origins {
    name    = "app-server-2"
    address = var.proxy_vm_app_server_ips[1]
    enabled = true
    weight  = 1
  }
  monitor = cloudflare_load_balancer_monitor.app_monitor.id  # Required for health-based failover
}

resource "cloudflare_load_balancer_monitor" "app_monitor" {
  expected_codes = "2xx, 3xx"  # Customize for app responses
  method         = "GET"  # "HEAD" or "POST" alternatives
  path           = "/health"  # App health endpoint – change if needed
  interval       = 60  # Seconds – lower for faster detection
  timeout        = 5
  retries        = 2  # Retries before marking down
}
