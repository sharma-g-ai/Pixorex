# Pixorex API

FastAPI service for the Pixorex V1 API (`/api/v1`). Rules: [CONSTITUTION](../CONSTITUTION.md), layout: [ARCHITECTURE §11](../ARCHITECTURE.md).

## Run locally

Needs Python 3.12 and [uv](https://docs.astral.sh/uv/) (`pip install uv`).

```bash
cd api
uv sync
# Local-only values. Deployed environments read secrets from Vault (PX-10-T03).
export PIXOREX_DATABASE_URL="postgresql://pixorex_app:local-only@localhost:5432/pixorex"
export PIXOREX_OIDC_ISSUER=http://localhost:8080/realms/pixorex
export PIXOREX_MINIO_URL=http://localhost:9000
export PIXOREX_MINIO_ACCESS_KEY=pixorex-local PIXOREX_MINIO_SECRET_KEY=local-only-minio  # large exports
export PIXOREX_VAULT_URL=http://localhost:8200
uv run uvicorn --factory app.main:create_app --reload
```

- Health: http://localhost:8000/api/v1/health · Ready: http://localhost:8000/api/v1/ready · Docs (local and test only): http://localhost:8000/api/v1/docs
- The app refuses to start if `PIXOREX_DATABASE_URL` uses `postgres` or `pixorex_owner`: they bypass row-level security.
- Windows: keep `--reload` (or use `--workers`). Without it uvicorn uses an event loop that psycopg's async mode can't use. Linux containers aren't affected.

## Migrations

Alembic, plain SQL, run as the **owner** role (never the API role). `0001` applies `migrations/baseline/`.

```bash
export PIXOREX_MIGRATIONS_DATABASE_URL="postgresql://pixorex_owner:local-only@localhost:5432/pixorex"
uv run alembic upgrade head
```

New migration: `uv run alembic revision -m "short summary"`, then write the SQL in `upgrade()`. Migrations are forward-only.

## Docker

`docker compose up -d` from the repo root builds this image, runs `migrate` once, then starts `api` on http://localhost:8000. On an empty volume, `migrations/local/init-db.sh` creates the roles with local-only passwords.

## Checks

```bash
uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run pytest
```

## Layout

`app/routers` → `app/services` → `app/repositories` (routers never touch SQL). `app/core`: config, logging, correlation id, problem+json, DB pool. `app/auth`: token check and request context (**A0**, see below).

## Needs architect review (A0, CONSTITUTION §5)

| File | What | Origin |
|---|---|---|
| `app/auth/tokens.py` | Keycloak token check | Iswarya's `jwt.py`, ported (async keys, problem+json) |
| `app/auth/context.py` | Request context: user, sign-out revocation, `SET LOCAL` for RLS, invite-link scope | Iswarya's `deps.py` / `db_ctx.py`, ported and extended |
| `app/auth/keycloak_admin.py` | Creates users in Keycloak on invite accept | Iswarya's code, ported; refuses another tenant's login |
| `migrations/versions/0002_*.py` | `invite_scope()` and the BU Admin sync trigger (SECURITY DEFINER) | New draft; replaces connecting as the owner role |
| `migrations/baseline/08_roles_grants.sql`, `09_rls.sql` | Grants and RLS | Drafts |
| `app/auth/signed_urls.py` | Signed MinIO links: review photos (15 min), large exports (1 hour) (BC-09) | New draft |
| `app/services/dlp.py` | DLP masking of CSV exports (BC-09) | New draft |
| `app/auth/keycloak_events.py` | HMAC check of Keycloak's audit events (`POST /internal/keycloak-events`); `keycloak_admin.brute_force_status` for the lock row | New draft |

## Open points

- `Idempotency-Key` is stored 24 hours in a new table, `idempotency_key` (migration 0003, approved by the lead 19 Oct 2026). The data model document doesn't list it yet. Same key + same request → the first answer; another request → 409 `idempotency-conflict`. Scans keep `client_capture_id`.
- Scans (2.21): the contract sends `photo_count`, but the data model has no column for it. Until one is added, photo numbers are checked against 1-4 and upload-complete needs photos 1..n with no gap.
- Scans are counted in `quota_usage`, but never refused with 402: where the unit's monthly limit is stored is PRD open item 9.
- The 429 rate limit (100 requests a minute per tenant) is not built.
- Keycloak events (`/internal/keycloak-events`, outside `/api/v1`): sign-in, failure, session end and lock rows are written. Not built: the reconciliation job that re-reads Keycloak's stored events (docs/keycloak.md 8.4), and phone change (Keycloak doesn't send that event yet). Deployed ingress must block `/internal/`.
- AI extraction (FR-4.4–4.9): upload-complete, retry and re-extract queue an attempt and an `extraction.run` outbox event; the worker reads the photos from MinIO, calls the AI proxy (Portkey) with the pinned contract's fields and stores one `ai_field_value` per field with its flags (`app/workers/extraction.py`, A1). Failed or timed out → scan `failed`; after 3 attempts → `retake_required`. Without Portkey settings the worker retries, then the attempt fails.
- Invite emails are sent by the API right after commit, not through the outbox: the outbox payload would store the raw link token (contract 1.8 says outbox; decide).
- CSV exports mask names, emails and phone numbers (agreed with the lead 19 Oct 2026); counts go into the export's audit row (DLP results not stored, OPEN O-14). A name typed into a field value is caught only if it belongs to a user of the company.
- AI assist (contract 2.20) goes through Portkey (`app/services/ai_proxy.py`, A1: prompt and injection defence need human review). The Portkey config picks the model (now Gemini; OPEN P-14 expects US endpoints with zero retention). Set `PIXOREX_PORTKEY_API_KEY` and `PIXOREX_PORTKEY_CONFIG_ID` in `.env`.
- Not built yet: the retention job (needs decisions; it should also delete old export files from MinIO).

## Worker

`python -m app.workers.runner` (Compose service `worker`, role `pixorex_worker`). Every 15 s it sends due outbox emails (retries with backoff, failed after 6 tries); it also builds exports over 1,000 rows into MinIO (`exports/<tenant>/<id>.csv`, rights checked again, `export_ready` alert; the job fails after 6 tries). Every 60 s it runs the jobs: 24-hour escalation, waiting-scan alerts (1 day, 1 week), stuck-batch alerts, invite expiry. Every bell notification also queues an email.

## Integration tests

They need a PostgreSQL superuser URL and are skipped without it:

```bash
PIXOREX_TEST_ADMIN_URL="postgresql://postgres:local-only@localhost:5433/postgres" uv run pytest
```
