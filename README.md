# CDIS Deployment

Deployment topology, reverse proxy, and end-to-end tests for the CDIS Engineering Template. This is **not** an application repository — it contains no copied frontend or backend source.

- Application source: [`cdis-frontend`](https://github.com/WorkGaurav1/cdis-frontend), [`cdis-backend`](https://github.com/WorkGaurav1/cdis-backend)
- This repo owns: Docker Compose orchestration, the reverse proxy, deployment scripts, and the Playwright end-to-end suite (which validates the *integrated* system — browser → frontend → backend → database — not either app in isolation)

---

## Architecture

```text
Internet
   │
   ▼
Reverse Proxy (Apache httpd, single public origin)
   ├── /api/*  ──▶  backend container  ──▶  Prisma  ──▶  MySQL
   └── /*      ──▶  frontend container (static build)
```

Frontend and backend share one public origin — the frontend is built with `VITE_API_BASE_URL=/api/v1` (a **relative** path), and the proxy routes `/api/*` to the backend container internally. This means the browser only ever talks to one origin: no CORS, and cookies (access/refresh/CSRF) work exactly as same-site cookies should.

MySQL has no published port — only the backend container can reach it, over the internal Docker network.

---

## Repository structure

```text
compose/
├── compose.yaml               local verification stack — builds from
│                               ../cdis-backend and ../cdis-frontend
└── compose.production.yaml    production stack — pulls pinned GHCR images (WIP)

reverse-proxy/apache/
└── httpd.conf                 routing: /api/* -> backend, /* -> frontend

scripts/
└── e2e-up.sh                  builds + starts the stack, runs migrations/seed

e2e/                            Playwright suite — see Testing below

env/
└── production.env.example      documents required variables; never commit real values
```

---

## Local verification stack

Requires `cdis-backend` and `cdis-frontend` checked out as **sibling directories** to this repo (`compose.yaml`'s build context defaults to `../../cdis-backend` / `../../cdis-frontend`, overridable via `BACKEND_BUILD_CONTEXT`/`FRONTEND_BUILD_CONTEXT` in `compose/.env`):

```text
Projects/
├── cdis-backend/
├── cdis-frontend/
└── cdis-deployment/
```

Inside the CDIS Template monorepo specifically, this repo's own `compose/.env` sets `BACKEND_BUILD_CONTEXT=../../back-end` / `FRONTEND_BUILD_CONTEXT=../../front-end` instead, so the stack builds from this repo's own `back-end/`/`front-end/` folders rather than needing separate sibling clones. That override lives only in the gitignored `compose/.env`, so this file stays accurate for both contexts.

```bash
cp env/production.env.example compose/.env
# then fill in real values in compose/.env — see the file for what's needed

./scripts/e2e-up.sh
```

This builds both images, starts MySQL + backend + frontend + reverse proxy, waits for the backend to answer `/health`, then applies migrations and seed data. The app is then reachable at `http://localhost:8080`.

To tear down: `docker compose -f compose/compose.yaml down` (add `-v` to also drop the MySQL volume).

**MySQL only applies `MYSQL_PASSWORD`/`MYSQL_ROOT_PASSWORD` when it initializes a brand-new, empty data volume — changing those values in `compose/.env` after the volume already exists does nothing; the database keeps its original credentials.** If you change the DB password and the app starts failing auth against MySQL, that's why — `down -v` (or delete the `cdis_mysql-data` volume directly) and start fresh.

---

## Production stack

Pulls pinned images from GHCR instead of building from source — this is the actual production model (build once in each app's own CI, deploy the resulting artifact everywhere else), never `docker compose ... up --build` on the server itself.

```bash
cp env/production.env.example compose/.env.production
# fill in real values, plus FRONTEND_VERSION / BACKEND_VERSION — a specific
# commit SHA from a successful build in cdis-frontend/cdis-backend's CI,
# never left unset or pointed at :latest

docker compose -f compose/compose.production.yaml --env-file compose/.env.production up -d
# first run only: apply migrations + seed (see the .env-file quirk noted
# above, in "A real quirk worth knowing about")
docker compose -f compose/compose.production.yaml --env-file compose/.env.production \
  exec -u root backend sh -c 'env > .env && npx prisma migrate deploy && npx prisma db seed'
```

Verified for real: pulled the actual GHCR images built by `cdis-backend`/`cdis-frontend`'s CI (not built from source), brought up this exact compose file, ran migrations/seed, then ran the full E2E suite against it — all 10 tests pass against genuinely pulled, pinned artifacts.

### A real quirk worth knowing about

The backend's seed command (`prisma.config.ts`) hardcodes `tsx --env-file=.env`, which needs a literal `.env` file to exist — even though the container already has every variable it needs via `environment:` in the compose file. `e2e-up.sh` handles this by generating a throwaway `.env` from the container's own environment before seeding. This also has to run as `root`, since the runtime image's `/app` is deliberately not writable by the non-root `app` user the main process runs as.

---

## Deploying and rolling back

`scripts/deploy.sh` is the only supported way to change what's running in production — it never rebuilds, it only pulls a specific already-published pair of images:

```bash
./scripts/deploy.sh <frontend-version> <backend-version>
# e.g. ./scripts/deploy.sh f144a570a1f9c131259e707b26093022ec18ebfc fc9c6e595645053dc578d7d8f1def79184114c8b
```

It records what was live before the change (`compose/current-versions.env` → `compose/previous-versions.env`), pulls and starts the requested versions, then polls `${HEALTH_CHECK_URL:-http://localhost}/health` for up to a minute. On failure it exits non-zero and points at rollback rather than leaving a broken deploy running silently.

```bash
./scripts/rollback.sh   # re-deploys whatever was live immediately before the last deploy.sh run
```

Both scripts require `compose/.env.production` to already exist (copy `env/production.env.example` once and fill in real secrets — never commit this file, which is why `.gitignore` matches `compose/.env*`).

For an ad-hoc check against any running environment (local, staging, production) without touching deploy state:

```bash
./scripts/health-check.sh                      # defaults to http://localhost
./scripts/health-check.sh https://cdis.example.com
```

It checks backend `/health` (200), frontend `/` (200), and unauthenticated `/api/v1/auth/me` (expects 401 specifically — a 200 there would mean auth is broken open, anything other than 401/200 usually means the backend or DB is down).

A real gotcha hit while testing this: reusing the same `cdis_mysql-data` Docker volume across two test runs with *different* generated `DB_PASSWORD` values fails auth (`P1000`), because the official MySQL image only applies `MYSQL_USER`/`MYSQL_PASSWORD` when initializing a brand-new empty volume — changing the password in `.env.production` later does nothing to an existing volume. Fix: `docker compose -f compose/compose.production.yaml down -v` to wipe the volume before a genuinely fresh start (obviously destructive — never run this against real production data without a backup).

---

## HTTPS

One-time setup, once a domain already resolves to this server's public IP on port 80:

```bash
./scripts/setup-https.sh cdis.example.com you@example.com
```

This brings up the HTTP-only bootstrap stack (`compose.https-init.yaml`), obtains a certificate via `certbot`'s webroot method (Let's Encrypt validates ownership by fetching `http://<domain>/.well-known/acme-challenge/...` from the public internet — the domain has to already be pointed here before this will work), renders `reverse-proxy/apache/httpd.tls.conf.template` into `reverse-proxy/apache/httpd.conf` with `envsubst`, and switches to the steady-state TLS stack (`compose.https.yaml`, port 443 + HTTP→HTTPS redirect on port 80).

Why `envsubst` on the host rather than a container-side templating mechanism: Compose *appends* `volumes:` lists across `-f` files rather than replacing them, so an overlay can't cleanly swap which file is mounted at `/usr/local/apache2/conf/httpd.conf` — it would end up bind-mounted twice. Rendering on the host and overwriting the one file both stacks already mount sidesteps that entirely.

After this runs, `reverse-proxy/apache/httpd.conf` on the server holds the rendered, domain-specific TLS config — that's expected and server-local; don't `git pull` over it without re-running the substitution.

Certificates expire after 90 days. Renew periodically (e.g. monthly via cron):

```bash
docker compose -f compose/compose.production.yaml -f compose/compose.https.yaml \
  --env-file compose/.env.production --env-file compose/current-versions.env \
  run --rm certbot certbot renew
docker compose -f compose/compose.production.yaml -f compose/compose.https.yaml \
  --env-file compose/.env.production --env-file compose/current-versions.env \
  restart reverse-proxy
```

Verified locally: the rendered TLS config (real domain substituted in) passes Apache's own `httpd -t` syntax check, and both `compose.https-init.yaml` and `compose.https.yaml` merge cleanly over `compose.production.yaml` with no duplicate or conflicting volume mounts. Real Let's Encrypt issuance is not verified yet — it needs a publicly-reachable domain, which requires the production server to exist first.

---

## Automated deploys (CD)

A push to `main` in `cdis-frontend` or `cdis-backend` that passes CI and publishes an image fires a `repository_dispatch` (`deploy-frontend` / `deploy-backend`) at this repo, carrying the new commit SHA as `client_payload.version`. `.github/workflows/deploy.yml` here picks that up, fills in whichever app *wasn't* just built from `compose/current-versions.env` (so a single app's CI can trigger a deploy without knowing its sibling's version), and runs `scripts/deploy.sh` with the resolved pair.

The job runs on a **self-hosted runner registered on the production server itself** — deliberately, over a GitHub-hosted runner SSHing in: no long-lived SSH private key sits in GitHub secrets, and no inbound SSH access from GitHub's runner IP ranges needs to be opened for this specifically. The runner should run as a low-privilege user that's only a member of the `docker` group.

One-time setup, once the server exists:

1. **Register the runner** — on the server: Settings → Actions → Runners → New self-hosted runner in this repo, follow GitHub's generated `./config.sh` command, then install it as a service (`sudo ./svc.sh install && sudo ./svc.sh start`) so it survives reboots.
2. **Create a dispatch token** — a fine-grained PAT (Settings → Developer settings → Personal access tokens → Fine-grained) scoped to *only* this repo, with **Contents: Read and write** permission. Add it as a secret named `DEPLOY_DISPATCH_TOKEN` in **both** `cdis-frontend` and `cdis-backend` (same value, same secret name in each).
3. **Seed `current-versions.env` once** — run `./scripts/deploy.sh <frontend-version> <backend-version>` by hand for the very first deploy. After that, CD keeps it current automatically.

Until the token secret is set, the "Trigger deploy" step in both app repos' CI is a no-op (`if: secrets.DEPLOY_DISPATCH_TOKEN != ''`) — CI stays green with nothing to dispatch to.

A specific version pair can also be deployed manually without waiting for a new commit: Actions → Deploy → Run workflow, with `frontend_version` / `backend_version` inputs (leave one blank to keep whatever's currently live).

Verified: the version-resolution logic (`deploy.yml`'s "Resolve versions" step) was tested standalone against all four real cases — frontend-only dispatch, backend-only dispatch, manual dispatch with both versions, and the first-deploy case with no `current-versions.env` yet (correctly fails with a clear message rather than deploying a blank version). Not yet verified: an actual run against a registered self-hosted runner, since no server exists yet to register one on.

---

## Testing

The Playwright suite in `e2e/` drives a real browser against whatever's running at `E2E_BASE_URL` (defaults to `http://localhost:8080`, i.e. the local compose stack). It does **not** manage its own environment (no `webServer` orchestration) — bringing up a full multi-container stack with migrations is a separate concern from running tests against it:

```bash
./scripts/e2e-up.sh     # bring the environment up first
npm run test:e2e        # then run the suite

# or point it at any other running environment, local stack or not:
E2E_BASE_URL=https://cdis.example.com npm run test:e2e
```

Coverage: login (success + wrong-credentials), session persistence across a reload, logout (and confirms the backend session is actually revoked, not just hidden client-side), sidebar navigation to every page, the permission-gated `/forbidden` redirect, and the 404 catch-all. This is a baseline suite — one representative path per concern — not exhaustive; deeper per-app behavior is covered by each app's own unit/component/integration tests in its own repo.

---

## What's not here yet

- Real production server (Oracle Cloud Always Free VM not yet created) — everything above is verified locally against genuinely pulled GHCR artifacts, but not yet against a real publicly-reachable host
- A registered self-hosted runner (needs the server above) — `deploy.yml` is written and its version-resolution logic tested standalone, but not yet run for real
- Real Let's Encrypt certificate issuance (needs the domain + server above)

These land as the deployment pipeline is built out — see this repo's issues/commits for current status rather than trusting this list to stay current.

---

## References

- Docker Compose — https://docs.docker.com/compose/
- Apache httpd (mod_proxy/mod_ssl) — https://httpd.apache.org/docs/2.4/
- Playwright — https://playwright.dev
