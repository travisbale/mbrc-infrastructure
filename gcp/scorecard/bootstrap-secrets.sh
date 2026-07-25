#!/usr/bin/env bash
#
# One-time: create the Secret Manager secrets the scorecard service reads. Re-running
# adds a new version to each secret (safe). Values are read from your environment / files
# so nothing sensitive is hard-coded or committed.
#
#   GCP_PROJECT=my-proj \
#   SCORECARD_DATABASE_URL='postgres://user:pass@ep-xxx.neon.tech/scorecard?sslmode=require' \
#   JWT_PUBLIC_KEY_FILE=./jwt-public.pem \
#     ./bootstrap-secrets.sh
#
set -euo pipefail

PROJECT="${GCP_PROJECT:?set GCP_PROJECT}"
DB_URL="${SCORECARD_DATABASE_URL:?set SCORECARD_DATABASE_URL (the Neon connection string)}"
JWT_PUB_FILE="${JWT_PUBLIC_KEY_FILE:?set JWT_PUBLIC_KEY_FILE (path to the heimdall PEM public key)}"

DB_URL_SECRET="${DB_URL_SECRET:-scorecard-database-url}"
JWT_PUBKEY_SECRET="${JWT_PUBKEY_SECRET:-jwt-public-key}"

create_or_update() {
  local name="$1" ; shift
  if ! gcloud secrets describe "$name" --project "$PROJECT" >/dev/null 2>&1; then
    gcloud secrets create "$name" --project "$PROJECT" --replication-policy=automatic
  fi
  # Feeds the value on stdin; "$@" is the producer command.
  "$@" | gcloud secrets versions add "$name" --project "$PROJECT" --data-file=-
}

create_or_update "$DB_URL_SECRET"    printf %s "$DB_URL"
create_or_update "$JWT_PUBKEY_SECRET" cat "$JWT_PUB_FILE"

echo "Secrets ready: $DB_URL_SECRET, $JWT_PUBKEY_SECRET"
echo "Grant the Cloud Run runtime service account access with grant-secret-access.sh."
