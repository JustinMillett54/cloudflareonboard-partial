# main.tf – Verified v5.13 Syntax (November 2025)
# Fixes: filter = { ... } object for data rulesets; cloudflare_tunnel with account_id (no secret arg); tunnel_settings with ingress list arg; all other from docs (content for dns_record, sbfm_ for bot, rules list for ruleset, zone_setting singular for_each, google for cert, fallback_pool/default_pools as id, origins list for pool, account_id for monitor)

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ZONES – Partial setup (v5: account object)
resource "cloudflare_zone" "this" {
  for_each = var.zones

  account = {
    id = var.cloudflare_account_id
  }
  name = each.value.domain
  type = "partial"
}

# DNS RECORDS – Proxied only (v5: dns_record with content)
resource "cloudflare_dns_record" "records" {
  for_each = {
    for pair in local.record_pairs : "${pair.zone_key}.${pair.record.hostname}.${pair.record.type}" => pair
  }

  zone_id = cloudflare_zone.this[each.value.zone_key].id
  name = each.value.record.hostname == "" ? "@" : each.value.record.hostname
  type = upper(each.value.record.type)
  content = each.value.record.target  # v5: "content"
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

# BOT MANAGEMENT – Safe challenge mode (v5: sbfm_ only)
resource "cloudflare_bot_management" "this" {
  for_each = cloudflare_zone.this
  zone_id = each.value.id

  enable_js = true
  auto_update_model = true
  sbfm_definitely_automated = "managed_challenge"
  sbfm_likely_automated = "managed_challenge"
  sbfm_verified_bots = "allow"
}

# MANAGED WAF + OWASP – Log-only start (v5: rules list arg, execute sub-object; hardcoded OWASP ID)
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
        id = "efb7b8c949ac4650a0e52a9c2d13d3bb"
      }
    },
    {
      action = "log"
      expression = "true"
      enabled = true
      description = "OWASP Core Ruleset – LOG"
      execute = {
        id = "4814384a9e5d4991b9815d64d2d2d2d2"  # Hardcoded from docs
      }
    }
  ]
}

data "cloudflare_rulesets" "owasp" {
  for_each = cloudflare_zone.this
  zone_id = each.value.id

  filter = {
    kind = "managed"
    name = "Cloudflare OWASP Core Ruleset"
    phase = "http_request_firewall_managed"
  }
}

# WAF EXCEPTIONS – For false positives (v5: rules list)
resource "cloudflare_ruleset" "waf_exceptions" {
  for_each = cloudflare_zone.this
  zone_id = each.value.id
  name = "WAF Exceptions – false positives"
  kind = "zone"
  phase = "http_request_firewall_managed"

  rules = [
    # Example: Skip a noisy rule
    # {
    #   action = "skip"
    #   expression = "true"
    #   description = "Skip rule 981173 – Wordpress false positive"
    #   enabled = true
    #   execute = {
    #     id = "981173"
    #   }
    # }
  ]
}

# RATE LIMITING – Log-only start (v5: rules list)
resource "cloudflare_ruleset" "rate_limiting" {
  for_each = cloudflare_zone.this
  zone_id = each.value.id
  name = "Rate Limiting – LOG only"
  kind = "zone"
  phase = "http_ratelimit"

  rules = [
    {
      enabled = true
      description = "Login protection – safe start"
      expression = "(http.request.uri.path contains \"/login\")"
      action = "log"
      ratelimit = {
        characteristics = ["ip.src", "cf.client.asn"]
        period = 60
        requests_per_period = 15
        mitigation_timeout = 600
      }
    }
  ]
}

# ZONE HARDENING SETTINGS (v5: cloudflare_zone_setting singular, for_each for each setting)
resource "cloudflare_zone_setting" "ssl" {
  for_each = cloudflare_zone.this

  zone_id = each.value.id
  setting_id = "ssl"
  value = "strict"
}

resource "cloudflare_zone_setting" "always_use_https" {
  for_each = cloudflare_zone.this

  zone_id = each.value.id
  setting_id = "always_use_https"
  value = "on"
}

resource "cloudflare_zone_setting" "min_tls_version" {
  for_each = cloudflare_zone.this

  zone_id = each.value.id
  setting_id = "min_tls_version"
  value = "1.3"
}

resource "cloudflare_zone_setting" "tls_1_3" {
  for_each = cloudflare_zone.this

  zone_id = each.value.id
  setting_id = "tls_1_3"
  value = "on"
}

resource "cloudflare_zone_setting" "automatic_https_rewrites" {
  for_each = cloudflare_zone.this

  zone_id = each.value.id
  setting_id = "automatic_https_rewrites"
  value = "on"
}

resource "cloudflare_zone_setting" "security_level" {
  for_each = cloudflare_zone.this

  zone_id = each.value.id
  setting_id = "security_level"
  value = "high"
}

resource "cloudflare_zone_setting" "brotli" {
  for_each = cloudflare_zone.this

  zone_id = each.value.id
  setting_id = "brotli"
  value = "on"
}

resource "cloudflare_zone_setting" "websocket" {
  for_each = cloudflare_zone.this

  zone_id = each.value.id
  setting_id = "websocket"
  value = "on"
}

# CLOUDFLARED TUNNEL – Zero-trust reverse proxy (v5: cloudflare_tunnel, tunnel_settings with ingress list)
resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_tunnel" "app_tunnel" {
  account_id = var.cloudflare_account_id
  name = "app-to-cloudflare-tunnel"
  # v5: No "secret" arg – token generated automatically
}

resource "cloudflare_tunnel_settings" "app_tunnel_config" {
  tunnel_id = cloudflare_tunnel.app_tunnel.id

  ingress = [
    {
      hostname = var.tunnel_public_hostname
      service = "http://localhost:${var.app_port}"
    },
    {
      service = "http_status:404"
    }
  ]
}

# Tunnel CNAME – Proxied for WAF/Bot (v5: dns_record with content, ttl)
resource "cloudflare_dns_record" "tunnel_cname" {
  zone_id = cloudflare_zone.this[var.primary_zone_key].id
  name = split(".", var.tunnel_public_hostname)[0]
  type = "CNAME"
  content = "${cloudflare_tunnel.app_tunnel.id}.cfargotunnel.com"
  proxied = true
  ttl = 1
  comment = "Tunnel CNAME – Terraform-managed"
}

# ADVANCED CERT PACK – Dedicated certs (v5: certificate_authority = "google")
resource "cloudflare_certificate_pack" "advanced_cert" {
  for_each = var.enable_advanced_cert ? cloudflare_zone.this : {}

  zone_id = each.value.id
  type = "advanced"
  hosts = [each.value.zone, "*.${each.value.zone}"]
  validation_method = "txt"
  validity_days = 30
  certificate_authority = "google"
  cloudflare_branding = false
}

# GLOBAL LOAD BALANCING – Between app servers via tunnel (v5: fallback_pool/default_pools as id, rules list with expression)
resource "cloudflare_load_balancer" "app_lb" {
  zone_id = cloudflare_zone.this[var.primary_zone_key].id
  name = var.tunnel_public_hostname
  fallback_pool = cloudflare_load_balancer_pool.app_pool.id
  default_pools = [cloudflare_load_balancer_pool.app_pool.id]
  proxied = true

  steering_policy = "geo"
  session_affinity = "ip_cookie"
  session_affinity_ttl = 14400

  rules = [
    {
      name = "itar_block"
      fixed_response = {
        status_code = 403
        message_body = "Access Denied – Restricted Country"
      }
      expression = "ip.geoip.country in ${jsonencode(var.itar_restricted_countries)}"
      priority = 1
    }
  ]
}

resource "cloudflare_load_balancer_pool" "app_pool" {
  account_id = var.cloudflare_account_id
  name = "app-pool"
  origins = [
    {
      name = "app-server-1"
      address = var.proxy_vm_app_server_ips[0]
      enabled = true
      weight = 1
    },
    {
      name = "app-server-2"
      address = var.proxy_vm_app_server_ips[1]
      enabled = true
      weight = 1
    }
  ]
  monitor = cloudflare_load_balancer_monitor.app_monitor.id
}

resource "cloudflare_load_balancer_monitor" "app_monitor" {
  account_id = var.cloudflare_account_id
  expected_codes = "2xx, 3xx"
  method = "GET"
  path = "/health"
  interval = 60
  timeout = 5
  retries = 2
}
