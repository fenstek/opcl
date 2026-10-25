#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_IMAGE="${OPENCLAW_INSTALL_SMOKE_IMAGE:-${CLAWDBOT_INSTALL_SMOKE_IMAGE:-openclaw-install-smoke:local}}"
NONROOT_IMAGE="${OPENCLAW_INSTALL_NONROOT_IMAGE:-${CLAWDBOT_INSTALL_NONROOT_IMAGE:-openclaw-install-nonroot:local}}"
INSTALL_URL="${OPENCLAW_INSTALL_URL:-${CLAWDBOT_INSTALL_URL:-https://openclaw.bot/install.sh}}"
CLI_INSTALL_URL="${OPENCLAW_INSTALL_CLI_URL:-${CLAWDBOT_INSTALL_CLI_URL:-https://openclaw.bot/install-cli.sh}}"
INSTALL_SHA256="${OPENCLAW_INSTALL_SHA256:-${CLAWDBOT_INSTALL_SHA256:-}}"
CLI_INSTALL_SHA256="${OPENCLAW_INSTALL_CLI_SHA256:-${CLAWDBOT_INSTALL_CLI_SHA256:-}}"
SKIP_NONROOT="${OPENCLAW_INSTALL_SMOKE_SKIP_NONROOT:-${CLAWDBOT_INSTALL_SMOKE_SKIP_NONROOT:-0}}"
LATEST_DIR="$(mktemp -d)"
LATEST_FILE="${LATEST_DIR}/latest"
CONTEXT_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$LATEST_DIR" "$CONTEXT_ROOT"' EXIT HUP INT TERM

stage_context() {
  local name="$1"
  local source_dir="$ROOT_DIR/scripts/docker/$name"
  local target_dir="$CONTEXT_ROOT/$name"
  mkdir -p "$target_dir"
  cp -- "$source_dir/Dockerfile" "$source_dir/run.sh" "$target_dir/"
  if [[ -f "$source_dir/run-cli.sh" ]]; then
    cp -- "$source_dir/run-cli.sh" "$target_dir/"
  fi
  cp -- "$ROOT_DIR/scripts/installers/verified-download.sh" "$target_dir/"
  printf '%s\n' "$target_dir"
}

SMOKE_CONTEXT="$(stage_context install-sh-smoke)"
NONROOT_CONTEXT="$(stage_context install-sh-nonroot)"

echo "==> Build smoke image (upgrade, root): $SMOKE_IMAGE"
docker build \
  -t "$SMOKE_IMAGE" \
  -f "$SMOKE_CONTEXT/Dockerfile" \
  "$SMOKE_CONTEXT"

echo "==> Run installer smoke test (root)"
docker run --rm -t \
  -v "${LATEST_DIR}:/out" \
  -e OPENCLAW_INSTALL_URL="$INSTALL_URL" \
  -e OPENCLAW_INSTALL_SHA256="$INSTALL_SHA256" \
  -e OPENCLAW_INSTALL_METHOD=npm \
  -e OPENCLAW_INSTALL_LATEST_OUT="/out/latest" \
  -e OPENCLAW_INSTALL_SMOKE_PREVIOUS="${OPENCLAW_INSTALL_SMOKE_PREVIOUS:-${CLAWDBOT_INSTALL_SMOKE_PREVIOUS:-}}" \
  -e OPENCLAW_INSTALL_SMOKE_SKIP_PREVIOUS="${OPENCLAW_INSTALL_SMOKE_SKIP_PREVIOUS:-${CLAWDBOT_INSTALL_SMOKE_SKIP_PREVIOUS:-0}}" \
  -e OPENCLAW_NO_ONBOARD=1 \
  -e DEBIAN_FRONTEND=noninteractive \
  "$SMOKE_IMAGE"

LATEST_VERSION=""
if [[ -f "$LATEST_FILE" ]]; then
  LATEST_VERSION="$(cat "$LATEST_FILE")"
fi

if [[ "$SKIP_NONROOT" == "1" ]]; then
  echo "==> Skip non-root installer smoke (OPENCLAW_INSTALL_SMOKE_SKIP_NONROOT=1)"
else
  echo "==> Build non-root image: $NONROOT_IMAGE"
  docker build \
    -t "$NONROOT_IMAGE" \
    -f "$NONROOT_CONTEXT/Dockerfile" \
    "$NONROOT_CONTEXT"

  echo "==> Run installer non-root test"
  docker run --rm -t \
    -e OPENCLAW_INSTALL_URL="$INSTALL_URL" \
    -e OPENCLAW_INSTALL_SHA256="$INSTALL_SHA256" \
    -e OPENCLAW_INSTALL_METHOD=npm \
    -e OPENCLAW_INSTALL_EXPECT_VERSION="$LATEST_VERSION" \
    -e OPENCLAW_NO_ONBOARD=1 \
    -e DEBIAN_FRONTEND=noninteractive \
    "$NONROOT_IMAGE"
fi

if [[ "${OPENCLAW_INSTALL_SMOKE_SKIP_CLI:-${CLAWDBOT_INSTALL_SMOKE_SKIP_CLI:-0}}" == "1" ]]; then
  echo "==> Skip CLI installer smoke (OPENCLAW_INSTALL_SMOKE_SKIP_CLI=1)"
  exit 0
fi

if [[ "$SKIP_NONROOT" == "1" ]]; then
  echo "==> Skip CLI installer smoke (non-root image skipped)"
  exit 0
fi

echo "==> Run CLI installer non-root test (same image)"
docker run --rm -t \
  --entrypoint /usr/local/bin/openclaw-install-cli \
  -e OPENCLAW_INSTALL_CLI_URL="$CLI_INSTALL_URL" \
  -e OPENCLAW_INSTALL_CLI_SHA256="$CLI_INSTALL_SHA256" \
  -e OPENCLAW_NO_ONBOARD=1 \
  -e DEBIAN_FRONTEND=noninteractive \
  "$NONROOT_IMAGE"
