#!/usr/bin/env bash
# =============================================================================
# tailscale_openclaw_ui_enable.sh — включить доступ к OpenClaw UI через tailnet
#
# Что делает:
#   Настраивает "tailscale serve" так, чтобы OpenClaw gateway (localhost:28789)
#   был доступен по HTTPS внутри tailnet по MagicDNS-адресу.
#   Никаких портов наружу не открывается.
#
# Использование:
#   sudo scripts/tailscale_openclaw_ui_enable.sh [--path PATH]
#
# Опции:
#   --path PATH   URL-путь для serve (default: /)
#                 Пример: --path /__openclaw__
#   --help        показать справку
#
# =============================================================================
set -euo pipefail

OPENCLAW_PORT=28789
SERVE_PATH="/"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path) SERVE_PATH="$2"; shift 2 ;;
    --help|-h)
      sed -n 's/^# \{0,1\}//p' "$0" | sed '1d'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ── Проверки ──────────────────────────────────────────────────────────────────
if ! command -v tailscale &>/dev/null; then
  echo "[ERROR] tailscale не установлен. Установите: curl -fsSL https://tailscale.com/install.sh | bash" >&2
  exit 1
fi

STATUS=$(tailscale status --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('BackendState','unknown'))" 2>/dev/null || echo "unknown")
if [[ "$STATUS" != "Running" ]]; then
  echo "[ERROR] Tailscale не запущен или не авторизован (state=$STATUS)."
  echo "  Запустите: sudo tailscale up"
  exit 1
fi

# ── Настройка serve ───────────────────────────────────────────────────────────
echo "[INFO] Настраиваю tailscale serve: HTTPS → localhost:${OPENCLAW_PORT}${SERVE_PATH}"
tailscale serve --https=443 "${SERVE_PATH}" "http://localhost:${OPENCLAW_PORT}"

# ── Получить URL ──────────────────────────────────────────────────────────────
HOSTNAME=$(tailscale status --json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
self = d.get('Self', {})
dns = self.get('DNSName', '')
print(dns.rstrip('.'))
" 2>/dev/null || echo "")

echo ""
echo "=========================================="
echo "  OpenClaw UI через Tailscale: ВКЛЮЧЁН"
echo "=========================================="
if [[ -n "$HOSTNAME" ]]; then
  echo "  URL:  https://${HOSTNAME}/__openclaw__/"
  echo "  Host: ${HOSTNAME}"
fi
echo ""
echo "  Проверить статус: tailscale serve status"
echo "  Отключить:        sudo scripts/tailscale_openclaw_ui_disable.sh"
echo "=========================================="
