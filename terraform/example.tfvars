# Template for terraform.tfvars. Copy to terraform.tfvars and fill in real values.
# terraform.tfvars is git-ignored; this example file is safe to commit.

# Your public IP as a /32 (find it: curl -s checkip.amazonaws.com)
evaluator_cidr = "203.0.113.5/32"

# Your WireGuard CLIENT public key (public half only).
# Generate locally:
#   umask 077
#   wg genkey | tee ~/.wg/juiceshop-client.key | wg pubkey > ~/.wg/juiceshop-client.pub
#   cat ~/.wg/juiceshop-client.pub
wg_client_public_key = "REPLACE_WITH_YOUR_CLIENT_PUBLIC_KEY="
