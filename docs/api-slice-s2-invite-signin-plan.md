# Plan: FastAPI Slice S2 — Invite + Sign-in Bridge to Keycloak

| Field | Value |
|---|---|
| Audience | API / Keycloak / web owners |
| Goal | Unblock **invite → Keycloak OTP → `GET /me` → dashboard** with a real API (not Prism) |
| Specs | SPEC-PX-01 · contracts 1.1–1.3, 1.6–1.11 · `docs/keycloak.md` §8.3 |
| Tasks | PX-01-T05 (JWT/context), PX-01-T08 (invite + KC user), related `/me` routes |
| Status | **In progress** — skeleton + JWT/me/invites/bootstrap code landed under `api/`; wire web proxy for E2E |
| Depends on | Keycloak up · SQL baseline applied · `pixorex-web` / `pixorex-api-admin` in realm |

---

## 1. Why we must build FastAPI (clarification)

Keycloak and the web/DB each own a different job. **None of them alone completes invite + sign-in.**

| Layer | What it does | What it does *not* do |
|---|---|---|
| **Keycloak** | OTP sign-in, sessions, JWTs (`tenant_id`, `app_user_id`, `aud=pixorex-api`) | Store units/roles; send invite magic links; answer “what can this admin see?” |
| **Postgres** | `app_user`, `invite`, `user_unit_role`, `user_session`, … | Validate tokens; create Keycloak users; expose HTTP to the SPA |
| **Web** | OIDC redirect, `/activate`, dashboards | Talk to Keycloak Admin API; enforce RBAC in the DB; hash invite tokens |

**FastAPI is the bridge:**

1. After Keycloak login, the web calls **`GET /me`** with the access token → API verifies JWT (JWKS) → loads roles/units from Postgres → returns the shell payload.
2. On **invite**, the web calls **`POST /invites`** → API writes `invite` (+ `app_user` as needed) → creates/updates the Keycloak user via **`pixorex-api-admin`** → enqueues invite email (link to `/activate#token=…`).
3. On **accept**, API marks invite accepted, ensures Keycloak user exists, returns `next_step: verify_email` → web starts Keycloak with `login_hint`.
4. On **sign-out**, API revokes `user_session` for `X-Device-Id`; web then ends the Keycloak session.

Without FastAPI, invite buttons only hit the Prism mock: **no real rows, no Keycloak user, no real activation.**

```text
Admin (web) → POST /invites → FastAPI → Postgres + Keycloak Admin + email
User (link) → /activate → preview/accept → FastAPI → Postgres (+ KC if needed)
User (Sign in) → Keycloak OTP → tokens → GET /me → FastAPI → Postgres → dashboard
```

---

## 2. Scope for this plan (MVP vs later)

### In scope (MVP — enough for complete local invite + sign-in)

| # | Endpoint / capability | Contract |
|---|---|---|
| 1 | App skeleton, settings, DB pool, health | — |
| 2 | JWT auth middleware (iss, aud, exp, azp) + `SET LOCAL` tenant/user for RLS | PX-01-T05 |
| 3 | `GET /me` | 1.1 |
| 4 | `PUT /me/active-unit` | 1.2 |
| 5 | `POST /me/sign-out` | 1.3 |
| 6 | `POST /invites/preview`, `POST /invites/accept` | 1.6–1.7 |
| 7 | `POST /invites`, `GET /invites`, resend, cancel | 1.8–1.11 |
| 8 | Keycloak Admin client: create/update user, roles, store `keycloak_user_id` | PX-01-T08 |
| 9 | Invite email via SMTP or local Mailpit (sync ok for MVP; outbox table write optional) | — |
| 10 | `bootstrap_tenant` / seed script: one EA in DB + Keycloak | local |
| 11 | Compose `api` service on `:8000` | PX-10-T01 (API part) |

### Out of scope (follow-up)

- Full worker / outbox consumer job
- `POST /internal/keycloak-events` (can keep event-sink until then)
- Phone-change (O-12 / deprecated in OpenAPI)
- BU Admin / technician admin APIs beyond invites (1.12+)
- Alembic migration runner (baseline SQL already applied locally)
- Production Vault wiring (env vars for local)

---

## 3. Where files live — create vs modify

### 3.1 New files (create under `api/`)

Proposed layout (matches `docs/keycloak.md` §8.3):

```text
api/
  pyproject.toml                 # FastAPI, uvicorn, httpx, PyJWT, asyncpg/psycopg, pydantic-settings
  README.md                      # how to run locally
  app/
    __init__.py
    main.py                      # FastAPI app, routers, CORS
    config.py                    # env: DB, KC issuer, api-admin secret, SMTP, audit
    db.py                        # connection pool; SET LOCAL helpers for RLS
    deps.py                      # CurrentUser from JWT + DB
    auth/
      jwt.py                     # JWKS fetch/cache, verify access token
      keycloak_admin.py          # client-credentials + create/update user/roles
      context.py                 # RequestContext: tenant_id, app_user_id, device_id
    routers/
      me.py                      # /me, /me/active-unit, /me/sign-out
      invites.py                 # preview, accept, CRUD invites
      health.py                  # /health, /ready (KC + DB checks)
    services/
      me.py
      invites.py
      mail.py                    # send invite link (Mailpit/SMTP)
    models/                      # pydantic request/response aligned to OpenAPI
      me.py
      invites.py
  scripts/
    bootstrap_tenant.py          # create tenant + EA in DB + Keycloak user
```

Prefix all public routes with `/api/v1` (contracts).

### 3.2 Existing files to modify

| File | Change |
|---|---|
| `docker-compose.yml` | Add `api` service (build/run uvicorn), env for DB + Keycloak, depends_on `postgres` + `keycloak` + `mailpit` |
| `.env.example` | Document `DATABASE_URL`, `KC_ISSUER`, `KC_API_ADMIN_CLIENT_ID/SECRET`, `INVITE_APP_BASE_URL`, SMTP |
| `Pixorex/.env` (local, git-ignored) | Fill local values (admin secret from Keycloak) |
| `web/vite.config.ts` (optional later) | Proxy `/api` to `:8000` instead of Prism when real API is up |
| `web/.env.local` / README | Note switching off mock |
| `docs/keycloak-web-developer-next-steps.md` | Point at real API when ready |
| `STATE.md` | Mark PX-01-T05 / T08 progress when done |

### 3.3 Leave unchanged (for this MVP)

| Path | Why |
|---|---|
| `keycloak/realm/`, SPI, themes | Already provide tokens + Admin client |
| `api/migrations/baseline/*.sql` | Schema already defined; apply via existing README / Docker |
| `contracts/*.yaml` | Source of truth for shapes — implement against them, don’t fork |
| `web/src/auth/*` | Already OIDC; only env/proxy may change |

### 3.4 Keycloak one-time local step (ops, not code)

Regenerate / copy **`pixorex-api-admin` client secret** from admin console → put in `.env` as `KC_API_ADMIN_SECRET`. Realm JSON may blank the secret on import.

---

## 4. Implementation phases

### Phase A — Skeleton + config + health
- `pyproject.toml`, `app/main.py`, `config.py`, `db.py`
- Compose `api` service
- `GET /api/v1/health` (and basic `/ready`)

### Phase B — JWT + `GET /me`
- JWKS validation
- Resolve `app_user` by `app_user_id` claim (or username = id)
- Return Me payload; create/update `user_session` for device
- Bootstrap script so at least one EA exists in DB **and** Keycloak

### Phase C — active-unit + sign-out
- `PUT /me/active-unit`, `POST /me/sign-out`

### Phase D — Invites + Keycloak Admin + email
- preview / accept / create / list / resend / cancel
- On create/accept: Keycloak Admin user + `pixorex-web` / `pixorex-mobile` role
- Email with `http://localhost:5173/activate#token=<raw-token>` (store only hash)

### Phase E — Wire web to real API
- Point Vite proxy to `:8000`
- E2E: invite → Mailpit → activate → Keycloak code → `/me` → dashboard

### Phase F — Later
- Internal keycloak-events, outbox worker, remaining S2 admin APIs

---

## 5. Data / security rules (must follow)

- Verify JWT: `iss` = configured realm, `aud` contains `pixorex-api`, `exp` valid, `azp` ∈ `{pixorex-web, pixorex-mobile}`.
- Never trust roles from the token for RBAC — only `app_user_id` / `tenant_id` + DB `user_unit_role`.
- API DB role: **`pixorex_app`** (not owner); `SET LOCAL app.tenant_id`, `app.user_id`, etc. per transaction (RLS).
- Invite token: random secret in email; **only SHA-256 (or similar) hash** in `invite.token_hash`.
- Invite preview/accept are public (no Bearer) — use a controlled lookup that still avoids cross-tenant leaks (baseline README open point #6).
- Technician invites → Keycloak role `pixorex-mobile`; admin → `pixorex-web`.

---

## 6. Local run (target)

```powershell
# Already: Keycloak + Mailpit + Postgres 18 + baseline SQL
.\keycloak\scripts\kc.ps1 up
docker compose up -d postgres api

# Bootstrap one EA (DB + Keycloak)
python -m api.scripts.bootstrap_tenant --name "Demo" --ea-email ea@demo.local

# Web against real API
# web/.env.local: VITE_OIDC_AUTHORITY=http://localhost:8180/realms/pixorex
npm run dev   # proxy /api → :8000
```

---

## 7. Done when

- [ ] `GET /api/v1/me` returns units/roles for a Keycloak-signed-in user backed by Postgres
- [ ] Admin can `POST /invites`; invite email appears in Mailpit with `/activate#token=`
- [ ] Accept + Keycloak email code activates; dashboard loads from real `/me`
- [ ] Sign-out revokes DB session and Keycloak SSO works with `/signed-out`
- [ ] No Prism required for this path

---

## 8. Implementation order (next actions)

1. Write this plan ✅  
2. **Phase A** — skeleton + compose ✅ (`api/app`, `api/Dockerfile`, compose `api` service)  
3. **Phase B** — JWT + `/me` + bootstrap ✅ (`auth/jwt.py`, `routers/me.py`, `scripts/bootstrap_tenant.py`)  
4. **Phase C–D** — sessions + invites + KC Admin + mail ✅ (code present; exercise via uvicorn)  
5. **Phase E** — web proxy → `:8000` + manual E2E ✅ (proxy default + `web/.env.local`; run stack and sign in as EA)

**Local notes:** app Postgres is on host port **5433** (avoids clash with another Postgres on 5432). Set `KC_API_ADMIN_SECRET` from Keycloak. Run API from `api/` venv with `uvicorn app.main:app --port 8000`. Web: `npm run dev` proxies `/api/v1` to `:8000` unless `VITE_API_PROXY_TARGET` points at Prism `:4010`.

Phone change and internal audit endpoint stay deferred.
