output "partial_cname_instructions" {
  value = <<EOT

=== PARTIAL (CNAME) SETUP – ADD THESE IN CURRENT DNS PROVIDER ===

${join("\n", [
  for r in cloudflare_dns_record.records : 
  format("  %-25s %-8s → %s.cdn.cloudflare.net (proxied = yes)",
    r.name == "@" ? r.zone_name : "${r.name}.${r.zone_name}",
    r.type,
    r.zone_name
  )
])}

EOT
}

output "cloudflared_deployment_guide" {
  value = <<EOT

=== DEDICATED CLOUDFLARED HA PAIR (on private DC VMs) ===

Run this on BOTH proxy VMs:

sudo apt update
sudo apt install -y haproxy wget
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -O /tmp/cloudflared.deb
sudo dpkg -i /tmp/cloudflared.deb
sudo cloudflared service install ${nonsensitive(cloudflare_zero_trust_tunnel_cloudflared.app_tunnel.tunnel_token)}
sudo systemctl enable --now cloudflared

sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<EOF
global
    maxconn 4096

defaults
    mode http
    timeout connect 5s
    timeout client 50s
    timeout server 50s

frontend fe_app
    bind *:${var.app_port}
    default_backend be_apps

backend be_apps
    balance roundrobin
    ${join("\n    ", [for ip in var.proxy_vm_app_server_ips : "server app-${index(var.proxy_vm_app_server_ips, ip)+1} ${ip}:${var.app_port} check"])}
EOF

sudo systemctl restart haproxy

Verify: cloudflared tunnel info ${cloudflare_zero_trust_tunnel_cloudflared.app_tunnel.id}

EOT
}
