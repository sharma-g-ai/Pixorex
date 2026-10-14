# SPEC-PX-10 — DevSecOps & resilience (Sprint 2 slice)

| Field | Value |
|---|---|
| Bounded context | BC-10 (+ BC-09 for Vault loading) |
| Grade | A1 (DevOps signs off every gate change) · A0 for Vault secret loading |
| PRD | Delivery pipeline NFR (US-062–US-067), Secrets NFR (US-055, US-064) |
| Contracts | 4.3 `/health`, 4.4 `/ready` |
| Sprint | **S2: REQ-10.01–10.08** · S6: deployment gate, DAST, rollback, backup/restore |
| Status | Draft — awaiting G1 |

---

## Requirements

### REQ-10.01 Local stack
- GIVEN a clean checkout WHEN `docker compose up` runs THEN api, worker, keycloak (realm imported), postgres 16, minio, vault (dev) and mailpit start healthy, migrations apply and `/ready` returns `ready`.
- GIVEN `make seed` THEN the synthetic dataset (REQ-04.06) loads.
- GIVEN the README THEN a new engineer gets from clone to a signed-in demo user in under 30 minutes.

### REQ-10.02 API skeleton and probes — contracts 4.3, 4.4
FastAPI app with the layering, problem+json error handler, JSON logging with `correlation_id`, config validation at startup.
- GIVEN `/health` THEN `{status: "ok"}` without a token.
- GIVEN any dependency down WHEN `/ready` is called THEN 503 with per-dependency `ok`/`fail`, and no versions or secrets.
- **This is the G2 baseline PR for the API; architects review it personally.**

### REQ-10.03 Secrets from Vault (A0, BC-09)
- GIVEN the api, worker and keycloak containers WHEN they start THEN DB, Keycloak admin, SMS, SMTP and listener secrets are read from Vault, not from env vars or files (local dev Vault seeded by a script with synthetic values).
- GIVEN Vault unreachable at start THEN the container fails fast with a clear error.

### REQ-10.04 CI: tests and coverage
- GIVEN a PR THEN path-filtered workflows run: `api` (ruff, mypy, pytest against the Compose services, isolation suite), `web` (lint, typecheck, unit tests, build), `mobile` (analyze, tests), `keycloak` (build SPI, realm import smoke test). A change under `contracts/` triggers all.
- GIVEN changed lines below 80% coverage THEN the check fails.

### REQ-10.05 CI: security gates
- Secret scan (e.g. gitleaks) on every push and PR, blocking.
- SAST (e.g. Semgrep + Bandit) and dependency scan (e.g. pip-audit, npm audit, osv-scanner), blocking on high/critical.
- Container image scan (e.g. Trivy) on Dockerfiles, blocking on critical.
- GIVEN any gate skipped or errored THEN the PR cannot merge.

### REQ-10.06 CI: contract and PR rules
- Spectral lint on `contracts/` with the repo's `.spectral.yaml`.
- PR size check: diff > 300 lines fails (generated files and lockfiles excluded by list).
- PR title must start with a task ID matching `PX-\d{2}-T\d{2}`.

### REQ-10.07 Branch protection and ownership
- `main`: no direct pushes, 2 approvals, CODEOWNERS review required, all checks required, linear history.
- CODEOWNERS as in ARCHITECTURE §11.

### REQ-10.08 AI review job (may slip to S3)
- GIVEN a PR THEN a job runs `.claude/ai-review-prompt.md` with the pinned review model against the diff, the linked spec and the constitution, and posts a PASS / WARN / FAIL report as a PR comment. FAIL blocks merge.
