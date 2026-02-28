#!/usr/bin/env bash
# =============================================================================
# tailscale_openclaw_ui_disable.sh — отключить доступ к OpenClaw UI через tailnet
#
# Что делает:
#   Убирает tailscale serve, закрывает HTTPS-доступ внутри tailnet.
#   Никак не затрагивает OpenClaw gateway (localhost:28789) и firewall.
#
# Использование:
#   sudo scripts/tailscale_openclaw_ui_disable.sh [--help]
#
# =============================================================================
set -euo pipefail

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) sed -n 's/^# \{0,1\}//p' "$0" | sed '1d'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if ! command -v tailscale &>/dev/null; then
  echo "[ERROR] tailscale не установлен." >&2; exit 1
fi

echo "[INFO] Отключаю tailscale serve (HTTPS:443)..."
tailscale serve --https=443 off 2>/dev/null || \
  tailscale serve reset 2>/dev/null || \
  echo "[WARN] Не удалось убрать serve — возможно уже отключён."

echo ""
echo "=========================================="
echo "  OpenClaw UI через Tailscale: ОТКЛЮЧЁН"
echo "=========================================="
echo "  OpenClaw gateway на localhost:${OPENCLAW_PORT:-28789} продолжает работать."
echo "  Включить снова: sudo scripts/tailscale_openclaw_ui_enable.sh"
echo "=========================================="
