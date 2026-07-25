#!/usr/bin/env bash
#
# Grant Cloud Run's runtime service account permission to read the scorecard secrets.
# Run once after bootstrap-secrets.sh. By default this targets the project's Compute
# Engine default service account, which new Cloud Run services use unless overridden.
#
#   GCP_PROJECT=my-proj ./grant-secret-access.sh
#
set -euo pipefail

PROJECT="${GCP_PROJECT:?set GCP_PROJECT}"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
RUNTIME_SA="${RUNTIME_SA:-${PROJECT_NUMBER}-compute@developer.gserviceaccount.com}"

DB_URL_SECRET="${DB_URL_SECRET:-scorecard-database-url}"
JWT_PUBKEY_SECRET="${JWT_PUBKEY_SECRET:-jwt-public-key}"

for secret in "$DB_URL_SECRET" "$JWT_PUBKEY_SECRET"; do
  gcloud secrets add-iam-policy-binding "$secret" \
    --project "$PROJECT" \
    --member "serviceAccount:${RUNTIME_SA}" \
    --role roles/secretmanager.secretAccessor
done

echo "Granted secretAccessor on: $DB_URL_SECRET, $JWT_PUBKEY_SECRET to $RUNTIME_SA"
