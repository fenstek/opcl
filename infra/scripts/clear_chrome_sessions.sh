#!/usr/bin/env bash
# Clear Chromium saved sessions from OpenClaw persistent user-data-dir.
# Prevents session restore on startup (which causes 20-30 renderer processes).
# Run before gateway restart or via cron.

CONTAINER="app-openclaw-gateway-1"
USER_DATA="/home/node/.openclaw/browser/openclaw/user-data/Default"
TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

log() { printf '[%s] %s\n' "$TS" "$*"; }

# Try clearing via docker exec (if container is running)
if docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null | grep -q running; then
  COUNT=$(docker exec "$CONTAINER" sh -c "ls '${USER_DATA}/Sessions/' 2>/dev/null | wc -l" 2>/dev/null || echo 0)
  if [[ "$COUNT" -gt "0" ]]; then
    docker exec "$CONTAINER" sh -c "rm -f '${USER_DATA}/Sessions/'* 2>/dev/null; echo ok" 2>/dev/null
    log "chrome_sessions: cleared $COUNT session files (via container)"
  else
    log "chrome_sessions: 0 files, nothing to clear"
  fi
else
  # Container not running — clear directly on host (volume is mounted from /opt/openclaw/state)
  HOST_PATH="/opt/openclaw/state/browser/openclaw/user-data/Default/Sessions"
  if [[ -d "$HOST_PATH" ]]; then
    COUNT=$(ls "$HOST_PATH" 2>/dev/null | wc -l)
    rm -f "${HOST_PATH}/"*
    log "chrome_sessions: cleared $COUNT session files (on host)"
  else
    log "chrome_sessions: sessions dir not found, skipping"
  fi
fi
