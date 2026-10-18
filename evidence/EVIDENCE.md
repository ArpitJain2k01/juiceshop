# Evidence (redacted)

Captured against the live lab. Public IPs, private IPs, and keys are redacted.
Supporting raw output files are in this folder; add screenshots as noted.

## 1. VPN access (WireGuard tunnel established)
Output of `sudo wg show` after `wg-quick up` — a recent handshake confirms the encrypted
tunnel to the gateway is live. Reaching a private host (no public IP) proves VPN-gated
access.

> **Add screenshot:** `evidence/01-vpn-wg-show.png` — a terminal showing `sudo wg show`
> (redact the public endpoint IP and keys) and a successful `ping`/`ssh` to the private
> app IP.

Example (redacted):
```
interface: utun4
  public key: <redacted>
  listening port: <redacted>
peer: <redacted>
  endpoint: <redacted-public-ip>:51820
  allowed ips: 10.20.0.0/16, 10.8.0.0/24
  latest handshake: 14 seconds ago
  persistent keepalive: every 25 seconds
```

## 2. WAF blocking (allow 200 / deterministic block 403)
Requests through the WAF (NodePort 30443). Clean traffic allowed; attacks blocked by
ModSecurity + OWASP CRS. Juice Shop never receives the blocked requests. See
[waf-allow-block.txt](waf-allow-block.txt).

```
$ curl ... http://<app>:30443/                                 (clean)          HTTP 200
$ curl ... "http://<app>:30443/?id=1' OR '1'='1"               (SQL injection)  HTTP 403
$ curl ... "http://<app>:30443/?file=../../../../etc/passwd"   (path traversal) HTTP 403
```

> **Add screenshot:** `evidence/02-waf-allow-block.png` — the terminal showing the 200 and
> the two 403s.

## 3. Fresh Wazuh event (end-to-end log delivery + detection)
A marked SQL-injection request, blocked by the WAF, recorded in the Wazuh indexer. The
alert shows Wazuh classified it as a SQL injection attempt. See
[wazuh-event.txt](wazuh-event.txt).

```json
{
  "total_hits": 23,
  "sample_alert": {
    "timestamp": "2026-10-18T18:10:20Z",
    "agent_name": "ip-10-20-1-253",
    "rule_id": "31164",
    "rule_description": "SQL injection attempt.",
    "rule_level": 6,
    "matched_log": "GET /?marker=VERIFYMARKER-...&id=1' OR '1'='1 ... 403 ..."
  }
}
```

> **Add screenshot:** `evidence/03-wazuh-dashboard.png` — the Wazuh dashboard
> (`https://<wazuh-ip>:443`) Security Events view showing the 403 / SQL-injection alert.

## 4. End-to-end verifier (the deployment gate)
The verifier proves the whole pipeline on every run: unique marker → WAF → agent →
manager → indexer, with bounded timeouts and a non-zero exit on failure. See
[verify-output.txt](verify-output.txt).

```
[verify] PASS: WAF is up (clean GET / returned 200)
[verify] PASS: Wazuh indexer is healthy
[verify] PASS: allowed path returned 200 (marker VERIFYMARKER-clean-...)
[verify] PASS: attack blocked with 403 (marker VERIFYMARKER-attack-...)
[verify] PASS: attack marker found in Wazuh indexer (WAF -> agent -> manager -> indexer)
[verify] PASS: clean marker found in Wazuh indexer (full audit visibility)
[verify] ALL CHECKS PASSED
```
