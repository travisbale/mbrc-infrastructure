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

# 3. Deploy. Migrations are applied by the service itself on startup.
./deploy.sh
```

`deploy.sh` prints the service URL — copy it into `cloudflare/api-proxy/wrangler.toml` as
`HEIMDALL_URL`. Deploy heimdall **before** scorecard so the shared `jwt-public-key` secret
exists (scorecard reads it).

## Notes

- **Email is stubbed.** With neither `EMAIL_WEBHOOK_URL` nor `MAILMAN_GRPC_ADDRESS` set,
  heimdall uses a console email client — password-reset "emails" are logged, not sent.
  That matches the frontend's stubbed forgot-password flow. Wire up `mailman` or a webhook
  later to send real mail.
- **Migrations run at startup.** They're embedded in the binary and applied before the
  listener opens (`internal/app/setup.go`), so a failed migration means the revision never
  becomes healthy and Cloud Run keeps routing to the previous one. CI only ever migrates
  an *empty* database, so a migration that depends on existing data can pass CI and still
  fail here.
- **gRPC (9090)** runs internally but isn't exposed by Cloud Run; nothing in this
  deployment consumes it.
- **Social login** (`GOOGLE_*`, `MICROSOFT_*`) is unset — email/password only for now.
