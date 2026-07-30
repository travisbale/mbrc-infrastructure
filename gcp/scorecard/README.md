# scorecard → Cloud Run

Deploys the `scorecard` API (Go, from its repo's Dockerfile) to Cloud Run: scale-to-zero,
capped at 3 instances, reading secrets from Secret Manager.

## Config the service reads (from `flags.go`)

| Env var                      | Set to                          | Where |
| ---------------------------- | ------------------------------- | ----- |
| `DATABASE_URL`               | Neon connection string          | Secret Manager |
| `JWT_PUBLIC_KEY_PATH`        | `/secrets/jwt/public.pem`       | file mounted from Secret Manager |
| `HTTP_ADDRESS`               | `:5000` (Cloud Run port = 5000) | env |
| `SCORECARD_PUBLIC_TENANT_ID` | your tenant id (anon reads)     | env |
| `TRUSTED_PROXY_MODE`         | `true` (behind Cloudflare)      | env |
| `ENVIRONMENT` / `LOG_FORMAT` | `production` / `json`           | env |

## Order of operations

```bash
export GCP_PROJECT=your-project
export GCP_REGION=us-central1
export SCORECARD_SRC=../../../scorecard          # a checkout of the scorecard repo

# 1. Create scorecard's DB-URL secret and grant Cloud Run access. (The shared
#    jwt-public-key secret is created by heimdall's bootstrap — deploy heimdall first.)
SCORECARD_DATABASE_URL='postgres://…neon.tech/scorecard?sslmode=require' \
  ./bootstrap-secrets.sh
./grant-secret-access.sh

# 2. Deploy the service. Migrations are applied by the service itself on startup.
SCORECARD_PUBLIC_TENANT_ID=<your-tenant-uuid> ./deploy.sh
```

`deploy.sh` prints the service URL — copy it into `cloudflare/api-proxy/wrangler.toml`
as `SCORECARD_URL`.

## Notes

- **Port 5000:** the service listens on `:5000`, so `--port 5000` is passed to Cloud Run
  (Cloud Run's default is 8080). No code change needed.
- **JWT public key:** scorecard only *verifies* tokens, so it needs heimdall's **public**
  key. Export it from heimdall (or Secret Manager) into the PEM file referenced above.
- **Cost cap:** `--min-instances 0` (idle = free) and `--max-instances 3` (bounded blast
  radius). Pair with a project budget alert — see the top-level README.
- **Migrations run at startup.** They're embedded in the binary and applied before the
  HTTP listener opens (`internal/app/server.go`), so a failed migration means the revision
  never becomes healthy and Cloud Run keeps routing to the previous one. CI only ever
  migrates an *empty* database, so a migration that depends on existing data (a new
  `NOT NULL`, a new unique constraint) can pass CI and still fail here.
