# Estimated Cost

Rough estimate for a short lab run in `ap-southeast-2`. The lab is designed to be torn
down with `make destroy` after testing, so cost is measured in hours, not months.

## Running resources
| Resource | Spec | Approx. hourly |
|---|---|---|
| App VM (EC2) | `c7i-flex.large` (2 vCPU / 4 GB) | ~$0.09 |
| Wazuh VM (EC2) | `m7i-flex.large` (2 vCPU / 8 GB) | ~$0.12 |
| WireGuard gateway (EC2) | `t3.micro` | ~$0.013 |
| NAT Gateway | 1 (plus data processing) | ~$0.059 + data |
| Elastic IPs | 2 (NAT + WG), in-use | ~$0.005 each |
| EBS | ~110 GB gp3 total (roots + 50 GB Wazuh data) | ~$0.01 |
| CloudWatch Logs | VPC flow logs, low volume | negligible |
| S3 | Terraform state | negligible |

**Approximate total: ~$0.30–0.40 per hour** while running.

## Example run cost
- A few hours of active testing: **well under $2**.
- Covered comfortably by the AWS free-plan credit used for this lab.

## Cost controls applied
- Smallest free-tier-eligible instance types that meet each role's needs.
- Single AZ, single NAT gateway (no HA — not needed for a lab).
- `make destroy` removes everything, including the NAT gateway and EIPs, which are the
  only meaningful idle charges.

## Notes
- The NAT gateway is the largest hourly line item. A cheaper alternative (public subnet +
  strict egress-only SGs, no NAT) was considered; NAT was kept for a cleaner
  private-subnet security posture, accepting the small cost for a short run.
- Instance-type choice was constrained by the account's free-plan policy, which only
  permits free-tier-eligible types.
