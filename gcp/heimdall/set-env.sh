#!/usr/bin/env bash
#
# Apply env.sh to the running heimdall service, without touching the image or the secrets.
#
# This is a separate script rather than a re-run of deploy.sh because deploy.sh builds from a
# local checkout unless IMAGE is set — so using it to change a variable can ship whatever is
# in the working tree. A release deploys the image alone and leaves the environment as it
# found it, so this is the only thing that changes configuration on a live service.
#
#   GCP_PROJECT=my-proj ./set-env.sh
#
set -euo pipefail

PROJECT="${GCP_PROJECT:?set GCP_PROJECT}"
REGION="${GCP_REGION:-us-central1}"
SERVICE="${SERVICE:-heimdall}"

source "$(dirname "$0")/env.sh"

# --update-env-vars merges; --set-env-vars removes every existing variable first, which would
# take the secret-backed ones with it. The cost is that dropping a variable from env.sh does
# not remove it from the service — that needs an explicit --remove-env-vars.
gcloud run services update "$SERVICE" \
  --project "$PROJECT" \
  --region "$REGION" \
  --update-env-vars "$ENV_VARS"

echo
echo "Now set on $SERVICE:"
gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" \
  --format='value(spec.template.spec.containers[0].env)'
