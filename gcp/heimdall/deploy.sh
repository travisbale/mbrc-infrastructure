#!/usr/bin/env bash
#
# Deploy heimdall (auth) to Cloud Run: HTTP on 8080, scale-to-zero, max 3 instances.
# heimdall also runs a gRPC listener on 9090 internally; Cloud Run only exposes the one
# HTTP port, which is all the SPA needs (scorecard verifies JWTs locally with the public
# key, so it doesn't call heimdall's gRPC).
#
# Deploys a prebuilt image from Artifact Registry, the same way release.yml does. Set
# IMAGE to pick a tag; without it, Cloud Build builds one from a local checkout instead.
#
#   GCP_PROJECT=my-proj IMAGE=…/mbrc/heimdall:bootstrap ./deploy.sh
#
set -euo pipefail

PROJECT="${GCP_PROJECT:?set GCP_PROJECT}"
REGION="${GCP_REGION:-us-central1}"
SERVICE="${SERVICE:-heimdall}"
SOURCE_DIR="${HEIMDALL_SRC:-../../../../travisbale/heimdall}"

if [[ -n "${IMAGE:-}" ]]; then
  BUILD_FROM=(--image "$IMAGE")
else
  BUILD_FROM=(--source "$SOURCE_DIR")
fi

# The environment, and set-env.sh's too — changing a variable on a running service is that
# script's job, not a re-run of this one.
source "$(dirname "$0")/env.sh"

DB_URL_SECRET="${DB_URL_SECRET:-heimdall-database-url}"
ENC_SECRET="${ENC_SECRET:-heimdall-encryption-key}"
JWT_PRIVATE_SECRET="${JWT_PRIVATE_SECRET:-jwt-private-key}"
JWT_PUBLIC_SECRET="${JWT_PUBLIC_SECRET:-jwt-public-key}"
PROXY_SECRET_NAME="${PROXY_SECRET_NAME:-proxy-secret}"

gcloud run deploy "$SERVICE" \
  --project "$PROJECT" \
  --region "$REGION" \
  "${BUILD_FROM[@]}" \
  --port 8080 \
  --cpu 1 \
  --memory 512Mi \
  --concurrency 80 \
  --timeout 60s \
  --min-instances 0 \
  --max-instances 3 \
  --allow-unauthenticated \
  --set-env-vars "$ENV_VARS" \
  --set-secrets "DATABASE_URL=${DB_URL_SECRET}:latest,ENCRYPTION_KEY=${ENC_SECRET}:latest,PROXY_SECRET=${PROXY_SECRET_NAME}:latest,/secrets/jwt-private/private.pem=${JWT_PRIVATE_SECRET}:latest,/secrets/jwt-public/public.pem=${JWT_PUBLIC_SECRET}:latest"

echo
echo "Deployed. Service URL:"
gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" \
  --format='value(status.url)'
echo "→ put that URL in the web repo's worker/wrangler.toml as HEIMDALL_URL."
