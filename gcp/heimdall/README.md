# heimdall → Cloud Run

Deploys the `heimdall` auth service (Go) to Cloud Run. heimdall **issues** the JWTs the
whole system trusts, so it owns the RSA keypair: it signs with the private key and
publishes the public key that scorecard verifies with.

## Config the service reads

| Env var                 | Set to                                   | Where |
| ----------------------- | ---------------------------------------- | ----- |
| `DATABASE_URL`          | Neon `heimdall` connection string        | Secret Manager |
| `ENCRYPTION_KEY`        | AES-256, 32-byte hex                      | Secret Manager |
| `JWT_PRIVATE_KEY_PATH`  | `/secrets/jwt/private.pem`                | file from Secret Manager |
| `JWT_PUBLIC_KEY_PATH`   | `/secrets/jwt/public.pem`                 | file from Secret Manager |
| `PUBLIC_URL`            | `https://manitobarydercup.com` (frontend)| env |
| `CORS_ALLOWED_ORIGINS`  | apex + www                                | env |
| `HTTP_ADDRESS`          | `:8080`                                   | env |
| `TRUSTED_PROXY_MODE`    | `true` (behind Cloudflare)                | env |

## Order of operations

```bash
export GCP_PROJECT=your-project
export GCP_REGION=us-central1
export HEIMDALL_SRC=../../../../travisbale/heimdall   # a checkout of the heimdall repo

# 1. Generate the shared JWT keypair (once).
./generate-jwt-keys.sh

# 2. Create secrets (DB URL, JWT keypair, encryption key) and grant Cloud Run access.
HEIMDALL_DATABASE_URL='postgres://…neon.tech/heimdall?sslmode=require' ./bootstrap-secrets.sh
./grant-secret-access.sh

# 3. Apply DB migrations (one-off Cloud Run Job).
./migrate.sh

# 4. Deploy.
./deploy.sh
```

`deploy.sh` prints the service URL — copy it into the web repo's `worker/wrangler.toml` as
`HEIMDALL_URL`. Deploy heimdall **before** scorecard so the shared `jwt-public-key` secret
exists (scorecard reads it).

## Notes

- **Email is stubbed.** With neither `EMAIL_WEBHOOK_URL` nor `MAILMAN_GRPC_ADDRESS` set,
  heimdall uses a console email client — password-reset "emails" are logged, not sent.
  That matches the frontend's stubbed forgot-password flow. Wire up `mailman` or a webhook
  later to send real mail.
- **Migrations run before the service does**, as a one-off job on the same image. A
  failure stops there and leaves the running revision alone, rather than taking out the new
  revision and every later boot of the old one. The schema therefore reaches production
  ahead of the code that reads it, so a change has to be compatible with the release before
  it: add and backfill in one release, remove in a later one. CI only ever migrates an
  *empty* database, so a migration that depends on existing data can pass CI and still fail
  here.
- **gRPC (9090)** runs internally but isn't exposed by Cloud Run; nothing in this
  deployment consumes it.
- **Social login** (`GOOGLE_*`, `MICROSOFT_*`) is unset — email/password only for now.
