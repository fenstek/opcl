#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/verified-download.sh"

INSTALL_URL="${HOMEBREW_INSTALL_URL:-https://raw.githubusercontent.com/Homebrew/install/85d1a3fc80d8a63932f632aca8f787de11d14a64/install.sh}"
INSTALL_SHA256="${HOMEBREW_INSTALL_SHA256:-}"

umask 077
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/openclaw-homebrew.XXXXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT HUP INT TERM

openclaw_download_verified "$INSTALL_URL" "$INSTALL_SHA256" "$TEMP_DIR/install.sh"

# Feed only the verified local file to the login shell; no URL or shell text is interpolated.
su - linuxbrew -c 'NONINTERACTIVE=1 CI=1 /bin/bash -s' <"$TEMP_DIR/install.sh"
