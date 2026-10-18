# Template for terraform.tfvars. Copy to terraform.tfvars and fill in real values.
# terraform.tfvars is git-ignored; this example file is safe to commit.

# --- VPN allowlist ---
# evaluator_cidr is OPTIONAL. Leave it empty (or omit) to AUTO-DETECT the public IP
# of whoever runs `terraform apply` and allowlist just that /32. Set it explicitly
# only if you want to pin a specific IP instead of the deployer's.
#   evaluator_cidr = "203.0.113.5/32"

# Allowlist additional IPs (e.g. a separate evaluator while you deploy from elsewhere).
#   extra_allowed_cidrs = ["198.51.100.7/32"]

# --- WireGuard client public key (public half only) ---
# Generate locally:
#   umask 077
#   wg genkey | tee ~/.wg/juiceshop-client.key | wg pubkey > ~/.wg/juiceshop-client.pub
#   cat ~/.wg/juiceshop-client.pub
wg_client_public_key = "REPLACE_WITH_YOUR_CLIENT_PUBLIC_KEY="
