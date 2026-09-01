#!/usr/bin/env bash
#
# Run heimdall database migrations as a one-off Cloud Run Job (`heimdall migrate up`).
# Run after bootstrap-secrets.sh and before/with deploy.sh.
#
# Set IMAGE to migrate with a released tag; without it, Cloud Build builds one from a
# local checkout, the same way deploy.sh does.
#
#   GCP_PROJECT=my-proj IMAGE=…/mbrc/heimdall:v1.2.3 ./migrate.sh
#
set -euo pipefail

PROJECT="${GCP_PROJECT:?set GCP_PROJECT}"
REGION="${GCP_REGION:-us-central1}"
JOB="${JOB:-heimdall-migrate}"
SOURCE_DIR="${HEIMDALL_SRC:-../../../../travisbale/heimdall}"
DB_URL_SECRET="${DB_URL_SECRET:-heimdall-database-url}"

if [[ -n "${IMAGE:-}" ]]; then
  BUILD_FROM=(--image "$IMAGE")
else
  BUILD_FROM=(--source "$SOURCE_DIR")
fi

gcloud run jobs deploy "$JOB" \
  --project "$PROJECT" \
  --region "$REGION" \
  "${BUILD_FROM[@]}" \
  --args "migrate,up" \
  --max-retries 0 \
  --task-timeout 300s \
  --set-secrets "DATABASE_URL=${DB_URL_SECRET}:latest"

echo "Executing migrations…"
gcloud run jobs execute "$JOB" --project "$PROJECT" --region "$REGION" --wait
echo "Migrations applied."
