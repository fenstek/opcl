# tailscale_openclaw_ui_enable.sh / tailscale_openclaw_ui_disable.sh

Скрипты управления доступом к OpenClaw UI через Tailscale внутри tailnet.

---

## Что делают скрипты

| Скрипт | Действие |
|--------|----------|
| `tailscale_openclaw_ui_enable.sh` | Включает `tailscale serve` — OpenClaw UI становится доступен по HTTPS внутри tailnet |
| `tailscale_openclaw_ui_disable.sh` | Выключает `tailscale serve` — доступ закрывается |

**Порты наружу не открываются** — это фундаментальное свойство `tailscale serve`
(в отличие от `tailscale funnel`, который открывает публичный доступ).

---

## Использование

```bash
# Включить доступ (нужен sudo для tailscale serve)
sudo scripts/tailscale_openclaw_ui_enable.sh

# Отключить доступ
sudo scripts/tailscale_openclaw_ui_disable.sh

# Показать текущий URL и статус
tailscale serve status
tailscale status
```

### Параметры enable-скрипта

| Параметр | Default | Описание |
|----------|---------|----------|
| `--path PATH` | `/` | URL-путь для serve (например `/__openclaw__`) |
| `--help` | — | Показать справку |

```bash
# Serve только под конкретным путём
sudo scripts/tailscale_openclaw_ui_enable.sh --path /__openclaw__
```

---

## Как работает

```
Браузер (ноутбук/телефон в tailnet)
  └── HTTPS → <hostname>.ts.net:443
        └── tailscale serve (TLS termination на VPS)
              └── HTTP → localhost:28789 (OpenClaw gateway)
```

- TLS-сертификат выпускается автоматически Tailscale (Let's Encrypt через Tailscale CA).
- Снаружи (без Tailscale) — порт закрыт, доступ невозможен.
- `tailscale serve` ≠ `tailscale funnel`: serve — только для устройств в вашем tailnet.

---

## Требования

- Tailscale установлен и авторизован: `tailscale status`
- OpenClaw gateway работает: `curl -s http://localhost:28789/__openclaw__/ | head -5`
- Второе устройство добавлено в тот же tailnet

---

## Примеры вывода

```
==========================================
  OpenClaw UI через Tailscale: ВКЛЮЧЁН
==========================================
  URL:  https://ubuntu-opcl.tailXXXXX.ts.net/__openclaw__/
  Host: ubuntu-opcl.tailXXXXX.ts.net
==========================================
```
