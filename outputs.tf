# outputs.tf – Post-apply instructions
# Options: Add more for cert details or LB IDs

output "zone_ids" {
  description = "Zone IDs for reference – saved in state"
  value       = { for k, z in cloudflare_zone.this : z.zone => z.id }
}

output "partial_cname_instructions" {
  description = "CNAMEs to add in external DNS"
  value = <<EOT
Add these in current DNS provider:
${join("\n", [
  for r in cloudflare_record.records : 
  format("%s (%s) → %s.cdn.cloudflare.net (proxied)", 
    r.name == "@" ? r.zone_name : "${r.name}.${r.zone_name}",
    r.type,
    r.zone_name
  )
])}
EOT
}

output "cloudflared_deployment_guide" {
  description = "Script for dedicated proxy VMs"
  value = <<EOT
Run on BOTH proxy VMs:

sudo apt update
sudo apt install -y haproxy wget
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -O /tmp/cloudflared.deb
sudo dpkg -i /tmp/cloudflared.deb
sudo cloudflared service install ${nonsensitive(cloudflare_tunnel.app_tunnel.tunnel_token)}
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

EOT
}

output "management_forever" {
  description = "Ongoing instructions"
  value = <<EOT
All managed by Terraform. Edit code → terraform apply to change.
EOT
}
