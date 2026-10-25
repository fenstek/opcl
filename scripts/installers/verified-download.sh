#!/usr/bin/env bash

# Shared download boundary for installer scripts and versioned binary archives.
# This file is sourced; callers must use the helpers below rather than piping
# network responses to a shell.

openclaw_verified_known_sha256() {
  case "${1-}" in
    https://openclaw.ai/install.sh|https://openclaw.bot/install.sh)
      printf '%s\n' '5ba2d16e2b89eab7e4d6f96f1348d867c43307309e829841a78fc8820956dd0c'
      ;;
    https://openclaw.ai/install-cli.sh|https://openclaw.bot/install-cli.sh)
      printf '%s\n' '7ad6910e76cf692eb60bed987a26637548cc5363164031ddf6ffec480ae1458b'
      ;;
    https://raw.githubusercontent.com/Homebrew/install/85d1a3fc80d8a63932f632aca8f787de11d14a64/install.sh)
      printf '%s\n' '5f333bbe53bc490e51e7ccb1df8779b3dd6ee73a1a7379efda216edb08ccb148'
      ;;
    *)
      return 1
      ;;
  esac
}

openclaw_bun_release_for_arch() {
  case "${1-}" in
    amd64|x86_64|x64)
      OPENCLAW_BUN_ARCHIVE_URL='https://github.com/oven-sh/bun/releases/download/bun-v1.4.4/bun-linux-x64.zip'
      OPENCLAW_BUN_ARCHIVE_SHA256='bf8ccbfb2b0b80159e0f9a6d15c55317add8077534dbc6130a3edb52fccb395c'
      OPENCLAW_BUN_ARCHIVE_DIR='bun-linux-x64'
      ;;
    arm64|aarch64)
      OPENCLAW_BUN_ARCHIVE_URL='https://github.com/oven-sh/bun/releases/download/bun-v1.4.4/bun-linux-aarch64.zip'
      OPENCLAW_BUN_ARCHIVE_SHA256='baa6bb36f51d6e58561e02bbea825038a9df454f673d6d776e8bbf86f8c7850e'
      OPENCLAW_BUN_ARCHIVE_DIR='bun-linux-aarch64'
      ;;
    *)
      printf 'Unsupported Bun architecture: %s\n' "${1-}" >&2
      return 1
      ;;
  esac
}

openclaw_verified_validate_url() {
  local url="${1-}"
  if [[ "$url" != https://* || "$url" =~ [[:space:][:cntrl:]] ]]; then
    echo 'Installer URL must be an absolute HTTPS URL without whitespace or control characters.' >&2
    return 1
  fi
}

openclaw_download_verified() {
  if (($# != 3)); then
    echo 'Usage: openclaw_download_verified URL SHA256 DESTINATION' >&2
    return 2
  fi

  local url="$1"
  local requested_sha256="$2"
  local destination="$3"
  local expected_sha256 actual_sha256

  openclaw_verified_validate_url "$url" || return 1
  if [[ -n "$requested_sha256" ]]; then
    expected_sha256="$requested_sha256"
  elif ! expected_sha256="$(openclaw_verified_known_sha256 "$url")"; then
    echo 'A SHA256 pin is required for this installer URL.' >&2
    return 1
  fi
  if [[ ! "$expected_sha256" =~ ^[[:xdigit:]]{64}$ ]]; then
    echo 'Installer SHA256 must contain exactly 64 hexadecimal characters.' >&2
    return 1
  fi
  expected_sha256="${expected_sha256,,}"
  if [[ -z "$destination" || -d "$destination" ]]; then
    echo 'Download destination must be a file path.' >&2
    return 2
  fi

  if ! curl --silent --show-error --fail --location --max-redirs 5 \
    --proto '=https' --proto-redir '=https' --tlsv1.2 --globoff \
    --output "$destination" -- "$url"; then
    rm -f -- "$destination"
    echo 'Verified download failed before execution.' >&2
    return 1
  fi

  if ! actual_sha256="$(sha256sum -- "$destination")"; then
    rm -f -- "$destination"
    echo 'Unable to calculate downloaded file SHA256.' >&2
    return 1
  fi
  actual_sha256="${actual_sha256%% *}"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    rm -f -- "$destination"
    echo 'Downloaded file SHA256 does not match its trusted pin.' >&2
    return 1
  fi
}

openclaw_run_verified_installer() {
  if (($# < 2)); then
    echo 'Usage: openclaw_run_verified_installer URL SHA256 [ARG ...]' >&2
    return 2
  fi

  local url="$1"
  local requested_sha256="$2"
  shift 2

  (
    umask 077
    local temp_dir
    temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/openclaw-installer.XXXXXXXX")" || exit 1
    trap 'rm -rf -- "$temp_dir"' EXIT HUP INT TERM
    if ! openclaw_download_verified "$url" "$requested_sha256" "$temp_dir/installer.sh"; then
      exit 1
    fi
    /bin/bash "$temp_dir/installer.sh" "$@"
  )
}
