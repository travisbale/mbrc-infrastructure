# mbrc-infrastructure

Deployment for the Manitoba Ryder Cup app. This branch replaces the previous single-EC2
setup (nginx + certbot + docker-compose, preserved on `master`) with a **serverless,
scale-to-zero** stack that idles at ~$0/month — appropriate for an app that's busy a few
days a year.

## Architecture

```
                    ┌─────────────────────────────┐
   internet ───────▶│      Cloudflare (edge)      │  WAF · Bot Fight · rate-limit · cache
                    └──────┬───────────────┬──────┘
                           │               │
              everything else         /api/auth/*  /api/scorecard/*
                           │               │
                    ┌──────▼──────┐   ┌─────▼─────────────────┐
                    │ Pages       │   │ Cloud Run (2 services)│  min=0, max=3
                    │ (Vue SPA)   │   │ heimdall + scorecard  │
                    └─────────────┘   └─────────┬─────────────┘
                                                │
                                          ┌─────▼─────┐
                                          │   Neon    │  serverless Postgres (autosuspend)
                                          └───────────┘
```

- **Frontend** — the Vue build on **Cloudflare Pages** (static, free, edge-cached).
- **APIs** — `scorecard` and `heimdall` on **Cloud Run** (containers, scale to zero).
- **Same-origin** — the SPA calls relative `/api/*`; a Cloudflare **Worker**
  (`cloudflare/api-proxy/`) routes those to Cloud Run, so there's no CORS and the Cloud
  Run URLs stay private. It mirrors the dev Vite proxy (prefix strip + refresh-cookie
  Path rewrite).
- **Database** — **Neon** serverless Postgres (free tier, sleeps when idle).

## Layout

| Path                     | What |
| ------------------------ | ---- |
| `cloudflare/api-proxy/`  | Worker routing `/api/*` → Cloud Run (`wrangler deploy`) |
| `gcp/scorecard/`         | scorecard → Cloud Run: secrets, migrations, deploy |
| `gcp/heimdall/`          | heimdall → Cloud Run *(todo)* |

## Deploy order (from scratch)

1. **Neon** — create a project; note the `scorecard` and `heimdall` connection strings.
2. **heimdall → Cloud Run** *(todo)* — it mints the JWT keypair; export the **public** key for scorecard.
3. **scorecard → Cloud Run** — `gcp/scorecard/` (secrets → migrate → deploy).
4. **Frontend → Pages** — connect the `web` repo; build `npm run build`, output `dist`; add `manitobarydercup.com`.
5. **API proxy** — set the Cloud Run URLs in `cloudflare/api-proxy/wrangler.toml`, `wrangler deploy`.
6. **Harden & cap cost** (below).

## Bot traffic & cost controls

- **Pages** absorbs all static/bot traffic at the edge for free — never hits an origin.
- **`--max-instances 3`** on each Cloud Run service bounds cost under any flood (worst
  case = 429s, not a bill). **`--min-instances 0`** keeps idle free.
- **Cloudflare**: enable **Bot Fight Mode** and a **rate-limit rule** on `/api/*`.
- **Harden ingress** *(todo)*: forward `X-Proxy-Secret` from the Worker and reject
  requests without it in the services (or front Cloud Run with a GCLB — pricier).
- **Budget alert**: `gcloud billing budgets create` at $5/$10 as a safety net.
```
gcloud billing budgets create --billing-account=<ACCT> \
  --display-name="mbrc" --budget-amount=10USD \
  --threshold-rule=percent=0.5 --threshold-rule=percent=1.0
```
