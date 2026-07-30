#!/usr/bin/env bash
#
# Deploy the scorecard API to Cloud Run with scale-to-zero and a capped max-instances so
# bot traffic can never run up an unbounded bill.
#
# Deploys a prebuilt image from Artifact Registry, the same way release.yml does. Set
# IMAGE to pick a tag; without it, Cloud Build builds one from a local checkout instead.
#
#   GCP_PROJECT=my-proj \
#   SCORECARD_PUBLIC_TENANT_ID=11111111-1111-1111-1111-111111111111 \
#   IMAGE=…/mbrc/scorecard:bootstrap \
#     ./deploy.sh
#
set -euo pipefail

PROJECT="${GCP_PROJECT:?set GCP_PROJECT}"
REGION="${GCP_REGION:-us-central1}"
SERVICE="${SERVICE:-scorecard}"

# Path to a checkout of the scorecard repo (built from source). Defaults to a sibling
# checkout next to this infrastructure repo.
SOURCE_DIR="${SCORECARD_SRC:-../../../scorecard}"

# The public single-tenant site: anonymous reads are scoped to this tenant so the
# leaderboard works without login. (Writes still require a heimdall JWT.)
PUBLIC_TENANT_ID="${SCORECARD_PUBLIC_TENANT_ID:?set SCORECARD_PUBLIC_TENANT_ID}"

DB_URL_SECRET="${DB_URL_SECRET:-scorecard-database-url}"
JWT_PUBKEY_SECRET="${JWT_PUBKEY_SECRET:-jwt-public-key}"
PROXY_SECRET_NAME="${PROXY_SECRET_NAME:-proxy-secret}"

if [[ -n "${IMAGE:-}" ]]; then
  BUILD_FROM=(--image "$IMAGE")
else
  BUILD_FROM=(--source "$SOURCE_DIR")
fi

gcloud run deploy "$SERVICE" \
  --project "$PROJECT" \
  --region "$REGION" \
  "${BUILD_FROM[@]}" \
  --port 5000 \
  --cpu 1 \
  --memory 512Mi \
  --concurrency 80 \
  --timeout 60s \
  --min-instances 0 \
  --max-instances 3 \
  --allow-unauthenticated \
  --set-env-vars "ENVIRONMENT=production,LOG_FORMAT=json,HTTP_ADDRESS=:5000,TRUSTED_PROXY_MODE=true,SCORECARD_PUBLIC_TENANT_ID=${PUBLIC_TENANT_ID},JWT_PUBLIC_KEY_PATH=/secrets/jwt/public.pem" \
  --set-secrets "DATABASE_URL=${DB_URL_SECRET}:latest,PROXY_SECRET=${PROXY_SECRET_NAME}:latest,/secrets/jwt/public.pem=${JWT_PUBKEY_SECRET}:latest"

echo
echo "Deployed. Service URL:"
gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" \
  --format='value(status.url)'
echo "→ put that URL in cloudflare/api-proxy/wrangler.toml as SCORECARD_URL."
