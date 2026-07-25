#!/usr/bin/env bash
#
# Deploy heimdall (auth) to Cloud Run: HTTP on 8080, scale-to-zero, max 3 instances.
# heimdall also runs a gRPC listener on 9090 internally; Cloud Run only exposes the one
# HTTP port, which is all the SPA needs (scorecard verifies JWTs locally with the public
# key, so it doesn't call heimdall's gRPC).
#
#   GCP_PROJECT=my-proj ./deploy.sh
#
set -euo pipefail

PROJECT="${GCP_PROJECT:?set GCP_PROJECT}"
REGION="${GCP_REGION:-us-central1}"
SERVICE="${SERVICE:-heimdall}"
SOURCE_DIR="${HEIMDALL_SRC:-../../../../travisbale/heimdall}"

# The SPA origin(s). PUBLIC_URL is the *frontend* base — heimdall builds the password-reset
# and email-verification links users click from it.
PUBLIC_URL="${PUBLIC_URL:-https://manitobarydercup.com}"
CORS_ORIGINS="${CORS_ORIGINS:-https://manitobarydercup.com,https://www.manitobarydercup.com}"

DB_URL_SECRET="${DB_URL_SECRET:-heimdall-database-url}"
ENC_SECRET="${ENC_SECRET:-heimdall-encryption-key}"
JWT_PRIVATE_SECRET="${JWT_PRIVATE_SECRET:-jwt-private-key}"
JWT_PUBLIC_SECRET="${JWT_PUBLIC_SECRET:-jwt-public-key}"

# `^@^` makes @ the delimiter between vars, so CORS_ALLOWED_ORIGINS can contain commas.
gcloud run deploy "$SERVICE" \
  --project "$PROJECT" \
  --region "$REGION" \
  --source "$SOURCE_DIR" \
  --port 8080 \
  --cpu 1 \
  --memory 512Mi \
  --concurrency 80 \
  --timeout 60s \
  --min-instances 0 \
  --max-instances 3 \
  --allow-unauthenticated \
  --set-env-vars "^@^ENVIRONMENT=production@LOG_FORMAT=json@HTTP_ADDRESS=:8080@PUBLIC_URL=${PUBLIC_URL}@TRUSTED_PROXY_MODE=true@CORS_ALLOWED_ORIGINS=${CORS_ORIGINS}@JWT_PRIVATE_KEY_PATH=/secrets/jwt/private.pem@JWT_PUBLIC_KEY_PATH=/secrets/jwt/public.pem" \
  --set-secrets "DATABASE_URL=${DB_URL_SECRET}:latest,ENCRYPTION_KEY=${ENC_SECRET}:latest,/secrets/jwt/private.pem=${JWT_PRIVATE_SECRET}:latest,/secrets/jwt/public.pem=${JWT_PUBLIC_SECRET}:latest"

echo
echo "Deployed. Service URL:"
gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" \
  --format='value(status.url)'
echo "→ put that URL in cloudflare/api-proxy/wrangler.toml as HEIMDALL_URL."
