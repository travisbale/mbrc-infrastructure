# Frontend → Cloudflare Pages

The Vue SPA (the `web` repo) is served as static files from Cloudflare Pages — free,
edge-cached, and the layer that absorbs bot/static traffic before it can reach an origin.

## Recommended: git integration (auto-deploy)

Connect the `web` repo to Pages once in the Cloudflare dashboard, so every push builds
and deploys:

- **Framework preset:** Vue / Vite
- **Build command:** `npm run build`
- **Build output directory:** `dist`
- **Custom domains:** `manitobarydercup.com` and `www.manitobarydercup.com`

The app calls relative `/api/*` paths, so **no build-time API env vars are needed** — the
Worker in the web repo's `worker/` routes those to Cloud Run at the edge.

## Manual deploy

For a first deploy or an out-of-band one:

```bash
npm install            # once, for wrangler
PAGES_PROJECT=mbrc-web WEB_SRC=../../../web ./deploy.sh
```

## Included in the build (from web/public/)

- **`_redirects`** — SPA fallback (`/* /index.html 200`) so client-side routes resolve.
- **`_headers`** — `X-Robots-Tag: noindex …` to keep the private app out of search results.

## Domain + Worker coexistence

The Pages project owns `manitobarydercup.com`; the web repo's `worker/` Worker is bound to
`manitobarydercup.com/api/*` and runs in front of Pages for those paths only. Set the
Pages custom domain first, then deploy the Worker.
