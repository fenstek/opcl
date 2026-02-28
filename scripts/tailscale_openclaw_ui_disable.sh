#!/usr/bin/env bash
# =============================================================================
# tailscale_openclaw_ui_disable.sh — отключить доступ к OpenClaw UI через tailnet
#
# Что делает:
#   Сбрасывает tailscale serve — закрывает HTTPS-доступ внутри tailnet.
#   Не трогает OpenClaw gateway (localhost:28789) и firewall.
#
# Использование:
#   scripts/tailscale_openclaw_ui_disable.sh
#
# =============================================================================
set -euo pipefail

if ! command -v tailscale &>/dev/null; then
  echo "[ERROR] tailscale не установлен." >&2; exit 1
fi

echo "[INFO] Отключаю tailscale serve..."
tailscale serve reset 2>/dev/null \
  && echo "[OK] Serve сброшен." \
  || echo "[WARN] Serve уже был отключён или ошибка сброса."

echo ""
echo "=========================================="
echo "  OpenClaw UI через Tailscale: ОТКЛЮЧЁН"
echo "=========================================="
echo "  OpenClaw gateway на localhost:28789 продолжает работать."
echo "  Включить снова: scripts/tailscale_openclaw_ui_enable.sh"
echo "=========================================="
