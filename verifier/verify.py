#!/usr/bin/env python3
"""
Secure-lab verifier.

Proves the lab works end-to-end and gates the deployment:

  1. Readiness  : WAF returns 200 on a clean request; Wazuh indexer is healthy.
  2. ALLOW (B1) : a clean marked request returns 200 (allowed path works).
  3. BLOCK (A)  : a marked attack request returns 403 (WAF blocks it).
  4. DELIVERY A : the attack marker is found in the Wazuh indexer (detection + log path).
  5. DELIVERY B2: the clean  marker is found in the Wazuh indexer (full audit visibility).

Exit 0 only if ALL checks pass. Any failure exits non-zero so CI / `make deploy`
can gate on it. Every wait is bounded by a timeout.

Connectivity: run this from a machine on the WireGuard VPN (laptop or CI runner),
so the WAF NodePort and the Wazuh indexer private IPs are reachable.

Configuration via environment variables (no secrets hardcoded):
  WAF_URL            e.g. http://10.20.1.253:30443      (required)
  INDEXER_URL        e.g. https://10.20.1.118:9200       (required)
  INDEXER_USER       Wazuh indexer username              (default: admin)
  INDEXER_PASSWORD   Wazuh indexer password              (required)
  READINESS_TIMEOUT  seconds to wait for readiness       (default: 120)
  DELIVERY_TIMEOUT   seconds to wait for a marker to be indexed (default: 120)
  POLL_INTERVAL      seconds between retries             (default: 5)
"""

import os
import sys
import time
import uuid
import urllib3
import requests

# The indexer uses a self-signed cert in this private lab; we connect over the VPN
# to a private IP, so we intentionally skip TLS verification and silence the warning.
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def env(name, default=None, required=False):
    val = os.environ.get(name, default)
    if required and not val:
        fail(f"Missing required environment variable: {name}")
    return val


def log(msg):
    print(f"[verify] {msg}", flush=True)


def ok(msg):
    print(f"[verify] PASS: {msg}", flush=True)


def fail(msg):
    print(f"[verify] FAIL: {msg}", file=sys.stderr, flush=True)
    sys.exit(1)


# ---- Configuration ----------------------------------------------------------
WAF_URL = env("WAF_URL", required=True).rstrip("/")
INDEXER_URL = env("INDEXER_URL", required=True).rstrip("/")
INDEXER_USER = env("INDEXER_USER", default="admin")
INDEXER_PASSWORD = env("INDEXER_PASSWORD", required=True)
READINESS_TIMEOUT = int(env("READINESS_TIMEOUT", default="120"))
DELIVERY_TIMEOUT = int(env("DELIVERY_TIMEOUT", default="120"))
POLL_INTERVAL = int(env("POLL_INTERVAL", default="5"))

AUTH = (INDEXER_USER, INDEXER_PASSWORD)
REQ_TIMEOUT = 10  # per-HTTP-request timeout (seconds)


# ---- Helpers ----------------------------------------------------------------
def http_get(url, **kwargs):
    kwargs.setdefault("timeout", REQ_TIMEOUT)
    return requests.get(url, **kwargs)


def wait_for(description, check_fn, timeout):
    """Poll check_fn() until it returns True or timeout elapses. Bounded."""
    deadline = time.time() + timeout
    attempt = 0
    while time.time() < deadline:
        attempt += 1
        try:
            if check_fn():
                return True
        except requests.RequestException as e:
            log(f"{description}: not ready yet (attempt {attempt}): {e}")
        time.sleep(POLL_INTERVAL)
    return False


# ---- Step 1: readiness ------------------------------------------------------
def waf_ready():
    r = http_get(f"{WAF_URL}/")
    return r.status_code == 200


def indexer_ready():
    r = http_get(f"{INDEXER_URL}/_cluster/health", auth=AUTH, verify=False)
    if r.status_code != 200:
        return False
    status = r.json().get("status")
    return status in ("green", "yellow")


# ---- Step 4/5: marker lookup in the indexer ---------------------------------
def marker_indexed(marker):
    """Return True if the marker appears in any wazuh-alerts-* document."""
    query = {"query": {"query_string": {"query": f'"{marker}"'}}}
    r = http_get(
        f"{INDEXER_URL}/wazuh-alerts-*/_search",
        auth=AUTH,
        verify=False,
        json=query,
    )
    if r.status_code != 200:
        return False
    total = r.json().get("hits", {}).get("total", {}).get("value", 0)
    return total > 0


# ---- Main flow --------------------------------------------------------------
def main():
    run_id = uuid.uuid4().hex[:12]
    clean_marker = f"VERIFYMARKER-clean-{run_id}"
    attack_marker = f"VERIFYMARKER-attack-{run_id}"
    log(f"run id {run_id}")

    # 1. Readiness
    log("waiting for WAF readiness...")
    if not wait_for("WAF", waf_ready, READINESS_TIMEOUT):
        fail(f"WAF not ready within {READINESS_TIMEOUT}s at {WAF_URL}")
    ok("WAF is up (clean GET / returned 200)")

    log("waiting for Wazuh indexer readiness...")
    if not wait_for("indexer", indexer_ready, READINESS_TIMEOUT):
        fail(f"Wazuh indexer not ready within {READINESS_TIMEOUT}s at {INDEXER_URL}")
    ok("Wazuh indexer is healthy")

    # 2. ALLOW (B1): clean marked request -> 200
    r = http_get(f"{WAF_URL}/", params={"marker": clean_marker})
    if r.status_code != 200:
        fail(f"clean request expected 200, got {r.status_code}")
    ok(f"allowed path returned 200 (marker {clean_marker})")

    # 3. BLOCK (A): marked attack request -> 403
    r = http_get(
        f"{WAF_URL}/",
        params={"marker": attack_marker, "id": "1' OR '1'='1"},
    )
    if r.status_code != 403:
        fail(f"attack request expected 403, got {r.status_code}")
    ok(f"attack blocked with 403 (marker {attack_marker})")

    # 4. DELIVERY A: attack marker indexed (detection + log pipeline)
    log("waiting for attack marker to be indexed in Wazuh...")
    if not wait_for(
        "attack marker",
        lambda: marker_indexed(attack_marker),
        DELIVERY_TIMEOUT,
    ):
        fail(f"attack marker {attack_marker} not found in indexer within {DELIVERY_TIMEOUT}s")
    ok("attack marker found in Wazuh indexer (WAF -> agent -> manager -> indexer)")

    # 5. DELIVERY B2: clean marker indexed (full audit visibility via custom rule)
    log("waiting for clean marker to be indexed in Wazuh...")
    if not wait_for(
        "clean marker",
        lambda: marker_indexed(clean_marker),
        DELIVERY_TIMEOUT,
    ):
        fail(f"clean marker {clean_marker} not found in indexer within {DELIVERY_TIMEOUT}s")
    ok("clean marker found in Wazuh indexer (full audit visibility)")

    log("ALL CHECKS PASSED")
    sys.exit(0)


if __name__ == "__main__":
    main()
