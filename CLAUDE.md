# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Pixorex V1: AI-powered industrial asset digitization for PPG Industries. A technician photographs an equipment nameplate (1–4 photos), AI extracts fields, the technician verifies and submits a revision, and a **different** person approves or rejects it — inside a tenant → business unit → location structure.

**Read before non-trivial work:** `CONSTITUTION.md` (binding rules; stop and raise any conflict with it) → `ARCHITECTURE.md` (relevant section only) → `STATE.md` (tasks, decisions) → the spec in `specs/`. Team status: `docs/handover.md`. Mobile API rules: `docs/mobile-api.md`.

## Repo layout

| Folder | What |
|---|---|
| `api/` | FastAPI (Python 3.12, uv), `/api/v1`, plus the worker process |
| `web/` | React 19 + TS strict + Vite + Tailwind 4: Enterprise Admin and BU Admin dashboards |
| `mobile/` | Flutter app, technicians only |
| `keycloak/` | Realm config, Java SPI (OTP authenticators, SMS, email, audit event listener), login theme |
| `contracts/` | OpenAPI 3.1, one file per slice (S2–S5) + `common.yaml`. The interface between all clients and the API |
| `docs/` | PRD, data model, readable contracts, setup guides |

## Commands

**Local stack** (Docker Desktop + Node 24). First time: `.\scripts\setup-local.ps1`. Daily: `docker compose up -d`, then `cd web; npm run dev` → http://localhost:5173. Sign in as `ea@demo.local` or `buadmin.p04@demo.local`; codes arrive in Mailpit (http://localhost:8025). Makefile: `make up|down|reset|ps|logs s=<svc>|migrate|seed`. Host Postgres is on **5433**.

**API** (`cd api`):
```bash
uv sync
uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run pytest   # full check
uv run pytest tests/integration/test_review.py::test_name                            # single test
PIXOREX_TEST_ADMIN_URL="postgresql://postgres:local-only@localhost:5433/postgres" uv run pytest  # integration tests (skipped without it)
uv run alembic revision -m "summary"   # new migration: plain SQL in upgrade(), forward-only, runs as pixorex_owner
uv run uvicorn --factory app.main:create_app --reload   # keep --reload on Windows (psycopg async needs it)
python -m app.workers.runner            # worker (Compose `worker` = PIXOREX_WORKER_ROLE general; `extraction-worker` = extraction)
```
The API refuses to start if `PIXOREX_DATABASE_URL` uses `postgres` or `pixorex_owner` (they bypass RLS).

**Web** (`cd web`): `npm run dev | build | typecheck | lint | format:check | test`. Single test: `npx vitest run src/features/units/UnitCard.test.tsx` (or `-t "name"`). After any contract change: `npm run api:types` (regenerates `src/api/generated/`; never edit it by hand). `npm run api:mock` runs a Prism mock (set `VITE_API_PROXY_TARGET=http://127.0.0.1:4010` in `.env.local`). Without `VITE_OIDC_*` set, dev uses mock auth.

**Mobile** (`cd mobile`): `flutter analyze`, `flutter test`. Run on a USB device: `adb reverse tcp:8000 tcp:8000; adb reverse tcp:8080 tcp:8080`, then `flutter run --dart-define=API_BASE_URL=http://localhost:8000/api/v1 --dart-define=KEYCLOAK_ISSUER=http://localhost:8080/realms/pixorex`.

**Keycloak SPI**: `mvn -B -f keycloak/spi/pom.xml verify`; smoke test `keycloak/scripts/kc-smoke.ps1`.

**Contracts** (`cd contracts`): `npx @stoplight/spectral-cli lint common.yaml slice-*.yaml` (baseline: 0 errors, 14 known warnings in `common.yaml`).

## Architecture (big picture)

- **API layering:** `app/routers` → `app/services` → `app/repositories`. Routers never touch SQL; services own rules and transactions; repositories are the only DB code. `app/core`: config, logging, correlation id, problem+json errors, DB pool. `app/auth`: token check and request context.
- **Request pipeline:** one dependency validates the Keycloak JWT, loads `app_user` and the device session (`X-Device-Id`, revocation within 60 s), resolves the active unit from `user_session.active_bu_id`, and does `SET LOCAL app.tenant_id / app.user_id / app.bu_ids / app.is_ea` for RLS. Nothing else sets RLS context. Roles come from `user_unit_role` in the DB, not from the token.
- **Tenancy:** PostgreSQL RLS on every tenant-owned table (tenant, then unit unless EA), in addition to API checks. The API connects as a non-owner role; migrations run as owner. Other tenant's rows → 404.
- **No sign-in endpoints in the API.** Web and mobile do OIDC Auth Code + PKCE directly with Keycloak; the Keycloak SPI handles OTP (email/SMS) and lockout. Keycloak users carry `app_user_id` and `tenant_id` attributes as token claims; the API creates Keycloak users on invite accept. Keycloak posts audit events to `/internal/keycloak-events` (HMAC-checked).
- **Audit + outbox in the same transaction.** Every *Audit* write writes `audit_log` in its transaction; external effects (email, AI extraction, large export builds) go to `outbox_event` and run in the worker (`app/workers/`), never inline. `ai_field_value`, `revision`, `audit_log` are insert-only.
- **Status changes are action endpoints** (`/publish`, `/decisions`, …), never PATCH. Scans have two independent statuses (`processing_status`, `review_status`); illegal moves → 409 `invalid-state`.
- **AI only through the proxy** (`app/services/ai_proxy.py`, OpenAI direct). Extraction runs in the worker (`app/workers/extraction.py`).
- **Errors:** RFC 9457 `application/problem+json`; the `type` URI is the stable code from the contracts. Creates take `Idempotency-Key` (scans use `client_capture_id`).
- **Web:** one typed client (`web/src/api/client.ts`, openapi-fetch over generated types) adds the token and `X-Device-Id`, handles 401/403. Per-area wrappers in `src/api/*.ts`, screens in `src/features/<area>/`, shared UI in `src/components/` (reuse or extend before adding), design tokens in `src/styles/` (no hardcoded colours/fonts). TanStack Query, react-hook-form + zod.

## Rules that bite

- **Data model is frozen** (31 tables, `docs/data-model.md`): no new tables or columns without a written change request.
- **Contract first:** changing an endpoint means changing `contracts/*.yaml` (and `docs/api-contracts.md`) in the same change, then `npm run api:types`.
- **Nothing marked OPEN / `x-decision-pending` is built** until its decision is in `STATE.md` → *Decisions*. Stop and ask.
- **A0 areas are human-only** (agents may add tests only): `api/app/auth/`, RLS/grants SQL (`api/migrations/baseline/08_roles_grants.sql`, `09_rls.sql`), Keycloak, signed URLs, DLP, client token handling (`web/src/auth/`, mobile secure storage). See the A0 table in `api/README.md` and grades in CONSTITUTION §5.
- Every new table needs RLS policies plus an isolation test (tenant A can't see B; unit X can't see Y).
- Synthetic data only; no secrets in the repo; no PII, tokens or secrets in logs.
- Out of V1, never build: Client Portal, SAML flow, roles beyond EA / BU Admin / technician, process picker, editing a published location tree or equipment type, batch approve/reject, push notifications.
- Conventions: task ID `PX-<spec>-T<nn>`; commit `<task-id>: summary`; branch `<task-id>-slug`; ≤ 5 files / ≤ 200 lines per task, PR diff ≤ 300 lines; tests first (GIVEN/WHEN/THEN); 80% coverage on changed lines. API paths kebab-case, path params camelCase, JSON snake_case, cursor paging (`limit`, `cursor`). New dependencies need a justification.
