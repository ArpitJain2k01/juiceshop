# Verifier — Learning Note

The verifier is the assignment's crown jewel: a script that proves the lab is actually
working end-to-end and **gates the deployment**. Deployment is only "successful" if the
verifier passes.

## What it must do (from the assignment)
1. **Check readiness** — the app/WAF/Wazuh are up before testing.
2. **Send a request with a new unique marker** — a value that cannot collide with any
   previous run.
3. **Find that marker in Wazuh via the Indexer API** — proving the log travelled the full
   path: WAF → agent → manager → indexer.
4. **Use timeouts and nonzero failure exits** — bounded waits; exit code != 0 on failure.
5. **Deployment succeeds only after readiness + log delivery pass.**
6. **Reruns must preserve data** — a fresh marker each run; historical events remain.

## Why a unique marker
If the verifier searched for a fixed string, a *previous* run's log could make it falsely
pass. A **new unique marker per run** (timestamp + random, e.g. `lab-marker-<epoch>-<rand>`)
guarantees that a hit in the indexer came from *this* run — real proof, not a stale match.

## The end-to-end path it proves
```
verifier ──HTTP(S) marked request──▶ WAF ──logs──▶ Wazuh agent ──1514──▶ manager
                                                                           │ decode + rule
                                                                           ▼
                                                                        indexer (9200)
verifier ──query wazuh-alerts-* for marker──────────────────────────────▶ found? → pass/fail
```
The verifier queries the **Indexer API** (`:9200`, OpenSearch-compatible), not the
dashboard or manager, because the indexer is the searchable programmatic source of truth.

## Attack-marker vs clean-request (design choice)
| Approach | Proves | Needs |
|---|---|---|
| **A: marker inside an attack (SQLi+marker)** | log delivery **and** WAF→SIEM detection/alerting | nothing extra (attack already triggers a rule → indexed in `wazuh-alerts-*`) |
| **B: clean request + marker** | log delivery for *any* request (audit completeness) | a custom rule or archive indexing (benign 200 does not alert by default) |

**Security view:** A tests detection+alerting (the SOC view); B tests full audit
visibility (no blind spots). For this lab we **gate on A** (one test proves log delivery
+ attack detection, deterministic, no extra config) and note B as a hardening option.

**Hybrid (used here):** also fire a **clean marked request** first to prove the allowed
path returns 200, then fire the **marked attack** and assert its marker is indexed. One
run demonstrates allow + block + log delivery.

## Readiness checks (before sending the marker)
Fail fast with clear messages if any of these are not ready within a timeout:
- WAF reachable and returns 200 on a clean `GET /`.
- Wazuh indexer `/_cluster/health` reachable and status is `green`/`yellow`.
- (Optional) agent shows Active on the manager.

## Timeouts and exit codes (non-negotiable per the assignment)
- Every wait loop is **bounded** (e.g. retry for up to N seconds, then give up).
- Log delivery is **eventually consistent** — the marker may take a few seconds to be
  indexed, so the indexer query **retries with backoff** until found or timeout.
- **Exit 0** only if readiness passed AND the marker was found.
- **Exit != 0** on any failure (readiness timeout, marker never indexed, API error).
- Non-zero exit is what lets CI **gate the deploy** and what makes `make deploy` fail
  loudly instead of silently "succeeding".

## How it gates the deployment
- Locally: `make deploy` runs `terraform apply` then the verifier; if the verifier exits
  non-zero, the deploy is considered failed.
- In Terraform: can be wired as a `null_resource` with a `local-exec` that runs the
  verifier, so `apply` itself errors if log delivery fails.
- In CI: the deploy job depends on the verifier/test job passing.

## Reruns preserve data
- Each run uses a **new marker**, so searches are unambiguous.
- Wazuh data is on a persistent EBS volume, so prior events survive — a rerun adds new
  events without wiping old ones.

## Likely cross-questions
- **Why a unique marker?** So a hit proves *this* run, not a stale previous log.
- **Why query the indexer, not the manager/dashboard?** Indexer is the searchable API /
  source of truth.
- **Why retries + timeout on the query?** Indexing is eventually consistent; bounded so
  failures surface instead of hanging.
- **Why non-zero exit?** It is the signal CI/`make` uses to gate/fail the deploy.
- **Attack-marker vs clean-marker?** Detection+delivery (A) vs audit completeness (B); see
  table. We gate on A, offer B as hardening.
- **What if the marker is never found?** Verifier times out and exits non-zero → deploy
  fails → you investigate the WAF→agent→manager→indexer chain.
