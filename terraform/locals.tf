data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  # If evaluator_cidr is set, use it; otherwise auto-detect the deployer's public IP.
  resolved_evaluator_cidr = var.evaluator_cidr != "" ? var.evaluator_cidr : "${chomp(data.http.my_ip.response_body)}/32"

  # Final allowlist = the resolved CIDR + any extra CIDRs, de-duplicated.
  vpn_allowed_cidrs = distinct(concat([local.resolved_evaluator_cidr], var.extra_allowed_cidrs))
}