# Доступ к OpenClaw UI через Tailscale

Полное руководство по безопасному доступу к OpenClaw Web UI
с любого устройства (ноутбук, телефон) без домена и без открытия портов.

---

## Зачем Tailscale?

OpenClaw gateway работает на `localhost:28789` — только внутри VPS.
Открывать этот порт в интернет **небезопасно**: нет TLS, нет авторизации.

**Tailscale** — это зашифрованная частная сеть (VPN-mesh) поверх интернета:
- Все устройства с вашим аккаунтом Tailscale видят друг друга как в локалке.
- Трафик зашифрован (WireGuard) от устройства до устройства.
- Сторонние сервисы/пользователи — не видят ничего.
- Не нужен домен, не нужен белый IP, не нужно проксировать через сервер.

Команда `tailscale serve` проксирует локальный HTTP-сервис (`localhost:28789`)
как HTTPS-эндпоинт внутри tailnet — с автоматическим TLS-сертификатом.

---

## Архитектура

```
Интернет
  ├── ❌ Нет доступа к VPS:28789 (порт закрыт в firewall)
  └── ✅ VPS в Tailscale tailnet (зашифрованный канал)

Ваши устройства (Tailscale установлен, вы вошли в свой аккаунт)
  └── HTTPS → ubuntu-opcl.tail******.ts.net:443
        └── tailscale serve (TLS termination, Let's Encrypt cert)
              └── HTTP → localhost:28789 (OpenClaw gateway, без изменений)
```

---

## Первоначальная настройка

### Шаг 1. Установить Tailscale на VPS

```bash
curl -fsSL https://tailscale.com/install.sh | sudo bash
```

### Шаг 2. Войти в Tailscale

```bash
sudo tailscale up
```

Команда выведет ссылку вида `https://login.tailscale.com/a/...`.
Откройте её в браузере и войдите в свой Tailscale-аккаунт.

После авторизации проверьте:

```bash
tailscale status
# Должны увидеть: ubuntu-opcl   100.X.X.X   linux   -
```

### Шаг 3. Включить доступ к OpenClaw UI

```bash
sudo scripts/tailscale_openclaw_ui_enable.sh
```

Скрипт выведет URL типа:
```
https://ubuntu-opcl.tail******.ts.net/__openclaw__/
```

### Шаг 4. Открыть в браузере

Откройте полученный URL на любом устройстве, где установлен Tailscale
и вы вошли в тот же аккаунт. OpenClaw UI должен открыться.

---

## Подключение нового устройства (ноутбук / телефон)

1. **Установить Tailscale** на устройство:
   - macOS/Windows: [tailscale.com/download](https://tailscale.com/download)
   - iOS/Android: из App Store / Play Store
   - Linux: `curl -fsSL https://tailscale.com/install.sh | bash && sudo tailscale up`

2. **Войти** в тот же Tailscale-аккаунт, что и на VPS.

3. **Открыть** в браузере URL из шага 3.

---

## Управление

### Найти URL

```bash
# Показать MagicDNS hostname и IP
tailscale status

# Показать что настроено в serve
tailscale serve status
```

### Включить/выключить доступ

```bash
# Включить
sudo scripts/tailscale_openclaw_ui_enable.sh

# Выключить (OpenClaw gateway продолжает работать на localhost)
sudo scripts/tailscale_openclaw_ui_disable.sh
```

### Проверить что OpenClaw доступен локально

```bash
curl -si http://localhost:28789/__openclaw__/ | head -5
```

---

## Безопасность

### Что защищает Tailscale

| Угроза | Статус |
|--------|--------|
| Посторонний в интернете открывает UI | ❌ Невозможно — порт закрыт |
| Трафик перехватывается в сети | ❌ Невозможно — WireGuard E2E |
| Чужой Tailscale-пользователь видит UI | По умолчанию — только если в вашем tailnet |

### ACL — ограничить доступ внутри tailnet

По умолчанию все устройства в tailnet видят друг друга. Для ограничения:

1. Откройте [login.tailscale.com](https://login.tailscale.com) → **Access Controls**.
2. Добавьте правила ACL. Пример — доступ к VPS только с конкретных тегов:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:personal"],
      "dst": ["tag:servers:*"]
    }
  ],
  "tagOwners": {
    "tag:personal": ["autogroup:member"],
    "tag:servers":  ["autogroup:member"]
  }
}
```

Назначьте VPS тег `tag:servers`, своим устройствам — `tag:personal` через
[Machines](https://login.tailscale.com/admin/machines) → Edit tags.

### Не использовать tailscale funnel

`tailscale funnel` делает сервис **публично доступным** в интернете.
В данной конфигурации используется `tailscale serve` — только для tailnet.

---

## Автозапуск

`tailscaled` и `tailscale up` автоматически запускаются при старте системы
(systemd unit `tailscaled.service`):

```bash
systemctl is-enabled tailscaled   # → enabled
systemctl status tailscaled
```

**Важно**: `tailscale serve` не сохраняется автоматически при перезапуске
системы в некоторых версиях. Если это нужно — включите скрипт как systemd unit
или добавьте в `ExecStartPost` сервиса tailscaled.

---

## Устранение проблем

| Симптом | Решение |
|---------|---------|
| URL недоступен | Проверьте `tailscale status` — VPS и устройство должны видеть друг друга |
| Ошибка TLS | Tailscale автоматически выпускает сертификат — подождите 1-2 минуты после первого включения |
| OpenClaw 502/504 | Проверьте что gateway запущен: `curl http://localhost:28789/__openclaw__/` |
| `tailscale serve` не работает | Убедитесь что запущен с sudo и tailscale авторизован |

---

## Связанные файлы

| Файл | Назначение |
|------|-----------|
| `scripts/tailscale_openclaw_ui_enable.sh` | Включить доступ через tailnet |
| `scripts/tailscale_openclaw_ui_disable.sh` | Выключить доступ |
| `scripts/TAILSCALE_OPENCLAW_UI.md` | Документация скриптов |
| `docs/REMOTE_UI_TAILSCALE.md` | Это руководство |
