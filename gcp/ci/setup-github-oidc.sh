#!/usr/bin/env bash
#
# One-time: let the GitHub Actions release workflows deploy to Cloud Run via Workload
# Identity Federation — GitHub mints a short-lived OIDC token, GCP trusts it, no key is
# ever stored in GitHub. Creates: the Artifact Registry repo, a deploy service account
# with the roles it needs, and a workload-identity pool/provider scoped to exactly the
# two service repos.
#
# Re-running is safe (each step no-ops if the resource already exists).
#
#   GCP_PROJECT=my-proj ./setup-github-oidc.sh
#
# Afterwards it prints the values to set as GitHub Actions *variables* on each service
# repo (Settings → Secrets and variables → Actions → Variables).
#
set -euo pipefail

PROJECT="${GCP_PROJECT:?set GCP_PROJECT}"
REGION="${GCP_REGION:-us-central1}"
AR_REPO="${AR_REPO:-mbrc}"
POOL="${POOL:-github-pool}"
PROVIDER="${PROVIDER:-github-provider}"
SA_NAME="${SA_NAME:-github-deployer}"
# Repos allowed to impersonate the deploy SA (owner/name), space-separated to override.
read -ra REPOS <<< "${REPOS:-manitoba-ryder-cup/scorecard travisbale/heimdall}"

SA_EMAIL="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"

exists() { eval "$1" >/dev/null 2>&1; }

echo "==> Enabling required APIs"
gcloud services enable --project "$PROJECT" \
  run.googleapis.com artifactregistry.googleapis.com \
  iamcredentials.googleapis.com sts.googleapis.com

echo "==> Artifact Registry repo ($AR_REPO)"
exists "gcloud artifacts repositories describe $AR_REPO --project $PROJECT --location $REGION" || \
  gcloud artifacts repositories create "$AR_REPO" --project "$PROJECT" \
    --location "$REGION" --repository-format docker \
    --description "Manitoba Ryder Cup service images"

echo "==> Deploy service account ($SA_EMAIL)"
exists "gcloud iam service-accounts describe $SA_EMAIL --project $PROJECT" || \
  gcloud iam service-accounts create "$SA_NAME" --project "$PROJECT" \
    --display-name "GitHub Actions deployer"

echo "==> Roles for the deploy SA"
# run.admin: deploy services + jobs. artifactregistry.writer: push images.
# iam.serviceAccountUser: act as the runtime SA when deploying.
for role in roles/run.admin roles/artifactregistry.writer roles/iam.serviceAccountUser; do
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member "serviceAccount:${SA_EMAIL}" --role "$role" --condition=None >/dev/null
done

echo "==> Workload Identity pool + provider"
exists "gcloud iam workload-identity-pools describe $POOL --project $PROJECT --location global" || \
  gcloud iam workload-identity-pools create "$POOL" --project "$PROJECT" \
    --location global --display-name "GitHub Actions"

# The provider trusts GitHub's OIDC issuer, maps the repo claim, and (attribute-condition)
# only accepts tokens from the allowed repos — so a token from any other repo is rejected.
REPO_CONDITION="$(printf "'%s'," "${REPOS[@]}" | sed 's/,$//')"
exists "gcloud iam workload-identity-pools providers describe $PROVIDER --project $PROJECT --location global --workload-identity-pool $POOL" || \
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
    --project "$PROJECT" --location global --workload-identity-pool "$POOL" \
    --display-name "GitHub" \
    --issuer-uri "https://token.actions.githubusercontent.com" \
    --attribute-mapping "google.subject=assertion.sub,attribute.repository=assertion.repository" \
    --attribute-condition "assertion.repository in [${REPO_CONDITION}]"

echo "==> Allow each repo to impersonate the deploy SA"
POOL_ID="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}"
for repo in "${REPOS[@]}"; do
  gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" --project "$PROJECT" \
    --role roles/iam.workloadIdentityUser \
    --member "principalSet://iam.googleapis.com/${POOL_ID}/attribute.repository/${repo}" >/dev/null
done

PROVIDER_RESOURCE="${POOL_ID}/providers/${PROVIDER}"

cat <<EOF

Done. Set these as GitHub Actions *Variables* on both service repos
(Settings → Secrets and variables → Actions → Variables):

  GCP_PROJECT   = ${PROJECT}
  GCP_REGION    = ${REGION}
  AR_REPO       = ${AR_REPO}
  DEPLOY_SA     = ${SA_EMAIL}
  WIF_PROVIDER  = ${PROVIDER_RESOURCE}

Then a \`git push origin vX.Y.Z\` on a service repo builds, migrates, and deploys.
EOF
