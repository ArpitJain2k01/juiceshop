# WAF — ModSecurity + OWASP CRS — Learning Note

Plain-language reference so every WAF choice in this lab is explainable.

## What a WAF is
A **Web Application Firewall** inspects **HTTP traffic** (layer 7 — the actual
requests/responses) and blocks malicious ones.

Compared with the security group already built:
| | Security Group | WAF |
|---|---|---|
| Layer | L3/L4 (IP, port) | L7 (URL, headers, body, cookies) |
| Knows | *who* is connecting (IP) and *where* (port) | *what* the request contains |
| Example | "allow TCP 443 from the VPN" | "this looks like SQL injection → block" |

They are complementary: the SG stops unknown *sources*; the WAF stops malicious
*content* from allowed sources.

## The two pieces: engine + rules
- **ModSecurity** = the **engine**. Hooks into a web server/proxy and gives it the
  ability to inspect requests against rules. Ships with almost no rules on its own — it
  is just the machinery.
- **OWASP CRS (Core Rule Set)** = the **rules**. Community-maintained signatures for the
  OWASP Top 10: SQLi, XSS, path traversal, RCE, scanner probes, etc. This is the actual
  "knowledge" of what an attack looks like.

Analogy: ModSecurity is the antivirus *program*; CRS is the *virus definitions*. You need
both. We use the ready-made `owasp/modsecurity-crs` image (nginx + ModSecurity + CRS)
rather than assembling it by hand.

## Where it sits (reverse proxy)
The WAF runs as a **reverse proxy** in front of Juice Shop:

```
VPN user ──HTTPS──▶ [ WAF: nginx + ModSecurity + CRS ] ──▶ Juice Shop (ClusterIP:3000)
                         │ inspects every request
                         ├─ clean  → forward to Juice Shop, return its response
                         └─ attack → return 403, Juice Shop never sees it
```

Reverse proxy = it receives the client request and, if allowed, makes the request *to*
Juice Shop on the client's behalf, then relays the response. Juice Shop only ever talks
to the WAF, never directly to the client.

## How a request is evaluated (CRS anomaly scoring)
CRS does not block on a single rule by default. It uses **anomaly scoring**:
1. Each matching rule **adds points** (e.g. a critical SQLi pattern = +5).
2. If the total score ≥ the **threshold** (default inbound 5), the request is blocked (403).
3. This reduces false positives — one weak signal alone will not block; a real attack
   trips multiple/high-score rules.

**Paranoia Level (PL 1–4):** how aggressive CRS is. PL1 (default) catches obvious attacks
with few false positives; PL4 is very strict with more false positives. The lab uses PL1
for reliable, deterministic blocks.

## Detection vs Blocking mode (`SecRuleEngine`)
- **DetectionOnly** — logs what it *would* block but lets everything through. Used first,
  to find false positives on legitimate traffic before enforcing.
- **On** (blocking) — actually returns 403 on attacks.

Proper rollout: deploy DetectionOnly → review logs → tune → switch to blocking. The lab
goes straight to blocking (it is a controlled demo), but the rollout order is the correct
production answer.

## What satisfies the assignment
- **Allowed request:** `GET /` → nothing malicious → proxied to Juice Shop → **200**.
- **Deterministic blocked request:** an obvious attack payload → CRS score over threshold
  → **403**, Juice Shop never sees it. Examples that reliably trip high-score rules:
  - `GET /?id=1' OR '1'='1` (SQLi)
  - `GET /../../etc/passwd` (path traversal)
- **No direct-origin bypass:** Juice Shop is ClusterIP with no public IP and no SG opening
  its port, so the WAF is the only path to it.

## Deployment choice
- **In-cluster (chosen):** run `owasp/modsecurity-crs` as a Deployment in K3s; it becomes
  the entry the VPN user hits; Juice Shop stays ClusterIP behind it.
- Alternative: WAF container on the host via docker. In-cluster keeps everything in
  Kubernetes and is cleaner.

TLS terminates at the WAF (self-signed cert for the private lab): VPN user hits
`https://<app>` → WAF → `http://juice-shop:3000` internally. The WAF can only inspect
HTTPS because TLS terminates there.

## Why ModSecurity + CRS and not a managed WAF
- **AWS WAF** needs an ALB/CloudFront + public endpoint + a domain + ongoing cost. This
  is a private lab with no public domain.
- **Cloudflare WAF** needs a domain you control and (for private access) an enrolled
  WARP client.
- **ModSecurity + CRS** is free, runs anywhere, is fully expressed in IaC, and gives
  deterministic open-source rules — the right fit for a private, cheap, reproducible lab.

## Likely cross-questions
- **WAF vs security group?** Different layers — L7 content vs L3/4 IP/port. Need both.
- **Why not AWS/Cloudflare WAF?** No public domain/endpoint; cost; this lab is private
  and must be fully in IaC. See section above.
- **How is bypass prevented?** ClusterIP + no SG for the app port + no public IP → the WAF
  is the only route to Juice Shop.
- **False positives?** DetectionOnly first, tune, then enforce; anomaly scoring and
  paranoia levels manage it.
- **What does a WAF NOT protect?** Logic flaws, auth/business-logic abuse (Juice Shop has
  many). A WAF catches known *patterns*, not everything — defense in depth still needed.
- **Does it see HTTPS?** Only because TLS terminates at the WAF. End-to-end encrypted
  traffic past the WAF would be opaque to it.
