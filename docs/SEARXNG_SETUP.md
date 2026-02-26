# SearxNG Self-Hosted Web Search — Setup Notes

## What's Running

| Service  | Image                   | Container     | Network        |
|----------|-------------------------|---------------|----------------|
| SearxNG  | `searxng/searxng:latest`| `searxng`     | `openclaw-tools` |
| Redis    | `redis:7-alpine`        | `searxng-redis` | `openclaw-tools` |

The `openclaw-tools` Docker bridge network (`172.20.0.0/16`) is shared between
the SearxNG stack and the OpenClaw gateway container, enabling internal DNS
resolution (`searxng:8080`).

## File Locations

| Path                        | Purpose                              |
|-----------------------------|--------------------------------------|
| `/opt/searxng/docker-compose.yml`     | SearxNG + Redis compose stack |
| `/opt/searxng/searxng/settings.yml`  | SearxNG instance config (format: json, limiter: false) |
| `/opt/openclaw/app/docker-compose.override.yml` | Gateway: browser build arg, SearxNG env, shared network |
| `/opt/openclaw/app/.env`             | `SEARXNG_BASE_URL=http://searxng:8080` |
| `/opt/openclaw/state/openclaw.json`  | `tools.web.search.provider = "searxng"` |

## Required Environment Variables

```
# /opt/openclaw/app/.env
SEARXNG_BASE_URL=http://searxng:8080
```

The gateway also accepts `SEARXNG_API_KEY` (optional) if SearxNG is configured
with HTTP Basic/token auth.

Runtime config (`openclaw.json`) — provider selection:

```json
{
  "tools": {
    "web": {
      "search": {
        "provider": "searxng"
      }
    }
  }
}
```

## Code Changes (web-search.ts patch)

The following files were patched to add SearxNG as a native provider:

- `src/agents/tools/web-search.ts` — new `SearxNGConfig/Result/Response` types,
  `SEARXNG_SEARCH_PATH` constant, provider detection, `runWebSearch` dispatch,
  and `resolveSearxNGConfig/BaseUrl/ApiKey` helpers
- `src/config/types.tools.ts` — added `"searxng"` to `provider` union type
- `src/config/zod-schema.agent-runtime.ts` — added `z.literal("searxng")` to
  runtime Zod schema and `searxng: { baseUrl?, apiKey? }` sub-object
- `docker-compose.yml` — ports moved to `docker-compose.override.yml`
- `docker-compose.override.yml` (new) — browser build arg, SearxNG env,
  `openclaw-tools` network attachment

## How to Verify

### 1. SearxNG health + JSON search

```bash
# From host (port mapped to localhost:28888)
curl -s "http://127.0.0.1:28888/search?q=test&format=json" | python3 -c \
  "import json,sys; d=json.load(sys.stdin); print(f'results: {len(d[\"results\"])} hits')"

# From inside the gateway container
docker exec app-openclaw-gateway-1 \
  sh -c 'curl -s "http://searxng:8080/search?q=openclaw&format=json" | head -c 200'
```

### 2. OpenClaw agent smoke test

```bash
docker exec \
  -e OPENCLAW_GATEWAY_TOKEN="$(grep OPENCLAW_GATEWAY_TOKEN /opt/openclaw/app/.env | cut -d= -f2)" \
  app-openclaw-gateway-1 \
  /app/openclaw.mjs agent --agent main \
    --message 'Use web_search to search for "SearxNG self-hosted" and give me the top 2 results' \
    --json 2>&1 | python3 -c \
  "import json,sys; d=json.load(sys.stdin); print(d['result']['payloads'][0]['text'])"
```

### 3. Confirm provider in live config

```bash
docker exec app-openclaw-gateway-1 \
  -e OPENCLAW_GATEWAY_TOKEN="..." \
  /app/openclaw.mjs config get tools.web.search.provider
```

## How to Restart

### Restart SearxNG only

```bash
cd /opt/searxng && docker compose restart
```

### Restart OpenClaw gateway only

```bash
cd /opt/openclaw/app && docker compose restart openclaw-gateway
```

### Full restart (SearxNG → then gateway)

```bash
cd /opt/searxng && docker compose up -d
cd /opt/openclaw/app && docker compose up -d
```

### After rebuilding the gateway image

```bash
cd /opt/openclaw/app
docker compose build openclaw-gateway
docker compose up -d openclaw-gateway
```

## How to Update SearxNG Settings

```bash
sudo nano /opt/searxng/searxng/settings.yml
cd /opt/searxng && docker compose restart searxng
```

Key settings in `settings.yml`:
- `search.formats: [html, json]` — must include `json`
- `server.limiter: false` — disable rate limiter for internal use
- `server.public_instance: false`

## Network Topology

```
┌─────────────────────────────────────────────────────────┐
│  Docker bridge: openclaw-tools  (172.20.0.0/16)         │
│                                                          │
│  redis          172.20.0.2   redis://redis:6379/0        │
│  searxng        172.20.0.3   http://searxng:8080         │
│  gateway        172.20.0.4   ws://127.0.0.1:28789 (host)│
└─────────────────────────────────────────────────────────┘

Host ports (127.0.0.1 only):
  28789 → gateway WS
  28790 → browser control
  28888 → SearxNG HTTP (for local testing)
```
