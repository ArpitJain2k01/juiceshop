# Secure Lab: OWASP Juice Shop + Wazuh on AWS (Terraform)

A fully automated, security-first lab that brings up OWASP Juice Shop behind a Web
Application Firewall, monitored by Wazuh, reachable only through a WireGuard VPN — with a
verifier that proves end-to-end log delivery before a deployment is considered successful.

Everything is Terraform-driven and reproducible: after credentials and variables are
supplied, the whole environment comes up with a single documented command.

## What this demonstrates
- **Application**: OWASP Juice Shop on single-node **K3s**, exposed only as a ClusterIP.
- **WAF**: **ModSecurity + OWASP CRS** reverse proxy in front of Juice Shop — one allowed
  request (200), deterministic blocked requests (403), and no direct-origin bypass.
- **VPN**: **WireGuard** gateway as the single public entry point; the app and Wazuh have
  no public IPs.
- **SIEM**: **Wazuh** (manager + indexer + dashboard) on a separate VM, with an agent on
  the app VM collecting WAF/ingress and application logs, data persisted on a dedicated
  EBS volume.
- **Verifier**: sends a unique marker through the WAF each run and confirms it in Wazuh
  via the Indexer API; bounded timeouts, non-zero exit on failure, deployment gated on it.
- **Cloud security**: least-privilege security groups and IAM, no public workloads,
  encrypted volumes, IMDSv2, VPC flow logs, Terraform state and secrets kept out of git.
- **CI/CD**: Terraform validation, Trivy (IaC + filesystem), Gitleaks (secrets), the
  verifier, and a deploy job gated on all checks, triggered through protected branches.

## Architecture
See [docs/architecture.md](docs/architecture.md) for the full topology, trust boundaries,
and the reasoning behind each decision.

```
Evaluator ──WireGuard (UDP 51820, allowlisted IP)──▶ WG gateway (only public IP)
                                                          │ private routing
                 ┌────────────────────────────────────────┼─────────────────────┐
                 ▼                                          ▼
        App VM (private)                            Wazuh VM (private)
        K3s: WAF (NodePort) ──▶ Juice Shop          manager + indexer + dashboard
             │ ModSecurity + CRS   (ClusterIP)       agent events ──▶ indexed, searchable
             └ Wazuh agent ───────── logs ──────────▶
```

## Prerequisites
- An AWS account with EC2 available in the chosen region (this lab uses `ap-southeast-2`;
  see docs/architecture.md for why).
- Local tools: Terraform `>= 1.11`, AWS CLI (configured profile), a WireGuard client
  (`wireguard-tools`), Python 3, `make`.
- An S3 bucket for Terraform state (configured in `terraform/backend.tf`).

## Setup
1. Generate a WireGuard client key pair (private key stays on your machine):
   ```bash
   umask 077
   wg genkey | tee ~/.wg/juiceshop-client.key | wg pubkey > ~/.wg/juiceshop-client.pub
   ```
2. Create `terraform/terraform.tfvars` from the template and fill in your values:
   ```bash
   cp terraform/example.tfvars terraform/terraform.tfvars
   # set wg_client_public_key; evaluator_cidr is optional (auto-detected if empty)
   ```
   `terraform.tfvars` is git-ignored and must never be committed.

## Deploy / verify / teardown
```bash
make deploy    # terraform apply, then run the verifier (deploy fails if log delivery fails)
make verify    # re-run the log-delivery verifier with a fresh unique marker
make destroy   # tear down all lab resources
```
`make verify` requires the WireGuard tunnel to be up so the runner can reach the private
WAF and Wazuh indexer. Connecting the VPN is documented in docs/architecture.md.

## Cloud security and TLS
- Secrets and state are never committed: `.gitignore` blocks `*.tfvars`, `*.tfstate`,
  keys, and `.env`; Gitleaks runs in CI as a backstop.
- Terraform state lives in an encrypted, versioned S3 bucket with public access blocked.
- Firewall rules are least-privilege (security-group references, no `0.0.0.0/0` inbound);
  IAM instance roles carry only what each host needs.
- TLS handling is documented in [docs/tls.md](docs/tls.md).

## Estimated cost
See [docs/cost.md](docs/cost.md). The lab runs on small instances; the main hourly cost
is the NAT gateway. Everything is torn down with `make destroy` after testing.

## CI/CD
GitHub Actions runs Terraform validation, Trivy and Gitleaks scans, and the verifier on
pull requests; `main` is protected so changes land only through PRs with passing checks.
The deploy job runs on a self-hosted runner (on the VPN), applies Terraform, and gates on
the verifier. AWS access uses a least-privilege IAM user whose key is stored in protected
GitHub secrets (OIDC is unavailable on this account — see docs/architecture.md).

## Effort
Roughly 1.5 focused days end to end, including learning the WAF/SIEM tooling, debugging
the Wazuh single-node deployment, and hardening the CI pipeline.

## AI use
Built with AI assistance for boilerplate (cloud-init scripts, the verifier script) and
repetitive command-line checks. The Terraform, the architecture and security decisions,
the design logic, and the review of every change are my own.


## Run in your own AWS account
The lab is reproducible with `make deploy`. To run it in a different account, adjust:
1. **State backend** — set your own bucket in `terraform/backend.tf` (`bucket`, `key`,
   `region`). The bucket should have versioning + encryption + public access blocked.
2. **Region / instance types** — this build targets `ap-southeast-2` and
   free-tier-eligible instance types because the source account's organization policy
   restricts both. In an unrestricted account, change `region` and the
   `*_instance_type` variables as desired.
3. **Inputs** — copy `terraform/example.tfvars` to `terraform/terraform.tfvars` and set
   `wg_client_public_key` (your WireGuard client public key). `evaluator_cidr` is optional
   and auto-detects the deployer's public IP if left empty.
4. **CI (optional)** — provide `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
   `INDEXER_PASSWORD`, and `WG_CLIENT_PUBLIC_KEY` as repository secrets, and register a
   self-hosted runner on a VPN-connected machine for the gated deploy job.

Then `make deploy`. Reaching the WAF and Wazuh requires bringing up the WireGuard tunnel
(see docs/architecture.md).

## Known limitations / incomplete items
- Wazuh runs single-node on 2 vCPU / 8 GB (free-tier-eligible types only); Wazuh's own
  recommendation is 4 vCPU. Fine for a lab, not production scale.
- Wazuh dashboard/indexer still use the shipped demo credentials in this build; rotating
  them to generated secrets in SSM is documented as the next hardening step.
- WAF currently serves HTTP behind the VPN; self-signed TLS termination at the WAF is
  documented in docs/tls.md as the planned hardening step.
- OIDC for CI is blocked by an account-level SCP, so a scoped IAM user key is used instead.


## Evidence
Redacted proof of VPN access, WAF blocking (allow 200 / block 403), and a fresh Wazuh
event (end-to-end log delivery) is in [evidence/EVIDENCE.md](evidence/EVIDENCE.md).
