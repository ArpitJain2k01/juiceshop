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

## Compute: App VM (K3s + Juice Shop)

The application tier is a single Ubuntu 24.04 EC2 instance in the **private subnet**.

| Aspect | Choice | Why |
|---|---|---|
| Kubernetes | **K3s** (single-node) | Lightweight, single-binary K8s; fits a 2-VM budget without a managed control plane |
| App deploy | Juice Shop as a **ClusterIP** Service | Not NodePort/LoadBalancer → unreachable from outside the node; only the in-cluster WAF reaches it |
| Image | pinned `bkimminich/juice-shop:v19.0.0` | Reproducible; never `:latest` |
| Provisioning | cloud-init (`user_data`) installs K3s + applies manifests on boot | "One command, no manual server setup" |
| Root disk | gp3, **encrypted** | Data-at-rest encryption |
| Metadata | **IMDSv2 required** (`http_tokens = "required"`) | Juice Shop is deliberately SSRF-vulnerable; IMDSv2 blocks metadata-credential theft |
| Pod security | non-root, drop ALL caps, no privilege escalation | Pod hardening by default even on an intentionally vulnerable app |

> Note: Juice Shop may not start cleanly as non-root. If the pod crash-loops on first
> apply, `runAsNonRoot` is relaxed and the reason documented — the ClusterIP exposure
> control is unaffected.

### Why ClusterIP matters (bypass prevention)
Port 3000 is published only inside the cluster. No Kubernetes Service exposes it to the
node's network, no security group opens it, and the VM has no public IP. The only route
to Juice Shop is: VPN → WG gateway → WAF (Phase 3) → ClusterIP. There is no second path.

## VPN: WireGuard gateway

The only public entry point. A `t3.micro` in the **public subnet** with an explicit EIP.

| Aspect | Choice | Why |
|---|---|---|
| VPN | **WireGuard** | Small, kernel-level, key-pair auth; see docs/learning/wireguard.md |
| Keys | **server keypair generated on the instance** (cloud-init) | Server private key never enters Terraform state or git |
| Client key | supplied as `wg_client_public_key` (public only) | Private half stays on the operator's laptop |
| Pubkey retrieval | server public key copied to `/home/ubuntu/wg-server-public.key`, read over SSH | No extra IAM; no secret in state |
| Routing | `source_dest_check = false` + IP forwarding + iptables MASQUERADE | Gateway forwards tunnel traffic into the private subnet |
| Public IP | explicit `aws_eip` | Single, known, deliberate entry point |

### Connect flow (operator)
1. `ssh ubuntu@<wireguard_public_ip>` and `cat wg-server-public.key`.
2. Build local `~/.wg/juiceshop.conf` with the client private key, server public key,
   `Endpoint = <wireguard_public_ip>:51820`, `AllowedIPs = 10.20.0.0/16, 10.8.0.0/24`.
3. `wg-quick up ./juiceshop.conf` → laptop can now reach the private App/Wazuh VMs.

## WAF: ModSecurity + OWASP CRS

An in-cluster reverse proxy (`owasp/modsecurity-crs:4.25.2-nginx-alpine-lts`) sits in
front of Juice Shop. See docs/learning/waf.md.

| Aspect | Choice | Why |
|---|---|---|
| Engine + rules | ModSecurity + OWASP CRS (bundled nginx image) | Open-source, deterministic, fully in IaC, no public domain |
| Placement | Deployment in K3s, `NodePort 30443` | WAF is the entry; Juice Shop stays ClusterIP behind it |
| Backend | `BACKEND=http://juice-shop:3000` | WAF proxies to Juice Shop's internal Service |
| Mode | `MODSEC_RULE_ENGINE=On`, `PARANOIA=1`, `ANOMALY_INBOUND=5` | Blocking, deterministic |
| Reachability | SG allows 30443 only from the WireGuard SG | VPN users only; still no public exposure |
| TLS | HTTP for now; self-signed TLS added in hardening pass | Prove allow/block first (documented) |

### Verified allow/block (live)
```
GET /                      → 200  (clean, proxied to Juice Shop)
GET /?id=1' OR '1'='1      → 403  (SQLi blocked by CRS)
GET /?file=../../etc/passwd → 403  (path traversal blocked by CRS)
```
Juice Shop never receives the blocked requests. Its own port 3000 remains ClusterIP, so
the WAF (NodePort 30443, VPN-only) is the single front door — no direct-origin bypass.

## Status
- [x] Phase 0 — network (VPC, subnets, IGW, NAT, routes, flow logs)
- [x] Phase 0 — security groups, IAM instance roles, keypair, outputs
- [x] Phase 1 — K3s + Juice Shop (App VM, cloud-init, ClusterIP)
- [x] Phase 2 — WireGuard (gateway, EIP, on-instance keygen, NAT forwarding)
- [x] Phase 3 — WAF (ModSecurity + CRS, NodePort, VPN-only, allow/block verified)
- [x] Phase 4a — Wazuh stack (manager + indexer + dashboard, persistent EBS volume)
- [x] Phase 4b — Wazuh agent on app VM, enrolled, collecting WAF + Juice Shop logs
- [x] Phase 4c — custom Wazuh rule indexes verifier markers (clean + attack)
- [x] Phase 5 — Verifier (readiness + allow/block + marker log-delivery via Indexer API; gates make deploy)
- [x] Phase 6 — CI/CD (validate + Trivy + Gitleaks + verifier; gated self-hosted deploy)
- [ ] Phase 7 — Hardening + evidence
