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

Capture the two connection strings:

```bash
export HEIMDALL_DATABASE_URL='postgres://…neon.tech/heimdall?sslmode=require'
export SCORECARD_DATABASE_URL='postgres://…neon.tech/scorecard?sslmode=require'
```

---

## Phase 2 — heimdall → Cloud Run

```bash
cd gcp/heimdall
export HEIMDALL_SRC=../../../../travisbale/heimdall

./generate-jwt-keys.sh                       # RSA keypair → ./keys (git-ignored)
./bootstrap-secrets.sh                        # DB URL, JWT keypair, encryption key, proxy-secret
./grant-secret-access.sh
./migrate.sh
./deploy.sh                                   # prints HEIMDALL_URL — save it
```

Capture: `HEIMDALL_URL`.

### Phase 2b — prod tenant + admin + data ⚠️ (needs a decision)

Prod starts with an empty database. Before the public site shows anything you need: a
**tenant**, an **admin user** (with the `scorecard:*:write` scopes), and **tournament
data**. Locally this was `dev/seed.sh` (heimdall) + `scorecard seed-tournament`. We still
need to settle the prod equivalent — see "Open items" at the bottom. The tenant's UUID
becomes `SCORECARD_PUBLIC_TENANT_ID`.

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
./migrate.sh
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

## Open items to settle

- **Prod data bootstrap (phase 2b):** how the first tenant, admin user + scopes, and
  tournament data get created in prod. Options: adapt the dev seed scripts, or a one-off
  admin bootstrap command. Decide before the site can show anything.
- **Route 53 teardown:** delete the old hosted zone once Cloudflare is confirmed Active
  (saves $0.50/mo). Leave EC2 / Secrets Manager / IAM until the new stack is serving.
- **Registrar transfer (optional):** move `manitobarydercup.com` from Namecheap to
  Cloudflare Registrar later for cheaper renewals.
