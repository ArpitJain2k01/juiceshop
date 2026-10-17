# WireGuard — Learning Note

Plain-language reference so every WireGuard choice in this lab is explainable.

## What it is
A **VPN**: software that builds an encrypted private tunnel between two machines over
the public internet. Once connected, your laptop behaves as if it is *inside* the AWS
private network. WireGuard is the modern choice — tiny codebase, fast (runs in the Linux
kernel), and its config is only a few lines.

## Terminology: which "gateway"?
In the WireGuard context, **"WG gateway"** always means the small **EC2 instance in the
public subnet running the WireGuard server** — the VPN entry point the evaluator connects
to. Do not confuse it with the two AWS VPC gateways:

| Name | What it is | Role |
|---|---|---|
| **WG gateway** | our EC2 VM running WireGuard | VPN entry point; evaluator connects here |
| **Internet Gateway (IGW)** | AWS VPC component | public subnet ↔ internet |
| **NAT Gateway** | AWS VPC component | private VMs' **outbound-only** internet |

When we say "the WG gateway forwards your traffic into the VPC", the forwarding is done
by the **WireGuard EC2 instance**. The IGW/NAT are the plumbing underneath.

## What is the "evaluator IP"?
The **public IP address of whoever is testing the lab** (recruiter/evaluator, or you
during testing). The assignment requires restricting the lab to "VPN users or an
evaluator IP allowlist".

- It is their internet-facing IP as seen by the world, e.g. `203.0.113.5`.
- Find yours with `curl ifconfig.me` or `curl checkip.amazonaws.com`.
- Stored in `var.evaluator_cidr` as a `/32` (exactly one IP) in `terraform.tfvars`
  (git-ignored). Never hardcoded.
- It is the **only** IP allowed to send the WireGuard handshake (the `sg-wireguard`
  ingress rule).

If the evaluator IP is unknown or changes, either ask them for it or temporarily widen
`evaluator_cidr` for their test window — a documented trade-off, not a silent `0.0.0.0/0`.

## The core idea: public/private key pairs
Each peer (your laptop, the WG gateway) has a **key pair**:
- **Private key** — secret, never leaves the machine, never committed to git.
- **Public key** — shared with the other side.

Each side's config lists the *other* side's **public key** plus the IPs that peer may
use. Traffic is encrypted so only the holder of the matching private key can decrypt it.
No passwords, no certificates — just key pairs. (This is why we generate keys at deploy
time and never commit the private keys.)

## How a connection happens (the handshake)
1. Laptop knows the WG gateway's **public key** and `publicIP:51820`.
2. Laptop sends a handshake packet to that `IP:51820` over **UDP**.
3. Gateway checks the sender's public key against its known peers; if recognised, the
   tunnel is established.
4. Both sides then exchange encrypted UDP packets on port 51820.

Facts that drive the security group design:
- WireGuard is **UDP**, not TCP.
- It listens on **one port**, conventionally **51820**.
- The **client initiates**; the gateway only needs that one inbound UDP port.

## What "being on the VPN" gives you
Each peer gets a VPN-internal IP (gateway `10.8.0.1`, laptop `10.8.0.2`). The gateway
forwards tunnel traffic into the AWS VPC (`10.20.0.0/16`), so the laptop can reach the
private VMs (`10.20.1.x`) even though they have **no public IP**.

```
Laptop (10.8.0.2) ──encrypted UDP──▶ WG gateway publicIP:51820 (10.8.0.1)
                                           │ forwards into VPC
                                           ▼
                               Private subnet 10.20.1.0/24
                               ├── App VM (WAF → Juice Shop)
                               └── Wazuh VM (dashboard, indexer)
```

## How this maps to our security groups
1. **`sg-wireguard` ingress — UDP 51820 from `evaluator_cidr` only.** The only
   internet-facing rule in the lab. UDP + 51820 because that is WireGuard; locked to the
   evaluator IP so only they can attempt the handshake. This is the front door.
2. **App & Wazuh ingress — `referenced_security_group_id = sg-wireguard`.** Once on the
   tunnel, traffic is forwarded by the gateway, so to the private VMs it appears to come
   *from the WG instance*. Allowing 443/22 only from the WG SG means "accept only if it
   arrived through the VPN". No tunnel → no WG SG → dropped. This is why we reference the
   SG, not the raw evaluator IP.
3. **App VM has no public IP.** Even knowing its private IP, there is no internet route
   to it. Only path in: VPN → gateway → WG SG → app SG → WAF → Juice Shop. Single path,
   no bypass.

### The chain in one line
`Evaluator IP → (UDP 51820, sg-wireguard) → tunnel → WG gateway forwards → (sg-app / sg-wazuh accept only from sg-wireguard) → WAF → Juice Shop`

## Why WireGuard over OpenVPN
| Factor | WireGuard | OpenVPN | Why it matters here |
|---|---|---|---|
| Codebase size | ~4,000 lines | ~100,000+ lines | Smaller = less attack surface (the headline for a security lab) |
| Speed | Faster (kernel) | Slower (userspace) | Lower latency |
| Config | A few lines, key-pair | Certs/CA/config, more parts | Easier to automate cleanly |
| Protocol | UDP only | UDP or TCP | Simpler SG (one UDP rule) |
| Setup time | Minutes | Longer (PKI) | Fits the timebox |
| Auditability | Simple | More complex | Easier to defend |

One-liner: *"WireGuard has a tiny, auditable codebase, runs in the kernel for speed, and
uses simple key-pair auth — less attack surface and far easier to automate than
OpenVPN's certificate-based setup. For a small secure lab, that simplicity is itself a
security advantage."*

## Likely cross-questions
- **Why UDP not TCP?** WireGuard is UDP-only by design; lower overhead, avoids TCP-in-TCP.
- **Why reference the WG SG instead of the client IP in the app SG?** The app is private;
  traffic arrives *from the gateway*, so the gateway's SG is the correct source. Also
  decouples from the client's changing IP.
- **What stops someone with the gateway's public IP from connecting?** They must be a
  configured peer (their public key in the gateway config) **and** come from the
  allowlisted evaluator IP. Two gates: network (SG) + crypto (key).
- **WireGuard vs OpenVPN?** See table above.
