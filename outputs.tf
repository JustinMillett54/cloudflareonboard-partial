# outputs.tf – PARTIAL / CNAME SETUP
output "zone_ids" {
  description = "Cloudflare Zone IDs – saved forever in Terraform state"
  value       = { for k, z in cloudflare_zone.this : z.zone => z.id }
}

output "partial_cname_instructions" {
  description = "Exact records the client MUST add in their current authoritative DNS provider"
  value = <<EOT

=== PARTIAL (CNAME) SETUP – CLIENT ACTION REQUIRED ===

Add these records in your CURRENT DNS provider (Route53, GoDaddy, etc.):

${join("\n", [
  for r in cloudflare_record.records : 
  format("  %-25s %-8s → %s.cdn.cloudflare.net (proxied = yes)",
    r.hostname == "@" ? r.zone_name : "${r.hostname}.${r.zone_name}",
    r.type,
    r.zone_name
  )
])}

As soon as these propagate (usually < 5 min), all traffic flows through Cloudflare WAF, Bot Management, Rate Limiting, etc.

EOT
}

output "management_forever" {
  value = <<EOT

=== CLOUDFLARE IS NOW 100% MANAGED BY TERRAFORM ===

Zone IDs (above) are saved forever – never look them up again.

From now on, any change = edit code → terraform apply
Examples:
  • Add new proxied subdomain
  • Turn LOG → BLOCK on WAF / Rate Limiting
  • Disable a noisy Managed Rule
  • Adjust Bot Management, SSL, etc.

No nameserver change ever needed.

EOT
}
