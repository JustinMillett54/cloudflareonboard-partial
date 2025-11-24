output "partial_cname_instructions" {
  value = <<EOT
=== PARTIAL (CNAME) SETUP – ADD THESE IN CURRENT DNS PROVIDER ===
${join("\n", [
  for r in cloudflare_dns_record.records :
  format(" %-25s %-8s → %s.cdn.cloudflare.net (proxied = yes)",
    r.name == "@" ? r.zone_name : "${r.name}.${r.zone_name}",
    r.type,
    r.zone_name
  )
])}
EOT
}

output "cloudflared_deployment_guide" {
  value = var.enable_tunnel ? <<EOT
=== DEDICATED CLOUDFLARED HA PAIR (on private DC VMs) ===

Run this on BOTH proxy VMs:

sudo apt update
sudo apt install -y haproxy wget
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -O /tmp/cloudflared.deb
sudo dpkg -i /tmp/cloudflared.deb

# Install tunnel with credentials
sudo cloudflared service install --credentials-file /root/.cloudflared/${cloudflare_zero_trust_tunnel_cloudflared.app_tunnel.id}.json

# Create config file
sudo tee /etc/cloudflared/config.yml > /dev/null <<CFEOF
tunnel: ${cloudflare_zero_trust_tunnel_cloudflared.app_tunnel.id}
credentials-file: /root/.cloudflared/${cloudflare_zero_trust_tunnel_cloudflared.app_tunnel.id}.json

ingress:
  - hostname: ${var.tunnel_public_hostname}
    service: http://localhost:${var.app_port}
  - service: http_status:404
CFEOF

# Configure HAProxy for load balancing
sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<HPEOF
global
    maxconn 4096

defaults
    mode http
    timeout connect 5s
    timeout client  50s
    timeout server  50s

frontend fe_app
    bind *:${var.app_port}
    default_backend be_apps

backend be_apps
    balance roundrobin
${join("\n    ", [for ip in var.proxy_vm_app_server_ips : "server app-${index(var.proxy_vm_app_server_ips, ip)+1} ${ip}:${var.app_port} check"])}
HPEOF

sudo systemctl restart haproxy
sudo systemctl start cloudflared

# Verify tunnel is running
sudo cloudflared tunnel info ${cloudflare_zero_trust_tunnel_cloudflared.app_tunnel.id}
EOT : "Tunnel disabled - set enable_tunnel = true to generate deployment guide"
}

output "tunnel_info" {
  value = var.enable_tunnel ? {
    tunnel_id   = cloudflare_zero_trust_tunnel_cloudflared.app_tunnel.id
    tunnel_name = cloudflare_zero_trust_tunnel_cloudflared.app_tunnel.name
    cname_target = "${cloudflare_zero_trust_tunnel_cloudflared.app_tunnel.id}.cfargotunnel.com"
  } : null
  description = "Tunnel connection details"
}
