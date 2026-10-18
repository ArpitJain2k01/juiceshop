# TLS Handling

This is a private lab with no public domain, so TLS is handled with self-signed
certificates and the trust model is scoped accordingly.

## What is encrypted today
| Channel | TLS? | Notes |
|---|---|---|
| Evaluator ↔ WireGuard gateway | Yes (VPN) | WireGuard encrypts the whole tunnel (ChaCha20-Poly1305). All traffic to the private subnet rides inside it. |
| Wazuh indexer API (9200) | Yes | The indexer serves HTTPS with Wazuh's self-signed certs; the verifier connects over TLS (cert verification disabled for the self-signed lab cert, over a private VPN path). |
| Wazuh dashboard (443) | Yes | Self-signed; accessed only over the VPN. |
| Wazuh agent ↔ manager (1514/1515) | Yes | Wazuh encrypts agent traffic with its own keys. |
| Terraform state (S3) | Yes | Enforced in transit; bucket is encrypted at rest and versioned. |
| EBS volumes | n/a (at rest) | All volumes encrypted. |

## WAF / Juice Shop path
The WAF currently serves **HTTP** on its NodePort behind the VPN. Because the only way to
reach it is through the WireGuard tunnel (which is itself encrypted end to end), traffic
is never in cleartext on the public internet. The internal hop WAF → Juice Shop is
localhost-to-ClusterIP inside the node.

## Planned hardening: self-signed TLS at the WAF
The next step is to terminate HTTPS at the WAF with a self-signed certificate (and CA)
generated at deploy time, so the evaluator connects to `https://` even inside the VPN.
This is deferred because the assignment's core WAF requirement (deterministic allow/block)
is already met over the VPN-encrypted path; adding WAF TLS is a defense-in-depth
improvement, not a functional gap.

## Why self-signed (not a public CA)
There is no public domain in this private lab, so a public CA (Let's Encrypt etc.) cannot
issue a certificate. Self-signed certs over a private VPN are the correct, standard choice
for a closed lab. In production with a real domain, these would be replaced by
ACM/Let's Encrypt certificates and TLS would terminate at a public, WAF-protected endpoint.

## Secrets and keys
- WireGuard server private key is generated on the gateway instance and never leaves it.
- The WireGuard client private key stays on the operator's machine.
- Neither private key, nor Terraform state, nor tfvars are ever committed (git-ignored +
  Gitleaks in CI).
