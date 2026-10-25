#!/usr/bin/env bash
set -euo pipefail

INSTALL_URL="${OPENCLAW_INSTALL_CLI_URL:-${CLAWDBOT_INSTALL_CLI_URL:-https://openclaw.bot/install-cli.sh}}"
INSTALL_SHA256="${OPENCLAW_INSTALL_CLI_SHA256:-${CLAWDBOT_INSTALL_CLI_SHA256:-}}"
source /usr/local/lib/openclaw/verified-download.sh

openclaw_run_verified_installer "$INSTALL_URL" "$INSTALL_SHA256" --set-npm-prefix --no-onboard
