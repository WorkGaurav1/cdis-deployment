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
Reverse Proxy (nginx, single public origin)
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

reverse-proxy/nginx/
└── nginx.conf                 routing: /api/* -> backend, /* -> frontend

scripts/
└── e2e-up.sh                  builds + starts the stack, runs migrations/seed

e2e/                            Playwright suite — see Testing below

env/
└── production.env.example      documents required variables; never commit real values
```

---

## Local verification stack

Requires `cdis-backend` and `cdis-frontend` checked out as **sibling directories** to this repo (`compose.yaml`'s build context is `../../cdis-backend` / `../../cdis-frontend`):

```text
Projects/
├── cdis-backend/
├── cdis-frontend/
└── cdis-deployment/
```

```bash
cp env/production.env.example compose/.env
# then fill in real values in compose/.env — see the file for what's needed

./scripts/e2e-up.sh
```

This builds both images, starts MySQL + backend + frontend + reverse proxy, waits for the backend to answer `/health`, then applies migrations and seed data. The app is then reachable at `http://localhost:8080`.

To tear down: `docker compose -f compose/compose.yaml down` (add `-v` to also drop the MySQL volume).

### A real quirk worth knowing about

The backend's seed command (`prisma.config.ts`) hardcodes `tsx --env-file=.env`, which needs a literal `.env` file to exist — even though the container already has every variable it needs via `environment:` in the compose file. `e2e-up.sh` handles this by generating a throwaway `.env` from the container's own environment before seeding. This also has to run as `root`, since the runtime image's `/app` is deliberately not writable by the non-root `app` user the main process runs as.

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

- `compose.production.yaml` (pinned GHCR image references, not build-from-source)
- Deploy/rollback scripts and the CD workflow
- Production server provisioning notes

These land as the deployment pipeline is built out — see this repo's issues/commits for current status rather than trusting this list to stay current.

---

## References

- Docker Compose — https://docs.docker.com/compose/
- nginx — https://nginx.org/en/docs/
- Playwright — https://playwright.dev
