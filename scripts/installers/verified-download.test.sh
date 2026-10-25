#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="$ROOT_DIR/scripts/installers/verified-download.sh"
SMOKE_RUNNER="$ROOT_DIR/scripts/docker/install-sh-smoke/run.sh"
NONROOT_RUNNER="$ROOT_DIR/scripts/docker/install-sh-nonroot/run.sh"
CLI_RUNNER="$ROOT_DIR/scripts/docker/install-sh-nonroot/run-cli.sh"
E2E_RUNNER="$ROOT_DIR/scripts/docker/install-sh-e2e/run.sh"
DOCKER_RUNNER="$ROOT_DIR/scripts/test-install-sh-docker.sh"
WORK_DIR="$(mktemp -d)"
BUN_TEST_ROOT="$(mktemp -d "/tmp/openclaw-bun-test.XXXXXXXX")"
chmod 0755 "$BUN_TEST_ROOT"
trap 'rm -rf -- "$WORK_DIR" "$BUN_TEST_ROOT"' EXIT HUP INT TERM

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

source "$HELPER"

MOCK_BIN="$WORK_DIR/mock-bin"
mkdir -p "$MOCK_BIN" "$WORK_DIR/private-tmp"
cat >"$MOCK_BIN/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
set -euo pipefail

output=''
url=''
proto=''
proto_redir=''
location=0
while (($#)); do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    --proto) proto="$2"; shift 2 ;;
    --proto-redir) proto_redir="$2"; shift 2 ;;
    --location) location=1; shift ;;
    --silent|--show-error|--fail|--globoff|--tlsv1.2) shift ;;
    --max-redirs) [[ "$2" == 5 ]]; shift 2 ;;
    --) shift; url="${1-}"; shift ;;
    *) echo "unexpected curl argument" >&2; exit 90 ;;
  esac
done

printf x >>"$CURL_MOCK_CALLS"
printf '%s' "$url" >"$CURL_MOCK_CAPTURE_URL"
printf '%s\0%s\0%s\0' "$proto" "$proto_redir" "$location" >"$CURL_MOCK_CAPTURE_FLAGS"
[[ "$url" == "$CURL_MOCK_EXPECT_URL" ]] || exit 91
[[ "$proto" == '=https' && "$proto_redir" == '=https' && "$location" == 1 ]] || exit 92
cp -- "$CURL_MOCK_FIXTURE" "$output"
if [[ "${CURL_MOCK_MODE:-success}" == fail-after-write ]]; then
  exit 23
fi
MOCK_CURL
chmod +x "$MOCK_BIN/curl"

FIXTURE="$WORK_DIR/fixture.sh"
cat >"$FIXTURE" <<'FIXTURE_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\0' "${FIXTURE_ENV-}" "${OPENCLAW_BETA-}" "${CLAWDBOT_BETA-}" \
  "${OPENCLAW_VERSION-}" "${CLAWDBOT_VERSION-}" "$@" >"$FIXTURE_EXEC_LOG"
FIXTURE_SCRIPT
chmod +x "$FIXTURE"
FIXTURE_SHA256="$(sha256sum -- "$FIXTURE")"
FIXTURE_SHA256="${FIXTURE_SHA256%% *}"

export PATH="$MOCK_BIN:$PATH"
export TMPDIR="$WORK_DIR/private-tmp"
export CURL_MOCK_FIXTURE="$FIXTURE"
export CURL_MOCK_CALLS="$WORK_DIR/curl-calls"
export CURL_MOCK_CAPTURE_URL="$WORK_DIR/curl-url"
export CURL_MOCK_CAPTURE_FLAGS="$WORK_DIR/curl-flags"
export FIXTURE_EXEC_LOG="$WORK_DIR/executed"
export FIXTURE_ENV='fixture env value'

TRUSTED_FIXTURE_URL='https://fixture.invalid/installer.sh'
CURL_MOCK_EXPECT_URL="$TRUSTED_FIXTURE_URL" openclaw_run_verified_installer \
  "$TRUSTED_FIXTURE_URL" "$FIXTURE_SHA256" 'arg with spaces' '--literal=$(touch marker)' \
  || fail 'trusted fixture did not execute'
mapfile -d '' -t OBSERVED_ARGS <"$FIXTURE_EXEC_LOG"
[[ "${OBSERVED_ARGS[0]}" == "$FIXTURE_ENV" ]] || fail 'environment did not reach fixture'
[[ -z "${OBSERVED_ARGS[1]}${OBSERVED_ARGS[2]}${OBSERVED_ARGS[3]}${OBSERVED_ARGS[4]}" ]] \
  || fail 'unset installer environment variables changed'
[[ "${OBSERVED_ARGS[5]}" == 'arg with spaces' ]] || fail 'first installer argument changed'
[[ "${OBSERVED_ARGS[6]}" == '--literal=$(touch marker)' ]] || fail 'shell metacharacters in argument were evaluated'
[[ "$(cat "$CURL_MOCK_CAPTURE_URL")" == "$TRUSTED_FIXTURE_URL" ]] || fail 'curl URL changed'
mapfile -d '' -t CURL_FLAGS <"$CURL_MOCK_CAPTURE_FLAGS"
[[ "${CURL_FLAGS[0]}" == '=https' && "${CURL_FLAGS[1]}" == '=https' && "${CURL_FLAGS[2]}" == 1 ]] \
  || fail 'HTTPS redirect restrictions were not passed to curl'
[[ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ]] || fail 'private download directory was not cleaned up'

OPENCLAW_BETA=1 CLAWDBOT_BETA=1 CURL_MOCK_EXPECT_URL="$TRUSTED_FIXTURE_URL" \
  openclaw_run_verified_installer "$TRUSTED_FIXTURE_URL" "$FIXTURE_SHA256" \
  || fail 'beta environment fixture did not execute'
mapfile -d '' -t OBSERVED_ARGS <"$FIXTURE_EXEC_LOG"
[[ "${OBSERVED_ARGS[1]}" == 1 && "${OBSERVED_ARGS[2]}" == 1 ]] \
  || fail 'beta environment did not reach installer script'

OPENCLAW_VERSION='1.2.3-beta.4' CLAWDBOT_VERSION='1.2.3-beta.4' \
  CURL_MOCK_EXPECT_URL="$TRUSTED_FIXTURE_URL" \
  openclaw_run_verified_installer "$TRUSTED_FIXTURE_URL" "$FIXTURE_SHA256" \
  || fail 'version environment fixture did not execute'
mapfile -d '' -t OBSERVED_ARGS <"$FIXTURE_EXEC_LOG"
[[ "${OBSERVED_ARGS[3]}" == '1.2.3-beta.4' && "${OBSERVED_ARGS[4]}" == '1.2.3-beta.4' ]] \
  || fail 'version environment did not reach installer script'

expect_rejected_without_execution() {
  local label="$1"
  shift
  rm -f -- "$FIXTURE_EXEC_LOG"
  : >"$CURL_MOCK_CALLS"
  if "$@"; then
    fail "$label unexpectedly succeeded"
  fi
  [[ ! -e "$FIXTURE_EXEC_LOG" ]] || fail "$label executed downloaded bytes"
}

CUSTOM_URL='https://custom.invalid/install.sh'
CURL_MOCK_EXPECT_URL="$CUSTOM_URL" expect_rejected_without_execution 'missing custom URL pin' \
  openclaw_run_verified_installer "$CUSTOM_URL" ''
[[ ! -s "$CURL_MOCK_CALLS" ]] || fail 'missing pin reached curl'
CURL_MOCK_EXPECT_URL="$CUSTOM_URL" expect_rejected_without_execution 'malformed SHA256' \
  openclaw_run_verified_installer "$CUSTOM_URL" 'abc'
[[ ! -s "$CURL_MOCK_CALLS" ]] || fail 'malformed pin reached curl'
CURL_MOCK_EXPECT_URL="$CUSTOM_URL" expect_rejected_without_execution 'wrong SHA256' \
  openclaw_run_verified_installer "$CUSTOM_URL" '0000000000000000000000000000000000000000000000000000000000000000'
[[ -s "$CURL_MOCK_CALLS" ]] || fail 'wrong pin did not attempt the offline fixture transfer'
[[ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ]] || fail 'rejected download left temporary files'

rm -f -- "$FIXTURE_EXEC_LOG"
: >"$CURL_MOCK_CALLS"
if CURL_MOCK_EXPECT_URL="$CUSTOM_URL" CURL_MOCK_MODE=fail-after-write \
  openclaw_run_verified_installer "$CUSTOM_URL" "$FIXTURE_SHA256"; then
  fail 'partial transfer unexpectedly succeeded'
fi
[[ ! -e "$FIXTURE_EXEC_LOG" ]] || fail 'partial transfer executed downloaded bytes'
[[ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ]] || fail 'partial transfer left temporary files'

INJECTION_MARKER="$WORK_DIR/url-was-evaluated"
INJECTION_URL="https://custom.invalid/'\$(touch\$IFS${INJECTION_MARKER})'"
rm -f -- "$FIXTURE_EXEC_LOG"
CURL_MOCK_EXPECT_URL="$INJECTION_URL" openclaw_run_verified_installer \
  "$INJECTION_URL" "$FIXTURE_SHA256" || fail 'quoted injection URL did not remain data'
[[ "$(cat "$CURL_MOCK_CAPTURE_URL")" == "$INJECTION_URL" ]] || fail 'injection URL changed before curl'
[[ ! -e "$INJECTION_MARKER" ]] || fail 'URL text was evaluated by a shell'

NEWLINE_URL=$'https://custom.invalid/line\nbreak'
CURL_MOCK_EXPECT_URL="$NEWLINE_URL" expect_rejected_without_execution 'newline URL' \
  openclaw_run_verified_installer "$NEWLINE_URL" "$FIXTURE_SHA256"
[[ ! -s "$CURL_MOCK_CALLS" ]] || fail 'newline URL reached curl'
CURL_MOCK_EXPECT_URL='http://custom.invalid/install.sh' expect_rejected_without_execution 'non-HTTPS URL' \
  openclaw_run_verified_installer 'http://custom.invalid/install.sh' "$FIXTURE_SHA256"
[[ ! -s "$CURL_MOCK_CALLS" ]] || fail 'non-HTTPS URL reached curl'

[[ "$(openclaw_verified_known_sha256 'https://openclaw.ai/install.sh')" == \
  '5ba2d16e2b89eab7e4d6f96f1348d867c43307309e829841a78fc8820956dd0c' ]] \
  || fail 'OpenClaw installer pin changed'
[[ "$(openclaw_verified_known_sha256 'https://openclaw.bot/install.sh')" == \
  '5ba2d16e2b89eab7e4d6f96f1348d867c43307309e829841a78fc8820956dd0c' ]] \
  || fail 'legacy OpenClaw installer alias is not pinned'
[[ "$(openclaw_verified_known_sha256 'https://openclaw.ai/install-cli.sh')" == \
  '7ad6910e76cf692eb60bed987a26637548cc5363164031ddf6ffec480ae1458b' ]] \
  || fail 'OpenClaw CLI installer pin changed'
[[ "$(openclaw_verified_known_sha256 'https://openclaw.bot/install-cli.sh')" == \
  '7ad6910e76cf692eb60bed987a26637548cc5363164031ddf6ffec480ae1458b' ]] \
  || fail 'legacy OpenClaw CLI installer alias is not pinned'
[[ "$(openclaw_verified_known_sha256 'https://raw.githubusercontent.com/Homebrew/install/85d1a3fc80d8a63932f632aca8f787de11d14a64/install.sh')" == \
  '5f333bbe53bc490e51e7ccb1df8779b3dd6ee73a1a7379efda216edb08ccb148' ]] \
  || fail 'Homebrew installer pin changed'

openclaw_bun_release_for_arch amd64 || fail 'amd64 Bun pin missing'
[[ "$OPENCLAW_BUN_ARCHIVE_URL" == 'https://github.com/oven-sh/bun/releases/download/bun-v1.4.4/bun-linux-x64.zip' ]] \
  && [[ "$OPENCLAW_BUN_ARCHIVE_SHA256" == 'bf8ccbfb2b0b80159e0f9a6d15c55317add8077534dbc6130a3edb52fccb395c' ]] \
  && [[ "$OPENCLAW_BUN_ARCHIVE_DIR" == bun-linux-x64 ]] || fail 'amd64 Bun pin is incorrect'
openclaw_bun_release_for_arch x64 || fail 'x64 Bun alias is unsupported'
openclaw_bun_release_for_arch arm64 || fail 'arm64 Bun pin missing'
[[ "$OPENCLAW_BUN_ARCHIVE_URL" == 'https://github.com/oven-sh/bun/releases/download/bun-v1.4.4/bun-linux-aarch64.zip' ]] \
  && [[ "$OPENCLAW_BUN_ARCHIVE_SHA256" == 'baa6bb36f51d6e58561e02bbea825038a9df454f673d6d776e8bbf86f8c7850e' ]] \
  && [[ "$OPENCLAW_BUN_ARCHIVE_DIR" == bun-linux-aarch64 ]] || fail 'arm64 Bun pin is incorrect'
openclaw_bun_release_for_arch aarch64 || fail 'aarch64 alias is unsupported'
if openclaw_bun_release_for_arch riscv64; then
  fail 'unknown Bun architecture was accepted'
fi

# Exercise the real Bun installer with local archive and binary fixtures. The
# temporary helper copy changes only the archive digest so the shared verifier
# still calculates and checks the actual fixture bytes.
openclaw_bun_release_for_arch amd64 || fail 'amd64 Bun fixture URL missing'
BUN_FIXTURE_URL="$OPENCLAW_BUN_ARCHIVE_URL"
BUN_PINNED_SHA256="$OPENCLAW_BUN_ARCHIVE_SHA256"
BUN_ARCHIVE_FIXTURE="$WORK_DIR/bun-fixture.zip"
BUN_BINARY_FIXTURE="$WORK_DIR/bun-fixture"
printf 'offline Bun archive fixture\n' >"$BUN_ARCHIVE_FIXTURE"
printf '#!/bin/sh\nexit 0\n' >"$BUN_BINARY_FIXTURE"
chmod 0755 "$BUN_BINARY_FIXTURE"
BUN_FIXTURE_SHA256="$(sha256sum -- "$BUN_ARCHIVE_FIXTURE")"
BUN_FIXTURE_SHA256="${BUN_FIXTURE_SHA256%% *}"
sed "s/${BUN_PINNED_SHA256}/${BUN_FIXTURE_SHA256}/" "$HELPER" \
  >"$BUN_TEST_ROOT/verified-download.sh"
cp -- "$ROOT_DIR/scripts/installers/install-bun.sh" "$BUN_TEST_ROOT/install-bun.sh"

cat >"$MOCK_BIN/unzip" <<'MOCK_UNZIP'
#!/usr/bin/env bash
set -euo pipefail

case "${1-}" in
  -Z1)
    [[ $# == 2 ]] || exit 81
    cmp -s -- "$2" "$UNZIP_MOCK_ARCHIVE" || exit 82
    stat -c '%a' "$(dirname "$2")" >"$UNZIP_MOCK_PRIVATE_MODE_FILE"
    printf '%s\n' 'bun-linux-x64/bun'
    ;;
  -p)
    [[ $# == 3 && "$3" == 'bun-linux-x64/bun' ]] || exit 83
    cmp -s -- "$2" "$UNZIP_MOCK_ARCHIVE" || exit 84
    cat -- "$UNZIP_MOCK_BINARY"
    ;;
  *)
    echo 'unexpected unzip invocation' >&2
    exit 85
    ;;
esac
MOCK_UNZIP
chmod +x "$MOCK_BIN/unzip"

BUN_INSTALL_PREFIX="$BUN_TEST_ROOT/prefix"
mkdir -p "$BUN_INSTALL_PREFIX"
chmod 0700 "$BUN_INSTALL_PREFIX"
printf '%s\n' 'private sentinel' >"$BUN_INSTALL_PREFIX/private-sentinel"
chmod 0600 "$BUN_INSTALL_PREFIX/private-sentinel"
CURL_MOCK_EXPECT_URL="$BUN_FIXTURE_URL" \
  CURL_MOCK_MODE=success \
  CURL_MOCK_FIXTURE="$BUN_ARCHIVE_FIXTURE" \
  UNZIP_MOCK_ARCHIVE="$BUN_ARCHIVE_FIXTURE" \
  UNZIP_MOCK_BINARY="$BUN_BINARY_FIXTURE" \
  UNZIP_MOCK_PRIVATE_MODE_FILE="$WORK_DIR/bun-private-mode" \
  TARGETARCH=amd64 BUN_INSTALL_DIR="$BUN_INSTALL_PREFIX" \
  /bin/bash "$BUN_TEST_ROOT/install-bun.sh" \
  || fail 'offline Bun installation fixture failed'
[[ "$(stat -c '%a' "$BUN_INSTALL_PREFIX")" == 755 ]] \
  || fail 'Bun installation prefix is not accessible to runtime users'
[[ "$(stat -c '%a' "$BUN_INSTALL_PREFIX/bin")" == 755 ]] \
  || fail 'Bun bin directory is not accessible to runtime users'
[[ "$(stat -c '%a' "$BUN_INSTALL_PREFIX/bin/bun")" == 755 ]] \
  || fail 'installed Bun binary is not executable by runtime users'
[[ "$(stat -c '%a' "$BUN_INSTALL_PREFIX/private-sentinel")" == 600 ]] \
  || fail 'Bun installation changed permissions on an unrelated prefix file'
[[ "$(cat "$WORK_DIR/bun-private-mode")" == 700 ]] \
  || fail 'Bun private download directory did not retain mode 0700'
if [[ "$(id -u)" == 0 ]] && command -v runuser >/dev/null 2>&1; then
  runuser -u nobody -- "$BUN_INSTALL_PREFIX/bin/bun" \
    || fail 'non-root user could not execute the installed Bun fixture'
fi

# Run the exact sandbox Docker RUN fragments through /bin/sh with a failing
# helper and successful follow-up commands. The helper failure must win.
RUN_MOCK_BIN="$WORK_DIR/run-mock-bin"
mkdir -p "$RUN_MOCK_BIN"
cat >"$RUN_MOCK_BIN/bash" <<'MOCK_BASH'
#!/bin/sh
printf '%s\n' "$*" >>"$RUN_MOCK_HELPER_CALLS"
exit 23
MOCK_BASH
cat >"$RUN_MOCK_BIN/id" <<'MOCK_ID'
#!/bin/sh
exit 0
MOCK_ID
cat >"$RUN_MOCK_BIN/chown" <<'MOCK_CHOWN'
#!/bin/sh
exit 0
MOCK_CHOWN
cat >"$RUN_MOCK_BIN/ln" <<'MOCK_LN'
#!/bin/sh
printf '%s\n' "$*" >>"$RUN_MOCK_LINK_CALLS"
exit 0
MOCK_LN
chmod +x "$RUN_MOCK_BIN/bash" "$RUN_MOCK_BIN/id" "$RUN_MOCK_BIN/chown" "$RUN_MOCK_BIN/ln"
RUN_MOCK_HELPER_CALLS="$WORK_DIR/helper-calls"
RUN_MOCK_LINK_CALLS="$WORK_DIR/link-calls"
BUN_RUN_FRAGMENT="$(sed -n '/^RUN set -e; if .*INSTALL_BUN/,/^fi$/p' \
  "$ROOT_DIR/Dockerfile.sandbox-common" | sed '1s/^RUN //' | sed 's/\\$//' | tr '\n' ' ')"
[[ -n "$BUN_RUN_FRAGMENT" ]] || fail 'sandbox Bun RUN fragment was not found'
if INSTALL_BUN=1 BUN_INSTALL_DIR="$BUN_TEST_ROOT/docker-bun" \
  RUN_MOCK_HELPER_CALLS="$RUN_MOCK_HELPER_CALLS" \
  RUN_MOCK_LINK_CALLS="$RUN_MOCK_LINK_CALLS" \
  PATH="$RUN_MOCK_BIN:$PATH" /bin/sh -c "$BUN_RUN_FRAGMENT"; then
  fail 'sandbox Docker RUN hid the Bun helper failure'
fi
[[ -s "$RUN_MOCK_HELPER_CALLS" ]] || fail 'sandbox Bun helper fixture was not invoked'
[[ ! -e "$RUN_MOCK_LINK_CALLS" ]] || fail 'sandbox Docker RUN continued after Bun helper failure'
rm -f -- "$RUN_MOCK_HELPER_CALLS" "$RUN_MOCK_LINK_CALLS"
INSTALL_BUN=0 BUN_INSTALL_DIR="$BUN_TEST_ROOT/docker-bun" \
  RUN_MOCK_HELPER_CALLS="$RUN_MOCK_HELPER_CALLS" \
  RUN_MOCK_LINK_CALLS="$RUN_MOCK_LINK_CALLS" \
  PATH="$RUN_MOCK_BIN:$PATH" /bin/sh -c "$BUN_RUN_FRAGMENT" \
  || fail 'INSTALL_BUN=0 no longer skips Bun installation'
[[ ! -e "$RUN_MOCK_HELPER_CALLS" && ! -e "$RUN_MOCK_LINK_CALLS" ]] \
  || fail 'INSTALL_BUN=0 invoked the Bun installation path'

BREW_RUN_FRAGMENT="$(sed -n '/^RUN set -e; if .*INSTALL_BREW/,/^fi$/p' \
  "$ROOT_DIR/Dockerfile.sandbox-common" | sed '1s/^RUN //' | sed 's/\\$//' | tr '\n' ' ')"
[[ -n "$BREW_RUN_FRAGMENT" ]] || fail 'sandbox Homebrew RUN fragment was not found'
BREW_INSTALL_FIXTURE="$BUN_TEST_ROOT/brew-prefix"
mkdir -p "$BREW_INSTALL_FIXTURE/Library" "$BREW_INSTALL_FIXTURE/bin"
printf '#!/bin/sh\nexit 0\n' >"$BREW_INSTALL_FIXTURE/bin/brew"
chmod 0755 "$BREW_INSTALL_FIXTURE/bin/brew"
if INSTALL_BREW=1 BREW_INSTALL_DIR="$BREW_INSTALL_FIXTURE" \
  RUN_MOCK_HELPER_CALLS="$RUN_MOCK_HELPER_CALLS" \
  RUN_MOCK_LINK_CALLS="$RUN_MOCK_LINK_CALLS" \
  PATH="$RUN_MOCK_BIN:$PATH" /bin/sh -c "$BREW_RUN_FRAGMENT"; then
  fail 'sandbox Docker RUN hid the Homebrew helper failure'
fi
[[ -s "$RUN_MOCK_HELPER_CALLS" ]] || fail 'sandbox Homebrew helper fixture was not invoked'
[[ ! -e "$RUN_MOCK_LINK_CALLS" ]] || fail 'sandbox Docker RUN continued after Homebrew helper failure'
rm -f -- "$RUN_MOCK_HELPER_CALLS" "$RUN_MOCK_LINK_CALLS"
INSTALL_BREW=0 BREW_INSTALL_DIR="$BREW_INSTALL_FIXTURE" \
  RUN_MOCK_HELPER_CALLS="$RUN_MOCK_HELPER_CALLS" \
  RUN_MOCK_LINK_CALLS="$RUN_MOCK_LINK_CALLS" \
  PATH="$RUN_MOCK_BIN:$PATH" /bin/sh -c "$BREW_RUN_FRAGMENT" \
  || fail 'INSTALL_BREW=0 no longer skips Homebrew installation'
[[ ! -e "$RUN_MOCK_HELPER_CALLS" && ! -e "$RUN_MOCK_LINK_CALLS" ]] \
  || fail 'INSTALL_BREW=0 invoked the Homebrew installation path'

# The docs carry a standalone repeatable Docker RUN; exercise its failure path too.
DOC_BUN_RUN_FRAGMENT="$(sed -n 's/^RUN set -e; bash \/usr\/local\/lib\/openclaw\/install-bun\.sh$/&/p' \
  "$ROOT_DIR/docs/install/docker.md" | sed 's/^RUN //')"
[[ -n "$DOC_BUN_RUN_FRAGMENT" ]] || fail 'Docker docs Bun RUN fragment is not fail-closed'
if RUN_MOCK_HELPER_CALLS="$RUN_MOCK_HELPER_CALLS" PATH="$RUN_MOCK_BIN:$PATH" \
  /bin/sh -c "$DOC_BUN_RUN_FRAGMENT"; then
  fail 'Docker docs RUN fragment hid the Bun helper failure'
fi

grep -Fq 'OPENCLAW_BETA=1 CLAWDBOT_BETA=1 openclaw_run_verified_installer' "$E2E_RUNNER" \
  || fail 'E2E beta variables are not assigned to the installer process'
grep -Fq 'OPENCLAW_VERSION="$INSTALL_TAG" CLAWDBOT_VERSION="$INSTALL_TAG"' "$E2E_RUNNER" \
  || fail 'E2E version variables are not assigned to the installer process'
grep -Fq 'openclaw_run_verified_installer "$INSTALL_URL" "$INSTALL_SHA256"' "$E2E_RUNNER" \
  || fail 'E2E installer invocation does not use the verified boundary'
grep -Fq 'OPENCLAW_INSTALL_CLI_SHA256' "$DOCKER_RUNNER" \
  || fail 'CLI installer digest is not forwarded to the Docker runner'
grep -Fq -- '--set-npm-prefix --no-onboard' "$CLI_RUNNER" \
  || fail 'CLI installer arguments were not preserved'
grep -Fq -- '--entrypoint /usr/local/bin/openclaw-install-cli' "$DOCKER_RUNNER" \
  || fail 'CLI smoke test does not call the dedicated verified entrypoint'
grep -Fq 'OPENCLAW_INSTALL_SHA256' "$SMOKE_RUNNER" \
  || fail 'smoke runner does not forward the OpenClaw installer pin'
grep -Fq 'OPENCLAW_INSTALL_SHA256' "$NONROOT_RUNNER" \
  || fail 'non-root runner does not forward the OpenClaw installer pin'
for context in smoke nonroot e2e; do
  grep -Fq 'COPY verified-download.sh /usr/local/lib/openclaw/verified-download.sh' \
    "$ROOT_DIR/scripts/docker/install-sh-$context/Dockerfile" \
    || fail "$context Docker context does not copy the shared helper"
done
grep -Fq 'COPY run-cli.sh /usr/local/bin/openclaw-install-cli' \
  "$ROOT_DIR/scripts/docker/install-sh-nonroot/Dockerfile" \
  || fail 'CLI installer entrypoint is not copied into the non-root image'
grep -Fq 'scripts/installers/verified-download.sh' "$DOCKER_RUNNER" \
  || fail 'smoke Docker runner does not stage the shared helper'
grep -Fq 'scripts/installers/verified-download.sh' "$ROOT_DIR/scripts/test-install-sh-e2e-docker.sh" \
  || fail 'E2E Docker runner does not stage the shared helper'
grep -Fq 'scripts/installers/install-bun.sh' "$ROOT_DIR/Dockerfile" \
  || fail 'main Dockerfile does not install Bun through the pinned archive helper'
grep -Fq 'scripts/installers/install-bun.sh' "$ROOT_DIR/Dockerfile.sandbox-common" \
  || fail 'sandbox Dockerfile does not install Bun through the pinned archive helper'
grep -Fq 'scripts/installers/install-homebrew.sh' "$ROOT_DIR/Dockerfile.sandbox-common" \
  || fail 'sandbox Dockerfile does not use the verified Homebrew installer'
grep -Fq 'if [ "${INSTALL_BUN}" = "1" ]' "$ROOT_DIR/Dockerfile.sandbox-common" \
  || fail 'INSTALL_BUN=0 no longer skips the Bun download path'
grep -Fq 'if [ "${INSTALL_BREW}" = "1" ]' "$ROOT_DIR/Dockerfile.sandbox-common" \
  || fail 'INSTALL_BREW=0 no longer skips the Homebrew download path'
grep -Fq 'scripts/installers/install-bun.sh' "$ROOT_DIR/docs/install/docker.md" \
  || fail 'Docker docs snippet is not synchronized with the Bun helper'

echo 'OK: verified downloader offline tests'
