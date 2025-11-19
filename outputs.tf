output "cname_instructions" {
  value = <<EOT

PARTIAL (CNAME) SETUP – CLIENT ACTION REQUIRED

Add these records in your CURRENT authoritative DNS provider (Route53, GoDaddy, etc.):

${join("\n", [
    for r in cloudflare_record.records : 
    format("%-20s %-8s → %s.%s.cdn.cloudflare.net (proxied)",
      r.hostname == "@" ? r.zone_name : "${r.hostname}.${r.zone_name}",
      r.type,
      r.zone_name,
      r.zone_name
    )
  ])}

Traffic will begin flowing through Cloudflare as soon as those CNAMEs propagate (usually < 5 min).

EOT
}
