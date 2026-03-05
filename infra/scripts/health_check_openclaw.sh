#!/usr/bin/env bash
# /opt/openclaw/scripts/health_check_openclaw.sh
#
# Monitors:
#   1. SearxNG /healthz endpoint (host port 28888)
#   2. SearxNG search returns results (host port 28888)
#   3. OpenClaw gateway container is running
#   4. web_search path: gateway container → searxng:8080 (internal docker network)
#   5. [NEW] Browser watchdog: Chrome renderer count + memory; auto-restarts gateway
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
GATEWAY_COMPOSE_DIR="/opt/openclaw/app"
CURL_TIMEOUT=8      # seconds per HTTP request
DOCKER_TIMEOUT=15   # seconds for docker exec

# Browser watchdog thresholds
CHROME_PROC_WARN=15    # warn if chrome renderer count exceeds this
CHROME_PROC_RESTART=22 # auto-restart if chrome renderer count exceeds this
MEM_RESTART_MB=2400    # auto-restart if container RAM usage exceeds this (MB)

TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
FAILED=0
CHECKS_TOTAL=0
CHECKS_OK=0

# ── Logging helpers ───────────────────────────────────────────────────────────
ok()   { printf '[%s] OK   %s\n' "$TS" "$*"; (( CHECKS_OK++ ))   || true; }
warn() { printf '[%s] WARN %s\n' "$TS" "$*"; }
fail() { printf '[%s] FAIL %s\n' "$TS" "$*"; FAILED=1; }
check_start() { (( CHECKS_TOTAL++ )) || true; }

restart_gateway() {
  local reason="$1"
  printf '[%s] ACTION restart_gateway reason="%s"\n' "$TS" "$reason"
  /opt/openclaw/scripts/clear_chrome_sessions.sh 2>&1 || true
  cd "$GATEWAY_COMPOSE_DIR" && docker compose restart openclaw-gateway
  printf '[%s] ACTION restart_gateway done\n' "$TS"
}

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
    fail "gateway[container] status=${GW_STATUS} (expected running) — auto-restarting"
    printf '[%s] ACTION start_gateway reason="container_exited status=%s"\n' "$TS" "$GW_STATUS"
    cd "$GATEWAY_COMPOSE_DIR" && docker compose up -d openclaw-gateway 2>&1 | tail -5
    sleep 8
    GW_STATUS=$(docker inspect --format='{{.State.Status}}' "$GATEWAY_CONTAINER" 2>/dev/null) || GW_STATUS="not_found"
    printf '[%s] ACTION start_gateway result="%s"\n' "$TS" "$GW_STATUS"
fi

# ── Check 3b: Gateway HTTP health ──────────────────────────────────────────
check_start
if [[ "$GW_STATUS" == "running" ]]; then
    GW_HTTP=$(curl -sf --max-time "$CURL_TIMEOUT" -o /dev/null -w '%{http_code}' \
        "http://127.0.0.1:28789/" 2>/dev/null) || GW_HTTP="ERR"
    if [[ "$GW_HTTP" == "200" ]]; then
        ok "gateway[http] port=28789 http=200"
    else
        fail "gateway[http] port=28789 http=${GW_HTTP} — restarting"
        cd "$GATEWAY_COMPOSE_DIR" && docker compose restart openclaw-gateway 2>&1 | tail -3
    fi
else
    warn "gateway[http] skipped — container not running"
fi

# ── Check 4: web_search path — gateway→searxng:8080 (internal docker network) ─
check_start
if [[ "$GW_STATUS" == "running" ]]; then
    WS_OUT=$(timeout "$DOCKER_TIMEOUT" sudo docker exec "$GATEWAY_CONTAINER" \
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

# ── Check 5: Browser watchdog ─────────────────────────────────────────────────
# Counts Chromium renderer processes; auto-restarts if too many (tab leak = OOM risk).
# Also checks container memory usage.
check_start
if [[ "$GW_STATUS" == "running" ]]; then
    CHROME_PROCS=$(sudo docker exec "$GATEWAY_CONTAINER" \
        sh -c 'ps aux | grep chrome-linux64/chrome | grep -v grep | wc -l' \
        2>/dev/null) || CHROME_PROCS=0

    # Container memory in MiB
    MEM_USAGE_RAW=$(docker stats "$GATEWAY_CONTAINER" --no-stream \
        --format '{{.MemUsage}}' 2>/dev/null) || MEM_USAGE_RAW="0MiB"
    # Extract number before "/" (e.g. "1.5GiB / 2.7GiB" → "1536")
    MEM_MB=$(echo "$MEM_USAGE_RAW" | awk '{
        val=$1
        if (index(val,"GiB")) { sub("GiB","",val); printf "%d", val*1024 }
        else if (index(val,"MiB")) { sub("MiB","",val); printf "%d", val }
        else { print 0 }
    }')

    if (( CHROME_PROCS >= CHROME_PROC_RESTART )); then
        fail "browser[watchdog] chrome_procs=${CHROME_PROCS} >= ${CHROME_PROC_RESTART} (leak!) mem=${MEM_MB}MB — auto-restarting gateway"
        restart_gateway "chrome_proc_leak procs=${CHROME_PROCS}"
    elif (( MEM_MB >= MEM_RESTART_MB )); then
        fail "browser[watchdog] mem=${MEM_MB}MB >= ${MEM_RESTART_MB}MB — auto-restarting gateway"
        restart_gateway "memory_high mem=${MEM_MB}MB"
    elif (( CHROME_PROCS >= CHROME_PROC_WARN )); then
        warn "browser[watchdog] chrome_procs=${CHROME_PROCS} (warn threshold=${CHROME_PROC_WARN}) mem=${MEM_MB}MB"
        (( CHECKS_OK++ )) || true
    else
        ok "browser[watchdog] chrome_procs=${CHROME_PROCS} mem=${MEM_MB}MB"
    fi
else
    warn "browser[watchdog] skipped — gateway not running"
fi

# -- SSH host symlink -------------------------------------------------------
# Ensure ssh-host wrapper is accessible inside the gateway container
if [[ "$GW_STATUS" == "running" ]]; then
    SL=$(sudo docker exec "$GATEWAY_CONTAINER" sh -c 'ls /usr/local/bin/ssh-host 2>/dev/null')
    if [[ -z "$SL" ]]; then
        sudo docker exec -u root "$GATEWAY_CONTAINER" sh -c \
            'ln -sf /home/node/.openclaw/.ssh/ssh-host /usr/local/bin/ssh-host' 2>/dev/null
        printf '[%s] INFO  ssh-host symlink restored in container\n' "$TS"
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
if (( FAILED == 0 )); then
    printf '[%s] ---- PASS (%d/%d checks OK)\n' "$TS" "$CHECKS_OK" "$CHECKS_TOTAL"
    exit 0
else
    printf '[%s] ---- FAIL (%d/%d checks OK)\n' "$TS" "$CHECKS_OK" "$CHECKS_TOTAL"
    exit 1
fi
