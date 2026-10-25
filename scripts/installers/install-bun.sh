#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/verified-download.sh"

INSTALL_DIR="${BUN_INSTALL_DIR:-${BUN_INSTALL:-/root/.bun}}"
TARGET_ARCH="${TARGETARCH:-$(uname -m)}"
openclaw_bun_release_for_arch "$TARGET_ARCH"

umask 077
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/openclaw-bun.XXXXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT HUP INT TERM

openclaw_download_verified \
  "$OPENCLAW_BUN_ARCHIVE_URL" \
  "$OPENCLAW_BUN_ARCHIVE_SHA256" \
  "$TEMP_DIR/bun.zip"

ARCHIVE_MEMBER="$OPENCLAW_BUN_ARCHIVE_DIR/bun"
MEMBER_COUNT="$(unzip -Z1 "$TEMP_DIR/bun.zip" | grep -Fxc -- "$ARCHIVE_MEMBER" || true)"
if [[ "$MEMBER_COUNT" != 1 ]]; then
  echo 'Pinned Bun archive does not contain exactly one expected binary.' >&2
  exit 1
fi
unzip -p "$TEMP_DIR/bun.zip" "$ARCHIVE_MEMBER" >"$TEMP_DIR/bun"
if [[ ! -s "$TEMP_DIR/bun" ]]; then
  echo 'Pinned Bun archive contains an empty binary.' >&2
  exit 1
fi

install -d -m 0755 -- "$INSTALL_DIR" "$INSTALL_DIR/bin"
install -m 0755 "$TEMP_DIR/bun" "$INSTALL_DIR/bin/bun"
