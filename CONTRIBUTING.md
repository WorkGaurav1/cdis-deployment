# Contributing

This repo is an independently clone/build/run-able export of the `deployment/` folder in [CDIS Template](https://github.com/WorkGaurav1/cdis-engineering-template) — the canonical, complete CDIS template, where new work happens first and full documentation (architecture, workflows, standards) lives. If you're extending the template itself rather than just using this repo standalone, work there instead; changes here get overwritten on the next sync.

## Before opening a PR

Bring up the local stack and confirm the E2E suite still passes — see [`README.md`](README.md)'s "Local verification stack" section:

```bash
./scripts/e2e-up.sh
npm run test:e2e
```

## Reporting a security issue

See [`SECURITY.md`](SECURITY.md).
