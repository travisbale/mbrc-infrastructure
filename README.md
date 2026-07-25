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
| `cloudflare/pages/`      | Frontend → Cloudflare Pages (build + deploy) |
| `gcp/heimdall/`          | heimdall → Cloud Run: keys, secrets, migrations, deploy |
| `gcp/scorecard/`         | scorecard → Cloud Run: secrets, migrations, deploy |
| `gcp/ci/`                | GitHub OIDC setup for tag-triggered Cloud Run deploys |

## Deploy order (from scratch)

1. **Neon** — create a project; note the `scorecard` and `heimdall` connection strings.
2. **heimdall → Cloud Run** — `gcp/heimdall/` (keys → secrets → migrate → deploy). It owns the JWT keypair, so this creates the shared `jwt-public-key` secret scorecard needs.
3. **scorecard → Cloud Run** — `gcp/scorecard/` (secrets → migrate → deploy).
4. **Frontend → Pages** — `cloudflare/pages/` (connect the `web` repo; build `npm run build`, output `dist`; add `manitobarydercup.com`).
5. **API proxy** — set the Cloud Run URLs in `cloudflare/api-proxy/wrangler.toml`, `wrangler deploy`.
6. **Harden & cap cost** (below).
7. **CI/CD** — `gcp/ci/` sets up tag-triggered deploys; after the first manual deploy, `git push origin vX.Y.Z` ships a service.

## Bot traffic & cost controls

- **Pages** absorbs all static/bot traffic at the edge for free — never hits an origin.
- **`--max-instances 3`** on each Cloud Run service bounds cost under any flood (worst
  case = 429s, not a bill). **`--min-instances 0`** keeps idle free.
- **Cloudflare**: enable **Bot Fight Mode** and a **rate-limit rule** on `/api/*`.
- **Shared-secret ingress gate** (implemented): the Worker sends `X-Proxy-Secret` and both
  services enforce it (knowhere's `RequireProxySecret`), so a direct hit to a `run.app`
  URL — around Cloudflare — gets a 403 before touching the DB. Create the `proxy-secret`
  (heimdall bootstrap) and give the Worker the same value.
- **Budget alert**: `gcloud billing budgets create` at $5/$10 as a safety net.
```
gcloud billing budgets create --billing-account=<ACCT> \
  --display-name="mbrc" --budget-amount=10USD \
  --threshold-rule=percent=0.5 --threshold-rule=percent=1.0
```
