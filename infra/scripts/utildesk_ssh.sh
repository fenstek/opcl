#!/usr/bin/env bash
# /opt/openclaw/scripts/utildesk_ssh.sh
#
# Safe wrapper for OpenClaw agent → utildesk-openclaw SSH calls.
# Validates subcommand against allowlist before invoking SSH.
# Mounted into gateway container as /usr/local/bin/utildesk_ssh
#
# Usage (inside container):  utildesk_ssh <subcommand> [args]
# E.g.:                       utildesk_ssh status
#                              utildesk_ssh tail_log publish
#                              utildesk_ssh show_file CLAUDE.md

set -uo pipefail

SSH_KEY="/home/node/.ssh/id_ed25519_utildesk_openclaw"
SSH_HOST="46.224.94.65"
SSH_USER="openclaw"
SSH_OPTS="-i ${SSH_KEY} -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o BatchMode=yes"

# ── Allowlist ────────────────────────────────────────────────────────────────
ALLOWED=(
    status
    fetch
    diff
    branch_safe
    checkout_safe
    build
    audit_done_vs_repo
    audit_alternatives
    list_scripts
    show_file
    tail_log
)

# ── Usage ────────────────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
    printf 'usage: utildesk_ssh <subcommand> [args]\n'
    printf 'allowed: %s\n' "${ALLOWED[*]}"
    exit 1
fi

SUBCMD="$1"
shift
ARGS="${*:-}"

# ── Validate subcommand ──────────────────────────────────────────────────────
VALID=0
for cmd in "${ALLOWED[@]}"; do
    [[ "$SUBCMD" == "$cmd" ]] && VALID=1 && break
done

if [[ $VALID -eq 0 ]]; then
    printf '[utildesk_ssh] DENIED: unknown subcommand "%s"\n' "$SUBCMD" >&2
    printf 'allowed: %s\n' "${ALLOWED[*]}" >&2
    exit 1
fi

# ── Guard: no shell metacharacters ──────────────────────────────────────────
FULL="${SUBCMD}${ARGS:+ $ARGS}"
if printf '%s' "$FULL" | grep -qE '[;&|`$<>(){}\\!]'; then
    printf '[utildesk_ssh] DENIED: shell metacharacters in: %s\n' "$FULL" >&2
    exit 1
fi

# ── Execute via SSH forced-command ──────────────────────────────────────────
# The forced-command on utildesk (/usr/local/bin/utildesk_exec) reads
# SSH_ORIGINAL_COMMAND and dispatches accordingly.
if [[ -n "$ARGS" ]]; then
    exec ssh $SSH_OPTS "${SSH_USER}@${SSH_HOST}" "${SUBCMD} ${ARGS}"
else
    exec ssh $SSH_OPTS "${SSH_USER}@${SSH_HOST}" "${SUBCMD}"
fi
