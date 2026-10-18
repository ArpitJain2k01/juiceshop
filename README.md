# Secure Lab: Juice Shop + Wazuh on AWS (Terraform)

One-command, fully automated secure lab:
- **OWASP Juice Shop** on **K3s** (single-node), reachable **only** through a WAF.
- **Wazuh** (server + indexer + dashboard) on a separate VM, with agent-based log
  collection and persistent data.
- **WireGuard** VPN as the only public entry point; Wazuh and admin are private.
- **ModSecurity + OWASP CRS** WAF in front of Juice Shop; direct-origin access is blocked.
- A **verifier** that proves end-to-end log delivery before the deploy is considered successful.
- **CI/CD** gating deploys on Terraform validation, verifier tests, and Trivy/Gitleaks scans.

> Status: **work in progress** — see [Build progress](#build-progress).

## Prerequisites
- AWS account with free-tier/credits, region `TBD`.
- Terraform `>= 1.x`, AWS CLI, a WireGuard client.
- (CI) GitHub repo with OIDC role to AWS; no long-lived keys.

## Commands
```bash
make deploy    # init + apply + run verifier (fails if logs do not reach Wazuh)
make verify    # re-run the log-delivery verifier with a fresh marker
make destroy   # tear down all lab resources
```
_(Targets are placeholders until the matching phase is built.)_

## Architecture
See [docs/architecture.md](docs/architecture.md).

## Estimated cost
See [docs/cost.md](docs/cost.md) — short lab run only; tear down after testing.

## TLS handling
See [docs/tls.md](docs/tls.md).

## Build progress
- [x] Phase 0 — repo scaffold
- [ ] Phase 0 — AWS foundation (VPC/SG/state backend/IAM)
- [ ] Phase 1 — K3s + Juice Shop
- [ ] Phase 2 — WireGuard VPN
- [ ] Phase 3 — ModSecurity + CRS WAF
- [ ] Phase 4 — Wazuh stack + agent + persistence
- [ ] Phase 5 — Verifier (Indexer API)
- [ ] Phase 6 — CI/CD
- [ ] Phase 7 — Hardening + evidence
- [ ] Phase 8 — Interview prep

## AI use
Built with AI assistance (Kiro CLI) for scaffolding, Terraform, and tool integration;
all design decisions reviewed and explainable by the author.

## Incomplete items
_Tracked here as we go._

<!-- CI pipeline test -->
