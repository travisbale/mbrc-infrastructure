#!/usr/bin/env bash
#
# One-time: create the scorecard database-URL secret. Re-running adds a new version (safe).
#
# scorecard also reads the shared `jwt-public-key` secret, but that one is owned and
# created by heimdall (gcp/heimdall/bootstrap-secrets.sh) — deploy heimdall first. Here we
# only create scorecard's own secret.
#
#   GCP_PROJECT=my-proj \
#   SCORECARD_DATABASE_URL='postgres://…neon.tech/scorecard?sslmode=require' \
#     ./bootstrap-secrets.sh
#
set -euo pipefail

PROJECT="${GCP_PROJECT:?set GCP_PROJECT}"
DB_URL="${SCORECARD_DATABASE_URL:?set SCORECARD_DATABASE_URL (the Neon connection string)}"
DB_URL_SECRET="${DB_URL_SECRET:-scorecard-database-url}"

if ! gcloud secrets describe "$DB_URL_SECRET" --project "$PROJECT" >/dev/null 2>&1; then
  gcloud secrets create "$DB_URL_SECRET" --project "$PROJECT" --replication-policy=automatic
fi
printf %s "$DB_URL" | gcloud secrets versions add "$DB_URL_SECRET" --project "$PROJECT" --data-file=-

echo "Secret ready: $DB_URL_SECRET"
echo "Grant access (to this + the shared jwt-public-key) with ./grant-secret-access.sh."
