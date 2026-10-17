# Architecture

Security-first lab: OWASP Juice Shop behind a WAF, monitored by Wazuh, reachable only
through a WireGuard VPN. One cloud (AWS), one region (`ap-southeast-2`).

## Why ap-southeast-2 only
The AWS account is a member of an Organization whose free-plan Service Control Policy
denies EC2 in every region **except `ap-southeast-2`**. We cannot change the SCP (it is
enforced from the management account), so the entire lab is built in `ap-southeast-2`.
This is documented here because an evaluator will ask why Sydney.

## Topology

```
                         Internet
                            │
                   UDP 51820 (evaluator IP only)
                            │
                   ┌────────▼─────────┐
   PUBLIC subnet   │  WireGuard GW    │  <- only instance with a public IP (explicit EIP)
   10.20.0.0/24    │  (bastion/VPN)   │
                   └────────┬─────────┘
                            │ VPN tunnel (private routing)
          ┌─────────────────┼───────────────────┐
          │                 │                    │
  ┌───────▼────────┐  ┌─────▼─────────┐    (admin access to
  │  App VM        │  │  Wazuh VM     │     Wazuh dashboard &
  │  K3s + WAF     │  │  server +     │     SSH only via VPN)
  │  (ModSecurity) │  │  indexer +    │
  │   └─ Juice Shop│  │  dashboard    │
  │     ClusterIP  │  └───────────────┘
  └────────────────┘
   PRIVATE subnet 10.20.1.0/24  (no public IPs; egress via NAT)

  NAT GW (in public subnet) ── IGW ── Internet   (outbound only for private subnet)
  VPC Flow Logs ── CloudWatch Logs                (network audit trail)
```

## Trust boundaries and key decisions

| Decision | Choice | Why |
|---|---|---|
| Public entry point | **WireGuard only** | Single, auditable ingress; everything else private |
| Workload placement | **Private subnet, no public IP** | Workloads unreachable from the internet |
| Private egress | **NAT Gateway** | Pull images/packages without inbound exposure |
| Public IP assignment | `map_public_ip_on_launch = false` everywhere | No instance gets a public IP by accident; WG gets a deliberate EIP |
| Juice Shop exposure | **ClusterIP only, no NodePort** | No SG anywhere opens its port → direct-origin bypass impossible |
| WAF | **ModSecurity + OWASP CRS** reverse proxy in front of Juice Shop | Open-source, deterministic allow/block, no public domain needed |
| Admin / SSH | **Over VPN (and/or SSM Session Manager)** | Port 22 is never open to the internet |
| Network audit | **VPC Flow Logs → CloudWatch** | Security lab should log traffic; evidence for review |
| Egress | NAT + IGW | Private subnet has no inbound route from the internet |

## Direct-origin bypass prevention
Juice Shop runs as a Kubernetes **ClusterIP** service — not NodePort, not LoadBalancer.
The only thing that can reach it is the in-cluster WAF (ModSecurity + CRS). No security
group anywhere opens the Juice Shop port, and the app VM has no public IP. The only path
from an evaluator to the app is: **VPN → WAF → Juice Shop**. There is no second path.

## Cost posture
NAT Gateway, 2 EIPs, and flow logs add a small hourly cost (~a few dollars for a short
run). We accept this for defensibility and tear everything down with `make destroy`
after testing. Running estimate: see [cost.md](cost.md).

## TLS
Self-signed CA generated at deploy time (no public domain in a private lab). See
[tls.md](tls.md). Details filled in as the WAF and Wazuh phases land.

## Status
- [x] Phase 0 — network (VPC, subnets, IGW, NAT, routes, flow logs)
- [ ] Phase 0 — security groups, IAM instance roles, outputs
- [ ] Phase 1 — K3s + Juice Shop
- [ ] Phase 2 — WireGuard
- [ ] Phase 3 — WAF
- [ ] Phase 4 — Wazuh
- [ ] Phase 5 — Verifier
- [ ] Phase 6 — CI/CD
- [ ] Phase 7 — Hardening + evidence
