# vps_deploy_safe.sh

Безопасный деплой fork-репозитория `fenstek/opcl` на VPS.
Обычно запускается автоматически из [`.github/workflows/upstream-sync.yml`](../.github/workflows/upstream-sync.yml)
через SSH, или вручную после `git pull`.

---

## Что делает скрипт

| Шаг | Действие |
|-----|----------|
| 1 | Создаёт git-тег `prod-before-upstream-YYYYMMDD-HHMM` — точка отката |
| 2 | `git fetch --all --prune` |
| 3 | Разрешает указанный ref в SHA |
| 4 | Сравнивает предыдущий и новый коммит: определяет, нужен ли restart |
| 5 | `git reset --hard <ref>` |
| 6 | Если нужен restart: `docker compose up -d` (или `--build` при изменении Dockerfile/lockfile) |
| 7 | Запускает healthcheck-скрипт (если есть) |
| 8 | Печатает структурированный отчёт |
| 9 | Отправляет Telegram-уведомление (если задан `TELEGRAM_BOT_TOKEN`) |

### Файлы-триггеры рестарта

```
Dockerfile
docker-compose.yml
docker-compose.override.yml
pnpm-lock.yaml
.npmrc
```

Если изменился `Dockerfile`, `pnpm-lock.yaml` или `.npmrc` — дополнительно добавляется флаг `--build`.

---

## Параметры

| Параметр | Default | Описание |
|----------|---------|----------|
| `--app-dir DIR` | `/opt/openclaw/app` | Путь к git-репозиторию |
| `--ref REF` | `origin/main` | Git ref для `reset --hard` |
| `--healthcheck-script S` | `/opt/openclaw/scripts/health_check_openclaw.sh` | Путь к healthcheck |
| `--skip-restart` | — | Не перезапускать контейнеры |
| `--skip-healthcheck` | — | Пропустить healthcheck |
| `--dry-run` | — | Показать план без применения |
| `--help` | — | Показать справку |

### Переменные окружения

| Переменная | Описание |
|------------|----------|
| `TELEGRAM_BOT_TOKEN` | Токен Telegram-бота (необязательно) |
| `TELEGRAM_CHAT_ID` | chat_id получателя (необязательно) |

---

## Примеры запуска

```bash
# Стандартный деплой с origin/main
scripts/vps_deploy_safe.sh

# Dry-run: показать план без применения
scripts/vps_deploy_safe.sh --dry-run

# Деплой конкретного тега или commit SHA
scripts/vps_deploy_safe.sh --ref v2026.2.14
scripts/vps_deploy_safe.sh --ref af549e89f9

# Деплой с кастомными путями
scripts/vps_deploy_safe.sh \
  --app-dir /opt/openclaw/app \
  --ref origin/main \
  --healthcheck-script /opt/openclaw/scripts/health_check_openclaw.sh

# Деплой с Telegram-нотификацией
TELEGRAM_BOT_TOKEN=1234567890:AAAA... \
TELEGRAM_CHAT_ID=-1001234567890 \
scripts/vps_deploy_safe.sh

# Пропустить рестарт (только обновить код)
scripts/vps_deploy_safe.sh --skip-restart

# Пропустить healthcheck
scripts/vps_deploy_safe.sh --skip-healthcheck
```

---

## Пример вывода

```
========================================================
[2026-02-27T20:00:00Z] INFO  STEP 1 — Create rollback tag
[2026-02-27T20:00:00Z] OK    Tag created: prod-before-upstream-20260227-2000 (at d6fd61fc11)

[2026-02-27T20:00:00Z] INFO  STEP 2 — git fetch --all --prune
[2026-02-27T20:00:01Z] OK    Fetch complete

[2026-02-27T20:00:01Z] INFO  STEP 3 — Resolve ref: origin/main
[2026-02-27T20:00:01Z] INFO    origin/main -> abc123def456

[2026-02-27T20:00:01Z] INFO  STEP 4 — Check restart triggers
[2026-02-27T20:00:01Z] INFO    CHANGED (restart trigger): docker-compose.yml
[2026-02-27T20:00:01Z] OK    Restart needed (changed: docker-compose.yml)

[2026-02-27T20:00:01Z] INFO  STEP 5 — git reset --hard origin/main
[2026-02-27T20:00:01Z] OK    Reset to abc123def456

[2026-02-27T20:00:01Z] INFO  STEP 6 — Docker compose
[2026-02-27T20:00:05Z] OK    Docker compose restarted

[2026-02-27T20:00:05Z] INFO  STEP 7 — Healthcheck
[2026-02-27T20:00:10Z] OK    Healthcheck PASSED

  UPSTREAM SYNC REPORT -- 2026-02-27 20:00 UTC
========================================================
  Status:                  ok
  App dir:                 /opt/openclaw/app
  Deploy ref:              origin/main
  Previous HEAD:           d6fd61fc11
  New HEAD:                abc123def456
  Rollback tag:            prod-before-upstream-20260227-2000
  Restart needed:          YES (docker-compose.yml)
  Rebuild needed:          no
  Healthcheck:             pass
========================================================
```

---

## Откат

```bash
# Посмотреть доступные теги отката
git tag -l 'prod-before-*' | sort -r | head -5

# Откатиться
scripts/vps_deploy_safe.sh --ref prod-before-upstream-20260227-2000

# Или вручную
git reset --hard prod-before-upstream-20260227-2000
docker compose up -d
```

---

## Безопасность

- **Секреты не логируются**: скрипт работает с git и docker, токены читаются из env.
- **`.env` не трогается**: только `git fetch` / `git reset --hard` + `docker compose`.
- **Rollback tag**: создаётся до любых изменений — можно откатиться даже при ошибке.
- **`--force-with-lease`**: используется в CI (upstream-sync.yml) при push, не здесь.
- **`--dry-run`**: всегда безопасно запустить перед реальным деплоем.

---

## Интеграция с CI/CD

> **Деплой теперь триггерится после merge PR или вручную через `workflow_dispatch`.**

`vps_deploy_safe.sh` вызывается автоматически из [`vps-deploy.yml`](../.github/workflows/vps-deploy.yml):
- при **push в main** (если изменились не только docs/markdown)
- при **ручном запуске** через `workflow_dispatch` с опциональным `ref`

Secrets: `VPS_SSH_KEY`, `VPS_HOST`, `VPS_USER` в Settings → Secrets → Actions.

```
GitHub Actions (vps-deploy.yml)
  └── push→main | workflow_dispatch
        └── SSH → VPS
              └── scripts/vps_deploy_safe.sh --app-dir /opt/openclaw/app --ref origin/main
```

upstream-sync.yml работает отдельно: создаёт ветку `sync/upstream-YYYYMMDD-<sha>`,
делает rebase, открывает PR — но **не деплоит напрямую**.
После merge PR триггерится vps-deploy.yml.

### Настройка автодеплоя

1. Создать SSH-ключ для деплоя:
   ```bash
   ssh-keygen -t ed25519 -C "github-deploy" -f ~/.ssh/github_deploy
   cat ~/.ssh/github_deploy.pub >> ~/.ssh/authorized_keys
   ```

2. Добавить в GitHub Secrets (`Settings → Secrets → Actions`):
   - `VPS_SSH_KEY` — содержимое `~/.ssh/github_deploy` (приватный ключ)
   - `VPS_HOST` — IP или hostname VPS
   - `VPS_USER` — пользователь (`opcl`)

3. Убедиться что скрипт исполняемый:
   ```bash
   chmod +x /opt/openclaw/app/scripts/vps_deploy_safe.sh
   ```
