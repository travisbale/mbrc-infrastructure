#!/usr/bin/env bash
#
# Run heimdall database migrations as a one-off Cloud Run Job (`heimdall migrate up`).
# Run after bootstrap-secrets.sh and before/with deploy.sh.
#
#   GCP_PROJECT=my-proj ./migrate.sh
#
set -euo pipefail

PROJECT="${GCP_PROJECT:?set GCP_PROJECT}"
REGION="${GCP_REGION:-us-central1}"
JOB="${JOB:-heimdall-migrate}"
SOURCE_DIR="${HEIMDALL_SRC:-../../../../travisbale/heimdall}"
DB_URL_SECRET="${DB_URL_SECRET:-heimdall-database-url}"

gcloud run jobs deploy "$JOB" \
  --project "$PROJECT" \
  --region "$REGION" \
  --source "$SOURCE_DIR" \
  --args "migrate,up" \
  --max-retries 1 \
  --task-timeout 300s \
  --set-secrets "DATABASE_URL=${DB_URL_SECRET}:latest"

echo "Executing migrations…"
gcloud run jobs execute "$JOB" --project "$PROJECT" --region "$REGION" --wait
echo "Migrations applied."
