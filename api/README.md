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

## Open points

- `Idempotency-Key` is required on creates but not stored: the data model has no table for it.
- Invite emails are sent by the API after commit; contract 1.8 says the outbox worker (not built yet).
- Unit counts (`waiting_count` and the rest) are 0 until the scan tables are in use (REQ-04.07).

## Integration tests

They need a PostgreSQL superuser URL and are skipped without it:

```bash
PIXOREX_TEST_ADMIN_URL="postgresql://postgres:local-only@localhost:5433/postgres" uv run pytest
```
