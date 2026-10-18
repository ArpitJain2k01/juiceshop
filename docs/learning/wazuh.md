# Wazuh — Learning Note

Plain-language reference so every Wazuh choice in this lab is explainable, and so the
Phase 5 verifier makes sense.

## What Wazuh is
Open-source **SIEM + XDR**:
- **SIEM** (Security Information and Event Management): collects logs/events from many
  sources, normalizes them, runs detection rules, raises **alerts**, and makes everything
  searchable.
- **XDR** (Extended Detection and Response): adds endpoint capabilities — file integrity
  monitoring, vulnerability detection, intrusion detection.

For this lab: **Wazuh collects logs from our app/WAF, runs rules, and produces searchable
security alerts.** The verifier later proves a specific log event reached Wazuh.

## The three components
| Component | Role | Analogy |
|---|---|---|
| **Wazuh Manager (server)** | Receives agent events, runs **decoders + rules**, generates **alerts** | The brain / analyst |
| **Wazuh Indexer** | Stores events/alerts in a searchable DB (OpenSearch fork) | The filing cabinet / search engine |
| **Wazuh Dashboard** | Web UI to view alerts, search, visualize (OpenSearch Dashboards fork) | The screen |

Data flow:
```
agents → MANAGER (decode + rule match → alert) → INDEXER (store, searchable) → DASHBOARD (view)
                                                      ▲
                                             the verifier queries HERE (Indexer API, 9200)
```

## The Wazuh Agent
- Lightweight program installed on the monitored machine (our **app VM**).
- Collects local data: log files, file changes, processes.
- Forwards events to the Manager over an encrypted channel.
- Ports: **1515** = enrollment (register, get a key), **1514** = ongoing event forwarding.
  (These are the ports opened in `sg-wazuh` from the app SG.)

## How a log becomes an alert (the pipeline)
When a log line reaches the manager:
1. **Decoder** parses the raw log into fields (URL, status, source IP, ...).
2. **Rule** pattern-matches the decoded fields; each rule has a **level** (0–15). A match
   generates an **alert** at that level.
3. **Alert** is written to `alerts.json` on the manager AND sent to the **Indexer** so it
   is searchable (and shown in the dashboard).

Example: WAF logs a 403 for a blocked SQLi → agent ships the line → manager decodes →
rule matches → alert → indexed → visible in dashboard and via API.

## Logs we collect (assignment: application/ingress logs)
Agent on the app VM collects:
- **WAF/ingress logs** — nginx + ModSecurity (allow/block events; the security-relevant data).
- **Juice Shop app logs** — the app's own output (K3s/container logs).

Because the app runs in K3s, the agent is pointed at container log paths
(`/var/log/containers` / `/var/log/pods`) and/or the ModSecurity audit log. Exact paths
are finalized during the agent/log-collection sub-phase.

## The Indexer API (what the verifier uses)
- The Indexer is OpenSearch-compatible; query it over HTTP on **port 9200**.
- Alerts live in an index like `wazuh-alerts-*`.
- Example query:
  ```
  GET https://<wazuh>:9200/wazuh-alerts-*/_search
  { "query": { "match": { "full_log": "<unique-marker>" } } }
  ```
- Verifier flow: send a request through the WAF carrying a **unique marker** → wait →
  query the Indexer for that marker → found = log delivery proven; not found within the
  timeout = fail (nonzero exit).

### Default-indexing gotcha
By default Wazuh indexes only events that **trigger a rule/alert**. To make our marker
searchable we either:
- (a) add a small **custom rule** that fires on the marker (cleaner, more realistic), or
- (b) enable **archive indexing** (index everything, including non-alerts).
The assignment allows either. Plan: a **custom rule**.

## Persistence (assignment requirement)
"Persist Wazuh data" + "reruns must preserve data":
- The Indexer's stored alerts must survive reboots/redeploys.
- Wazuh data directories live on a **separate EBS volume** not destroyed when the instance
  is replaced, so `terraform apply` reruns keep historical events.

## Deployment
- Official **Wazuh Docker** single-node deployment (docker-compose) on the Wazuh VM:
  manager + indexer + dashboard as containers.
- Resource reality: Wazuh recommends 4 vCPU / 8 GB. We use `m7i-flex.large` = 2 vCPU /
  8 GB. The 8 GB RAM matters most (the indexer is memory-hungry); 2 vCPU runs for a lab,
  just slower. Documented trade-off (free-tier-eligible types only).

## Likely cross-questions
- **Manager vs Indexer vs Dashboard?** Brain vs filing-cabinet vs screen.
- **How does an agent authenticate?** Enroll on 1515 → key → forward on 1514, encrypted.
- **How does a log become an alert?** Decoder → rule (level) → alert → indexed.
- **Why query the Indexer, not the Manager, in the verifier?** The Indexer is the
  searchable store with an HTTP API; the programmatic source of truth.
- **Default indexing gotcha?** Only alerts index by default; use a custom rule or archives.
- **Wazuh vs ELK vs Splunk?** Wazuh = free, security-focused, bundles stack + agents + rules;
  ELK = general log analytics (build detection yourself); Splunk = powerful but commercial.
- **How is data persisted?** Indexer data on a separate EBS volume that survives redeploys.
