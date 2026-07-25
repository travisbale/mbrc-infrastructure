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

# The AES-256 encryption key must be stable — rotating it breaks anything already
# encrypted (e.g. stored OAuth client secrets) — so create it only once.
if secret_exists "$ENC_SECRET"; then
  echo "Keeping existing $ENC_SECRET (not rotating)."
else
  gcloud secrets create "$ENC_SECRET" --project "$PROJECT" --replication-policy=automatic
  openssl rand -hex 32 | gcloud secrets versions add "$ENC_SECRET" --project "$PROJECT" --data-file=-
fi

echo "Secrets ready: $DB_URL_SECRET, $JWT_PRIVATE_SECRET, $JWT_PUBLIC_SECRET, $ENC_SECRET"
echo "Grant access with ./grant-secret-access.sh (and scorecard's, for jwt-public-key)."
