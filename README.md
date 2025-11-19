# Cloudflare Enterprise – Partial (CNAME) Log-First Template

Perfect for clients who **do NOT want to change nameservers**.

Features:
- 100% Terraform-driven onboarding
- Starts in full LOG mode → zero risk
- One-word changes to go live
- Clear CNAME instructions in output

Usage:
```bash
terraform init
terraform plan
terraform apply
→ Copy the CNAMEs from output and add them in current DNS provider
