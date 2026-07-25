# API proxy (Cloudflare Worker)

Routes the SPA's same-origin API calls to the Cloud Run services:

| Request (browser)            | Upstream (Cloud Run)                 |
| ---------------------------- | ------------------------------------ |
| `/api/auth/*`                | `HEIMDALL_URL` + path (prefix stripped) |
| `/api/scorecard/*`           | `SCORECARD_URL` + path (prefix stripped) |
| everything else              | falls through to the Pages site      |

This mirrors the dev Vite proxy (`web/vite.config.ts`) so production behaves like local
dev, including rewriting heimdall's refresh-token cookie `Path` (`/v1/refresh` →
`/api/auth/v1/refresh`) — without that rewrite the browser never returns the cookie and
sessions can't refresh.

## Deploy

```bash
npm install
# 1. Set the upstream URLs in wrangler.toml [vars] to the deployed Cloud Run URLs.
# 2. (optional, when hardening) set the shared secret:
wrangler secret put PROXY_SECRET
# 3. Ship it:
npm run deploy
```

## Requirements / gotchas

- The `manitobarydercup.com` zone must be in this Cloudflare account, and the **Pages
  project must own the custom domain**. The Worker routes (`/api/*`) run in front of Pages
  for matching paths only.
- If a `/api/*` request ever returns the SPA's `index.html` instead of hitting the
  service, the Worker route isn't taking precedence — the reliable fallback is to move
  `src/index.ts` into the web repo as a Pages Function at `functions/api/[[path]].ts`
  (same logic, guaranteed to run on the Pages domain). Keeping it here as a Worker keeps
  all deploy code in the infrastructure repo, which is why it's the default.
- `PROXY_SECRET` is forwarded as `X-Proxy-Secret` and **enforced** by both services
  (knowhere's `RequireProxySecret` middleware): a request missing or mismatching it gets a
  403, except the health check. Set the **same** value here and in Secret Manager
  (`proxy-secret`) — a mismatch 403s all API traffic. Deploy the services with the secret
  set at the same time you set it on the Worker.
