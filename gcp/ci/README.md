# CI/CD — tag-triggered Cloud Run deploys

Pushing a version tag to a service repo builds its image, pushes it to Artifact Registry,
runs migrations, and deploys the new revision to Cloud Run. No key material is stored in
GitHub — auth is via Workload Identity Federation (GitHub OIDC → GCP).

The workflows themselves live **in the service repos** (`.github/workflows/release.yml`),
because GitHub Actions only runs workflows from their own repo. This directory holds the
one-time GCP setup they depend on.

## One-time setup

```bash
GCP_PROJECT=your-project ./setup-github-oidc.sh
```

This creates the Artifact Registry repo, a `github-deployer` service account (roles:
`run.admin`, `artifactregistry.writer`, `iam.serviceAccountUser`), and a
workload-identity provider scoped to exactly `manitoba-ryder-cup/scorecard` and
`travisbale/heimdall`. It prints five values to set as **Actions Variables** on each
service repo (Settings → Secrets and variables → Actions → Variables):

| Variable       | Example |
| -------------- | ------- |
| `GCP_PROJECT`  | `mbrc-prod` |
| `GCP_REGION`   | `us-central1` |
| `AR_REPO`      | `mbrc` |
| `DEPLOY_SA`    | `github-deployer@mbrc-prod.iam.gserviceaccount.com` |
| `WIF_PROVIDER` | `projects/123.../locations/global/workloadIdentityPools/github-pool/providers/github-provider` |

These are non-secret (they're just resource names), so Variables — not Secrets — is
correct.

## Cutting a release

The first deploy of each service must be done manually (`gcp/<service>/deploy.sh`) so the
env vars, secrets, and scaling are set. After that, releases are just tags:

```bash
git tag v1.2.0
git push origin v1.2.0
```

The workflow deploys with `gcloud run deploy --image` only, so every non-image setting is
**inherited** from the existing service — config stays defined in one place (`deploy.sh`).

## Notes

- **Migrations run before the new revision serves.** Use expand-then-contract migrations
  (add columns/tables in one release, remove in a later one) so the currently-running
  revision keeps working while the job runs.
- **Rollback:** deploy a previous tag, or `gcloud run services update-traffic <svc>
  --to-revisions <older>=100`.
- **Frontend (web)** isn't a container — deploy it via Cloudflare Pages git integration
  (auto-build on push) or `cloudflare/pages/deploy.sh`, not this pipeline.
