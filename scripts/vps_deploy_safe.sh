#!/usr/bin/env bash
# =============================================================================
# vps_deploy_safe.sh — безопасный деплой openclaw fork на VPS
#
# Что делает:
#   1. Создаёт git-тег prod-before-upstream-YYYYMMDD-HHMM (rollback point)
#   2. git fetch --all --prune
#   3. git reset --hard <ref>
#   4. Определяет нужен ли restart контейнеров
#      (изменились ли Dockerfile / docker-compose / lockfiles)
#   5. Если restart нужен: docker compose up -d [--build] + healthcheck
#   6. Если healthcheck есть — запускает его
#   7. Печатает структурированный отчёт
#   8. Telegram-уведомление (если задан TELEGRAM_BOT_TOKEN)
#
# Использование:
#   scripts/vps_deploy_safe.sh [OPTIONS]
#
# Опции:
#   --app-dir DIR          путь к репозиторию (default: /opt/openclaw/app)
#   --ref REF              git ref для reset --hard (default: origin/main)
#   --healthcheck-script S путь к healthcheck-скрипту
#                          (default: /opt/openclaw/scripts/health_check_openclaw.sh)
#   --skip-restart         не перезапускать контейнеры даже при изменениях
#   --skip-healthcheck     пропустить healthcheck после restart
#   --dry-run              ничего не делать, только показать план
#   --help                 показать эту справку
#
# Переменные окружения (для Telegram):
#   TELEGRAM_BOT_TOKEN     токен бота (необязательно)
#   TELEGRAM_CHAT_ID       chat_id получателя (необязательно)
#
# Примеры:
#   # Стандартный деплой
#   scripts/vps_deploy_safe.sh
#
#   # Деплой конкретного тега
#   scripts/vps_deploy_safe.sh --ref v2026.2.14
#
#   # Dry-run: показать план без применения
#   scripts/vps_deploy_safe.sh --dry-run
#
#   # Деплой с Telegram-нотификацией
#   TELEGRAM_BOT_TOKEN=xxx TELEGRAM_CHAT_ID=yyy scripts/vps_deploy_safe.sh
#
# =============================================================================

set -uo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
APP_DIR="/opt/openclaw/app"
DEPLOY_REF="origin/main"
HEALTHCHECK_SCRIPT="/opt/openclaw/scripts/health_check_openclaw.sh"
SKIP_RESTART=0
SKIP_HEALTHCHECK=0
DRY_RUN=0

# Файлы, изменение которых требует restart/rebuild контейнеров
RESTART_TRIGGER_FILES=(
  "Dockerfile"
  "docker-compose.yml"
  "docker-compose.override.yml"
  "pnpm-lock.yaml"
  ".npmrc"
)
# Файлы, изменение которых требует именно --build (rebuild образа)
REBUILD_TRIGGER_FILES=(
  "Dockerfile"
  "pnpm-lock.yaml"
  ".npmrc"
)

# ── Helpers ───────────────────────────────────────────────────────────────────
TS()   { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log()  { printf '[%s] %s\n' "$(TS)" "$*"; }
info() { printf '[%s] INFO  %s\n' "$(TS)" "$*"; }
ok()   { printf '[%s] OK    %s\n' "$(TS)" "$*"; }
warn() { printf '[%s] WARN  %s\n' "$(TS)" "$*"; }
fail() { printf '[%s] ERROR %s\n' "$(TS)" "$*" >&2; }

hr() { printf '=%.0s' {1..56}; printf '\n'; }

die() {
  fail "$*"
  _telegram_notify "error" "❌ VPS Deploy ERROR: $*"
  exit 1
}

# ── Telegram ──────────────────────────────────────────────────────────────────
_telegram_notify() {
  local level="$1"; shift
  local text="$*"

  # Пропускаем если токен не задан
  [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]] && return 0

  curl -sS -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${text}" \
    -d "parse_mode=" \
    > /dev/null 2>&1 && true
  # Ошибки отправки не фатальны
}

# ── Аргументы ─────────────────────────────────────────────────────────────────
usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '1d'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-dir)            APP_DIR="$2"; shift 2 ;;
    --ref)                DEPLOY_REF="$2"; shift 2 ;;
    --healthcheck-script) HEALTHCHECK_SCRIPT="$2"; shift 2 ;;
    --skip-restart)       SKIP_RESTART=1; shift ;;
    --skip-healthcheck)   SKIP_HEALTHCHECK=1; shift ;;
    --dry-run)            DRY_RUN=1; shift ;;
    --help|-h)            usage ;;
    *) die "Unknown argument: $1" ;;
  esac
done

# ── Pre-flight ────────────────────────────────────────────────────────────────
[[ -d "$APP_DIR/.git" ]] || die "Not a git repository: $APP_DIR"
cd "$APP_DIR"

# ── Переменные результата ─────────────────────────────────────────────────────
REPORT_STATUS="unknown"
RESTART_NEEDED=0
BUILD_NEEDED=0
CHANGED_TRIGGER_FILES=()
HEALTHCHECK_RESULT="skipped"
OLD_REF=""
NEW_REF=""
TAG_NAME=""

# ── Шаг 1: Тег для rollback ──────────────────────────────────────────────────
hr
info "STEP 1 — Create rollback tag"
TAG_NAME="prod-before-upstream-$(date '+%Y%m%d-%H%M')"
OLD_REF=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

if [[ "$DRY_RUN" -eq 0 ]]; then
  if git tag "$TAG_NAME" 2>/dev/null; then
    ok "Tag created: $TAG_NAME (at ${OLD_REF:0:12})"
  else
    warn "Tag already exists or failed: $TAG_NAME"
  fi
else
  info "[DRY RUN] Would create tag: $TAG_NAME"
fi

# ── Шаг 2: Fetch ─────────────────────────────────────────────────────────────
hr
info "STEP 2 — git fetch --all --prune"
if [[ "$DRY_RUN" -eq 0 ]]; then
  GIT_TERMINAL_PROMPT=0 git fetch --all --prune 2>&1 | while IFS= read -r line; do
    info "  fetch: $line"
  done || die "git fetch failed"
  ok "Fetch complete"
else
  info "[DRY RUN] Would run: git fetch --all --prune"
fi

# ── Шаг 3: Определить ref ─────────────────────────────────────────────────────
hr
info "STEP 3 — Resolve ref: $DEPLOY_REF"
if ! RESOLVED_REF=$(git rev-parse --verify "$DEPLOY_REF" 2>/dev/null); then
  die "Cannot resolve ref: $DEPLOY_REF"
fi
info "  $DEPLOY_REF -> ${RESOLVED_REF:0:12}"

# ── Шаг 4: Определить нужен ли restart ──────────────────────────────────────
hr
info "STEP 4 — Check restart triggers"
if [[ "$OLD_REF" != "unknown" && "$OLD_REF" != "$RESOLVED_REF" ]]; then
  for f in "${RESTART_TRIGGER_FILES[@]}"; do
    if git diff --name-only "${OLD_REF}" "${RESOLVED_REF}" 2>/dev/null | grep -qF "$f"; then
      CHANGED_TRIGGER_FILES+=("$f")
      RESTART_NEEDED=1
      info "  CHANGED (restart trigger): $f"
    fi
  done
  for f in "${REBUILD_TRIGGER_FILES[@]}"; do
    if [[ " ${CHANGED_TRIGGER_FILES[*]} " == *" $f "* ]]; then
      BUILD_NEEDED=1
    fi
  done
else
  info "  Same ref — checking all trigger files as potentially changed"
  RESTART_NEEDED=0
fi

if [[ "$RESTART_NEEDED" -eq 0 ]]; then
  ok "No restart trigger files changed"
else
  ok "Restart needed (changed: ${CHANGED_TRIGGER_FILES[*]})"
  [[ "$BUILD_NEEDED" -eq 1 ]] && ok "Rebuild needed (Dockerfile or lockfile changed)"
fi

# ── Шаг 5: git reset --hard ──────────────────────────────────────────────────
hr
info "STEP 5 — git reset --hard $DEPLOY_REF"
if [[ "$DRY_RUN" -eq 0 ]]; then
  git reset --hard "$RESOLVED_REF" 2>&1 | while IFS= read -r line; do
    info "  $line"
  done || die "git reset --hard failed"
  NEW_REF=$(git rev-parse HEAD)
  ok "Reset to ${NEW_REF:0:12}"
else
  NEW_REF="$RESOLVED_REF"
  info "[DRY RUN] Would run: git reset --hard $RESOLVED_REF"
fi

# ── Шаг 6: Docker restart (если нужен) ───────────────────────────────────────
hr
info "STEP 6 — Docker compose"
if [[ "$SKIP_RESTART" -eq 1 ]]; then
  info "  Skipped (--skip-restart)"
elif [[ "$RESTART_NEEDED" -eq 0 ]]; then
  ok "No restart required"
else
  if [[ "$DRY_RUN" -eq 0 ]]; then
    if [[ "$BUILD_NEEDED" -eq 1 ]]; then
      info "  Running: docker compose up -d --build"
      docker compose up -d --build 2>&1 | while IFS= read -r line; do
        info "  compose: $line"
      done || die "docker compose up --build failed"
    else
      info "  Running: docker compose up -d"
      docker compose up -d 2>&1 | while IFS= read -r line; do
        info "  compose: $line"
      done || die "docker compose up failed"
    fi
    ok "Docker compose restarted"
  else
    local_cmd="docker compose up -d"
    [[ "$BUILD_NEEDED" -eq 1 ]] && local_cmd="docker compose up -d --build"
    info "[DRY RUN] Would run: $local_cmd"
  fi
fi

# ── Шаг 7: Healthcheck ───────────────────────────────────────────────────────
hr
info "STEP 7 — Healthcheck"
if [[ "$SKIP_HEALTHCHECK" -eq 1 ]]; then
  info "  Skipped (--skip-healthcheck)"
  HEALTHCHECK_RESULT="skipped"
elif [[ "$RESTART_NEEDED" -eq 0 && "$SKIP_RESTART" -eq 0 ]]; then
  info "  Skipped (no restart was performed)"
  HEALTHCHECK_RESULT="skipped"
elif [[ ! -x "$HEALTHCHECK_SCRIPT" ]]; then
  warn "  Healthcheck script not found or not executable: $HEALTHCHECK_SCRIPT"
  HEALTHCHECK_RESULT="skipped"
elif [[ "$DRY_RUN" -eq 0 ]]; then
  info "  Running: $HEALTHCHECK_SCRIPT"
  # Небольшая пауза — дать контейнеру время запуститься
  sleep 5
  if "$HEALTHCHECK_SCRIPT" 2>&1 | while IFS= read -r line; do
       info "  hc: $line"
     done; then
    ok "Healthcheck PASSED"
    HEALTHCHECK_RESULT="pass"
  else
    warn "Healthcheck FAILED — check logs"
    HEALTHCHECK_RESULT="fail"
    REPORT_STATUS="warn"
  fi
else
  info "[DRY RUN] Would run: $HEALTHCHECK_SCRIPT"
  HEALTHCHECK_RESULT="skipped"
fi

# ── Шаг 8: Отчёт ─────────────────────────────────────────────────────────────
[[ "$REPORT_STATUS" == "unknown" ]] && REPORT_STATUS="ok"
hr
printf '\n'
printf '  UPSTREAM SYNC REPORT -- %s\n' "$(date -u '+%Y-%m-%d %H:%M UTC')"
hr
printf '  %-24s %s\n' "Status:"         "$( [[ "$DRY_RUN" -eq 1 ]] && echo "DRY RUN" || echo "$REPORT_STATUS" )"
printf '  %-24s %s\n' "App dir:"        "$APP_DIR"
printf '  %-24s %s\n' "Deploy ref:"     "$DEPLOY_REF"
printf '  %-24s %s\n' "Previous HEAD:"  "${OLD_REF:0:12}"
printf '  %-24s %s\n' "New HEAD:"       "${NEW_REF:0:12}"
printf '  %-24s %s\n' "Rollback tag:"   "${TAG_NAME:-none}"
printf '  %-24s %s\n' "Restart needed:" "$( [[ "$RESTART_NEEDED" -eq 1 ]] && echo "YES (${CHANGED_TRIGGER_FILES[*]:-})" || echo "no" )"
printf '  %-24s %s\n' "Rebuild needed:" "$( [[ "$BUILD_NEEDED" -eq 1 ]] && echo "YES" || echo "no" )"
printf '  %-24s %s\n' "Healthcheck:"    "$HEALTHCHECK_RESULT"
hr
printf '\n'

# ── Telegram-нотификация ──────────────────────────────────────────────────────
if [[ "$DRY_RUN" -eq 0 ]]; then
  HC_EMOJI=""
  case "$HEALTHCHECK_RESULT" in
    pass)    HC_EMOJI=" | healthcheck OK" ;;
    fail)    HC_EMOJI=" | healthcheck FAILED" ;;
    skipped) HC_EMOJI="" ;;
  esac

  if [[ "$REPORT_STATUS" == "ok" ]]; then
    _telegram_notify "info" \
      "🚀 VPS Deploy OK ($(date -u '+%Y-%m-%d %H:%M UTC'))
HEAD: ${NEW_REF:0:12}${HC_EMOJI}
Rollback: $TAG_NAME"
  else
    _telegram_notify "warn" \
      "⚠️ VPS Deploy WARNING ($(date -u '+%Y-%m-%d %H:%M UTC'))
HEAD: ${NEW_REF:0:12} | status: $REPORT_STATUS
Check: docker compose ps && $HEALTHCHECK_SCRIPT"
  fi
fi

# Выход с кодом согласно статусу healthcheck
[[ "$HEALTHCHECK_RESULT" == "fail" ]] && exit 2
exit 0
