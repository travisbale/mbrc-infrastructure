#!/usr/bin/env bash
#
# Run scorecard database migrations as a one-off Cloud Run Job (`scorecard migrate up`).
# Deploy-time step: run this after bootstrap-secrets.sh and before/with deploy.sh.
# The job reuses the same container image and the same DATABASE_URL secret as the service.
#
# Set IMAGE to migrate with a released tag; without it, Cloud Build builds one from a
# local checkout, the same way deploy.sh does.
#
#   GCP_PROJECT=my-proj IMAGE=…/mbrc/scorecard:v1.2.3 ./migrate.sh
#
set -euo pipefail

PROJECT="${GCP_PROJECT:?set GCP_PROJECT}"
REGION="${GCP_REGION:-us-central1}"
JOB="${JOB:-scorecard-migrate}"
SOURCE_DIR="${SCORECARD_SRC:-../../../scorecard}"
DB_URL_SECRET="${DB_URL_SECRET:-scorecard-database-url}"

# `--args migrate,up` overrides the image's default `start` command. migrate needs only
# the database URL (not the JWT key), so nothing else is wired in.
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
