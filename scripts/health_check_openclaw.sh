#!/usr/bin/env bash
# /opt/openclaw/scripts/health_check_openclaw.sh
#
# Monitors:
#   1. SearxNG /healthz endpoint (host port 28888)
#   2. SearxNG search returns results (host port 28888)
#   3. OpenClaw gateway container is running
#   4. web_search path: gateway container → searxng:8080 (internal docker network)
#
# Exit codes:  0 = all OK,  1 = one or more checks failed
# Log:         /var/log/openclaw-health.log  (stdout → cron redirect)
#
# Cron (every 10 min):
#   */10 * * * * /opt/openclaw/scripts/health_check_openclaw.sh \
#     >> /var/log/openclaw-health.log 2>&1

set -uo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
SEARXNG_HOST="http://127.0.0.1:28888"
SEARXNG_INTERNAL="http://searxng:8080"
GATEWAY_CONTAINER="app-openclaw-gateway-1"
CURL_TIMEOUT=8      # seconds per HTTP request
DOCKER_TIMEOUT=15   # seconds for docker exec

TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
FAILED=0
CHECKS_TOTAL=0
CHECKS_OK=0

# ── Logging helpers ───────────────────────────────────────────────────────────
ok()   { printf '[%s] OK   %s\n' "$TS" "$*"; (( CHECKS_OK++ ))   || true; }
warn() { printf '[%s] WARN %s\n' "$TS" "$*"; }
fail() { printf '[%s] FAIL %s\n' "$TS" "$*"; FAILED=1; }
check_start() { (( CHECKS_TOTAL++ )) || true; }

# ── Check 1: SearxNG /healthz ─────────────────────────────────────────────────
check_start
HTTP_CODE=$(curl -sf \
    --max-time "$CURL_TIMEOUT" \
    -o /dev/null -w '%{http_code}' \
    "${SEARXNG_HOST}/healthz" 2>/dev/null) || HTTP_CODE="ERR"

if [[ "$HTTP_CODE" == "200" ]]; then
    ok "searxng[healthz] http=200"
else
    fail "searxng[healthz] http=${HTTP_CODE} (expected 200) — SearxNG may be down"
fi

# ── Check 2: SearxNG search returns JSON results ──────────────────────────────
check_start
SEARCH_OUT=$(curl -sf \
    --max-time "$CURL_TIMEOUT" \
    "${SEARXNG_HOST}/search?q=healthcheck&format=json" 2>/dev/null) || SEARCH_OUT=""

if [[ -z "$SEARCH_OUT" ]]; then
    fail "searxng[search] no response from ${SEARXNG_HOST}"
else
    RESULT_COUNT=$(printf '%s' "$SEARCH_OUT" \
        | python3 -c \
            "import json,sys; d=json.load(sys.stdin); print(len(d.get('results',[])))" \
            2>/dev/null) || RESULT_COUNT="ERR"

    if [[ "$RESULT_COUNT" =~ ^[0-9]+$ ]] && (( RESULT_COUNT > 0 )); then
        ok "searxng[search] results=${RESULT_COUNT}"
    elif [[ "$RESULT_COUNT" == "0" ]]; then
        warn "searxng[search] results=0 — search engines may be slow or rate-limited"
        (( CHECKS_OK++ )) || true   # degraded but not failed
    else
        fail "searxng[search] invalid JSON response (count=${RESULT_COUNT})"
    fi
fi

# ── Check 3: Gateway container running ───────────────────────────────────────
check_start
GW_STATUS=$(docker inspect \
    --format='{{.State.Status}}' \
    "$GATEWAY_CONTAINER" 2>/dev/null) || GW_STATUS="not_found"

if [[ "$GW_STATUS" == "running" ]]; then
    ok "gateway[container] status=running"
else
    fail "gateway[container] status=${GW_STATUS} (expected running)"
fi

# ── Check 4: web_search path — gateway→searxng:8080 (internal docker network) ─
# Reproduces the exact HTTP call that web-search.ts makes when provider=searxng.
# Skipped if the gateway container is not running (already failed in check 3).
check_start
if [[ "$GW_STATUS" == "running" ]]; then
    WS_OUT=$(timeout "$DOCKER_TIMEOUT" docker exec "$GATEWAY_CONTAINER" \
        sh -c "curl -sf --max-time $((CURL_TIMEOUT - 1)) \
               '${SEARXNG_INTERNAL}/search?q=healthcheck&format=json'" \
        2>/dev/null) || WS_OUT=""

    if [[ -z "$WS_OUT" ]]; then
        fail "web_search[path] gateway cannot reach ${SEARXNG_INTERNAL} — check openclaw-tools network"
    else
        WS_COUNT=$(printf '%s' "$WS_OUT" \
            | python3 -c \
                "import json,sys; d=json.load(sys.stdin); print(len(d.get('results',[])))" \
                2>/dev/null) || WS_COUNT="ERR"

        if [[ "$WS_COUNT" =~ ^[0-9]+$ ]] && (( WS_COUNT > 0 )); then
            ok "web_search[path] gateway→searxng:8080 results=${WS_COUNT}"
        elif [[ "$WS_COUNT" == "0" ]]; then
            warn "web_search[path] gateway→searxng:8080 results=0"
            (( CHECKS_OK++ )) || true
        else
            fail "web_search[path] invalid response from ${SEARXNG_INTERNAL} (count=${WS_COUNT})"
        fi
    fi
else
    warn "web_search[path] skipped — gateway container is not running"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
if (( FAILED == 0 )); then
    printf '[%s] ---- PASS (%d/%d checks OK)\n' "$TS" "$CHECKS_OK" "$CHECKS_TOTAL"
    exit 0
else
    printf '[%s] ---- FAIL (%d/%d checks OK)\n' "$TS" "$CHECKS_OK" "$CHECKS_TOTAL"
    exit 1
fi
