#!/usr/bin/env bash
#
# Build the Vue app and upload it to Cloudflare Pages. For ongoing deploys, prefer
# connecting the web repo to Pages in the dashboard (auto-build on push) — see README.md.
# This script is for the first deploy or a manual out-of-band one.
#
#   PAGES_PROJECT=mbrc-web ./deploy.sh
#
set -euo pipefail

WEB_SRC="${WEB_SRC:-../../../web}"
PROJECT="${PAGES_PROJECT:-mbrc-web}"

( cd "$WEB_SRC" && npm ci && npm run build )

npx wrangler pages deploy "$WEB_SRC/dist" --project-name "$PROJECT"
