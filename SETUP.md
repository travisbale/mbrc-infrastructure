# Deployment runbook

Work top to bottom. Each phase notes the **values to capture** for later phases. Commands
assume the repos are checked out as siblings under one directory (this `infrastructure`
repo next to `scorecard`, and `heimdall` under `travisbale/`), matching the script
defaults.

## Values you'll collect

| Value | From | Used in |
| ----- | ---- | ------- |
| `GCP_PROJECT` | GCP project (phase 0) | every gcloud step + CI |
| `GCP_REGION` | you choose (default `us-central1`) | every gcloud step |
| `SCORECARD_DATABASE_URL` | Neon (phase 1) | scorecard secrets |
| `HEIMDALL_DATABASE_URL` | Neon (phase 1) | heimdall secrets |
| `HEIMDALL_URL` | heimdall deploy (phase 2) | Worker `wrangler.toml` |
| `SCORECARD_URL` | scorecard deploy (phase 3) | Worker `wrangler.toml` |
| `SCORECARD_PUBLIC_TENANT_ID` | prod tenant (phase 2b) | scorecard deploy |
| proxy secret | `proxy-secret` in Secret Manager | Worker `PROXY_SECRET` |

---

## Phase 0 — Accounts

**GCP**
1. console.cloud.google.com → create project (e.g. `mbrc-prod`); note the **Project ID**.
2. Enable **billing** (card required; usage stays ~free).
3. `gcloud auth login && gcloud config set project <PROJECT_ID> && gcloud auth application-default login`

**Neon**
1. neon.tech → new project, region nearest `us-central1` (**AWS us-east-2**).
2. Create a second database so you have both `scorecard` and `heimdall`.
3. Copy each **connection string** (ensure `?sslmode=require`).

**Cloudflare** — done (domain added, nameservers moved).

```bash
export GCP_PROJECT=<your-project-id>
export GCP_REGION=us-central1
```

---

## Phase 1 — Neon

One project with two databases (`heimdall`, `scorecard`), not two projects. A Neon project
is a compute endpoint, so two of them means two cold starts and two autosuspend timers for
services whose traffic is very unevenly split.

Use the **pooled** connection strings — the `-pooler` hostname. Each service opens up to 25
connections per instance and caps at 3 instances, so a flood can ask for 150 against a
free-tier compute that tops out around 100. Transaction pooling is safe here because both
services set `app.current_tenant_id` with `SET LOCAL` inside a transaction, so it can't
leak between requests on a shared connection.

```bash
export HEIMDALL_DATABASE_URL='postgres://…-pooler…neon.tech/heimdall?sslmode=require'
export SCORECARD_DATABASE_URL='postgres://…-pooler…neon.tech/scorecard?sslmode=require'
```

### Give each service a non-superuser role ⚠️

**Do this before the services first start.** Neon's default `neondb_owner` inherits
`BYPASSRLS` from `neon_superuser`, which makes every `FORCE ROW LEVEL SECURITY` policy in
both schemas inert. It matters most for heimdall, whose queries carry *no* explicit tenant
predicate at all — `GetUser` is `WHERE id = $1` — so RLS is its only tenant isolation.
`dev/postgres/init/*.sh` already does exactly this locally.

Roles created in the Neon console are auto-granted `neon_superuser`, so they must be
created in SQL:

```sql
CREATE ROLE scorecard LOGIN PASSWORD '…';
GRANT CONNECT ON DATABASE scorecard TO scorecard;
GRANT USAGE, CREATE ON SCHEMA public TO scorecard;
```

Then point the connection string at that role, so the startup migration creates and owns
every table as it. Verify with `SELECT bool_or(rolbypassrls) FROM pg_roles WHERE
pg_has_role(current_user, oid, 'USAGE')` — it must be false.

If a service already migrated as `neondb_owner`, transfer ownership instead:
`GRANT <role> TO CURRENT_USER WITH INHERIT TRUE` (PG16 gives the creator ADMIN but not
INHERIT, and `REASSIGN` needs the latter) followed by
`REASSIGN OWNED BY neondb_owner TO <role>`, then redeploy so the new DSN is picked up.

---

## Phase 2 — heimdall → Cloud Run

```bash
cd gcp/heimdall
export HEIMDALL_SRC=../../../../travisbale/heimdall

./generate-jwt-keys.sh                       # RSA keypair → ./keys (git-ignored)
./bootstrap-secrets.sh                        # DB URL, JWT keypair, encryption key, proxy-secret
./grant-secret-access.sh
./deploy.sh                                   # prints HEIMDALL_URL — save it
```

Capture: `HEIMDALL_URL`.

### Phase 2b — prod tenant + admin

There is no tenant API: a tenant exists only as a side effect of the first registration.
`BootstrapTenant` creates it along with a **System Admin** role granted every permission
that exists *at that instant* (`internal/db/postgres/tenants.go:67`), which fixes the
ordering below — register before the scorecard scopes exist and the admin can never write.

This is `dev/bootstrap.sh` with two substitutions: every call carries `X-Proxy-Secret`
(the services 403 anything else, and there's no Worker in front yet), and the verification
token comes from Cloud Logging rather than `docker logs`.

```bash
H=$(gcloud secrets versions access latest --secret=proxy-secret --project "$GCP_PROJECT")

# 1. Scorecard's scopes must exist first. No API creates permissions — /v1/permissions is
#    read-only, and heimdall's own seed migration only knows its own scopes.
psql "$HEIMDALL_DATABASE_URL" <<'SQL'
INSERT INTO permissions (name, description) VALUES
  ('scorecard:tournaments:write', 'Manage tournaments, teams, rosters, matches, participants'),
  ('scorecard:players:write',     'Create players'),
  ('scorecard:scores:write',      'Submit match scores'),
  ('scorecard:courses:write',     'Manage courses, tee colors, tee sets')
ON CONFLICT (name) DO NOTHING;
SQL

# 2. Register the admin. This is the call that mints the tenant.
curl -X POST "$HEIMDALL_URL/v1/register" -H "X-Proxy-Secret: $H" \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@manitobarydercup.com","first_name":"MRC","last_name":"Admin"}'

# 3. With no mailer configured heimdall logs the email instead of sending it. Only the
#    plaintext token in the log works — the stored row is a sha256 of it. `logs read`
#    won't render the structured payload, hence `logging read`.
gcloud logging read \
  'resource.type=cloud_run_revision AND resource.labels.service_name=heimdall' \
  --project "$GCP_PROJECT" --limit 5 --format='value(jsonPayload.verification_url)'

# 4. Verify and set the password in one call.
curl -X POST "$HEIMDALL_URL/v1/verify-email" -H "X-Proxy-Secret: $H" \
  -H 'Content-Type: application/json' \
  -d '{"token":"<from step 3>","password":"<choose one>"}'
```

Sanity check before moving on — the role should hold 17 permissions, 13 heimdall + 4
scorecard:

```sql
SELECT count(*) FROM role_permissions rp JOIN roles r ON r.id = rp.role_id;
```

The tenant UUID (`SELECT tenant_id FROM users`) becomes `SCORECARD_PUBLIC_TENANT_ID`.

```bash
export SCORECARD_PUBLIC_TENANT_ID=<tenant-uuid-from-heimdall>
```

---

## Phase 3 — scorecard → Cloud Run

```bash
cd ../scorecard                               # gcp/scorecard
export SCORECARD_SRC=../../../scorecard

./bootstrap-secrets.sh                         # scorecard DB URL (jwt-public-key already exists)
./grant-secret-access.sh
./deploy.sh                                    # prints SCORECARD_URL — save it
```

Capture: `SCORECARD_URL`.

---

## Phase 4 — Frontend → Cloudflare Pages

In the Cloudflare dashboard → Workers & Pages → create a Pages project, connect the `web`
repo:
- Build command: `npm run build`  ·  Output dir: `dist`
- Add custom domains: `manitobarydercup.com` and `www.manitobarydercup.com`

No build-time API vars needed (the app calls relative `/api/*`).

---

## Phase 5 — API proxy Worker

```bash
cd ../../cloudflare/api-proxy
# 1. Put HEIMDALL_URL and SCORECARD_URL into wrangler.toml [vars].
# 2. Give the Worker the same proxy secret the services enforce:
gcloud secrets versions access latest --secret=proxy-secret --project="$GCP_PROJECT" \
  | npx wrangler secret put PROXY_SECRET
# 3. Ship it:
npm install && npm run deploy
```

Now `https://manitobarydercup.com` serves the app and `/api/*` reaches the services.

---

## Phase 6 — Harden & cap cost

- Cloudflare → your domain → Security → enable **Bot Fight Mode**; add a **rate-limit
  rule** on `/api/*`.
- Budget alert:
  ```bash
  gcloud billing budgets create --billing-account=<ACCT> \
    --display-name=mbrc --budget-amount=10USD \
    --threshold-rule=percent=0.5 --threshold-rule=percent=1.0
  ```

---

## Phase 7 — CI/CD

```bash
cd ../../gcp/ci
./setup-github-oidc.sh                          # prints 5 values
```

Set those 5 as **Actions Variables** on `manitoba-ryder-cup/scorecard` and
`travisbale/heimdall`. After that, `git push origin vX.Y.Z` builds + deploys that service.

---

## Gotchas found during the first run

- **`/healthz` never reaches the container.** Cloud Run's frontend answers it with its own
  HTML 404. Sibling paths (`/health`, `/healthz2`) reach the service normally, and the same
  image serves `/healthz` fine locally, so don't debug the build. Cloud Run's own startup
  check is a TCP probe and doesn't use it, but any uptime check pointed there reads as
  permanently down.
- **Two secrets can't share a mount directory.** Cloud Run derives one volume per secret
  and rejects two at the same path, so heimdall's JWT keys mount at `/secrets/jwt-private/`
  and `/secrets/jwt-public/` rather than a shared `/secrets/jwt/`.
- **The first image must be built and pushed by hand.** `release.yml` authenticates through
  the Workload Identity pool that phase 7 creates, and its deploy step passes only
  `--image`, so it needs a service that already has its env vars and secrets. Build locally,
  push to Artifact Registry, and pass `IMAGE=` to `deploy.sh`. Tag it something like
  `bootstrap` so `v1.0.0` stays free for the first real release.

## Open items to settle
- **Route 53 teardown:** delete the old hosted zone once Cloudflare is confirmed Active
  (saves $0.50/mo). Leave EC2 / Secrets Manager / IAM until the new stack is serving.
- **Registrar transfer (optional):** move `manitobarydercup.com` from Namecheap to
  Cloudflare Registrar later for cheaper renewals.
