#!/usr/bin/env bash
#
# Create heimdall's Secret Manager secrets, including the shared JWT keypair (heimdall is
# the token issuer, so it owns both the private and public keys; scorecard reads the
# public one). Run generate-jwt-keys.sh first.
#
#   GCP_PROJECT=my-proj \
#   HEIMDALL_DATABASE_URL='postgres://…neon.tech/heimdall?sslmode=require' \
#     ./bootstrap-secrets.sh
#
set -euo pipefail

PROJECT="${GCP_PROJECT:?set GCP_PROJECT}"
DB_URL="${HEIMDALL_DATABASE_URL:?set HEIMDALL_DATABASE_URL (the Neon connection string)}"
KEYS_DIR="${KEYS_DIR:-./keys}"

DB_URL_SECRET="${DB_URL_SECRET:-heimdall-database-url}"
ENC_SECRET="${ENC_SECRET:-heimdall-encryption-key}"
JWT_PRIVATE_SECRET="${JWT_PRIVATE_SECRET:-jwt-private-key}"
JWT_PUBLIC_SECRET="${JWT_PUBLIC_SECRET:-jwt-public-key}"
# Shared with scorecard and with the Cloudflare Worker (the edge sets this header; both
# services require it). Owned here since heimdall bootstraps first.
PROXY_SECRET_NAME="${PROXY_SECRET_NAME:-proxy-secret}"

secret_exists() { gcloud secrets describe "$1" --project "$PROJECT" >/dev/null 2>&1; }

# Add a new version, creating the secret first if needed. "$@" is the value producer.
create_or_update() {
  local name="$1"; shift
  secret_exists "$name" || gcloud secrets create "$name" --project "$PROJECT" --replication-policy=automatic
  "$@" | gcloud secrets versions add "$name" --project "$PROJECT" --data-file=-
}

create_or_update "$DB_URL_SECRET"     printf %s "$DB_URL"
create_or_update "$JWT_PRIVATE_SECRET" cat "$KEYS_DIR/jwt-private.pem"
create_or_update "$JWT_PUBLIC_SECRET"  cat "$KEYS_DIR/jwt-public.pem"

# `openssl rand -hex` ends its output with a newline, which would be stored as part of the
# secret. heimdall hex-decodes ENCRYPTION_KEY and would refuse to start; PROXY_SECRET is
# compared byte-for-byte against the header the Worker sends. Strip it in both cases.
rand_hex() { openssl rand -hex 32 | tr -d '\n'; }

# The AES-256 encryption key must be stable — rotating it breaks anything already
# encrypted (e.g. stored OAuth client secrets) — so create it only once.
if secret_exists "$ENC_SECRET"; then
  echo "Keeping existing $ENC_SECRET (not rotating)."
else
  gcloud secrets create "$ENC_SECRET" --project "$PROJECT" --replication-policy=automatic
  rand_hex | gcloud secrets versions add "$ENC_SECRET" --project "$PROJECT" --data-file=-
fi

# The proxy secret must stay stable (the Worker holds a copy) — create it only once.
if secret_exists "$PROXY_SECRET_NAME"; then
  echo "Keeping existing $PROXY_SECRET_NAME (not rotating)."
else
  gcloud secrets create "$PROXY_SECRET_NAME" --project "$PROJECT" --replication-policy=automatic
  rand_hex | gcloud secrets versions add "$PROXY_SECRET_NAME" --project "$PROJECT" --data-file=-
fi

echo "Secrets ready: $DB_URL_SECRET, $JWT_PRIVATE_SECRET, $JWT_PUBLIC_SECRET, $ENC_SECRET, $PROXY_SECRET_NAME"
echo
echo "Give the Cloudflare Worker the same proxy secret so its header matches:"
echo "  gcloud secrets versions access latest --secret=$PROXY_SECRET_NAME --project=$PROJECT | \\"
echo "    (cd ../../../web/worker && npx wrangler secret put PROXY_SECRET)"
echo "Then grant access with ./grant-secret-access.sh (and scorecard's)."
