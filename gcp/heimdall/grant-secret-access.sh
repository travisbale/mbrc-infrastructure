#!/usr/bin/env bash
#
# Grant Cloud Run's runtime service account read access to heimdall's secrets. Run once
# after bootstrap-secrets.sh. Targets the Compute Engine default service account unless
# RUNTIME_SA is overridden.
#
#   GCP_PROJECT=my-proj ./grant-secret-access.sh
#
set -euo pipefail

PROJECT="${GCP_PROJECT:?set GCP_PROJECT}"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
RUNTIME_SA="${RUNTIME_SA:-${PROJECT_NUMBER}-compute@developer.gserviceaccount.com}"

DB_URL_SECRET="${DB_URL_SECRET:-heimdall-database-url}"
ENC_SECRET="${ENC_SECRET:-heimdall-encryption-key}"
JWT_PRIVATE_SECRET="${JWT_PRIVATE_SECRET:-jwt-private-key}"
JWT_PUBLIC_SECRET="${JWT_PUBLIC_SECRET:-jwt-public-key}"

for secret in "$DB_URL_SECRET" "$ENC_SECRET" "$JWT_PRIVATE_SECRET" "$JWT_PUBLIC_SECRET"; do
  gcloud secrets add-iam-policy-binding "$secret" \
    --project "$PROJECT" \
    --member "serviceAccount:${RUNTIME_SA}" \
    --role roles/secretmanager.secretAccessor
done

echo "Granted secretAccessor to $RUNTIME_SA on heimdall's secrets."
