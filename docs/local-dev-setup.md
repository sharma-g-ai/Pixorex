# Local development setup — Keycloak, API, and Web

End-to-end guide to run **Keycloak**, the **FastAPI** Slice S2 API, and the **React** admin dashboard on one Windows laptop. Synthetic / local-only credentials only; never commit `.env` or secrets.

Related docs: `keycloak/README.md`, `api/README.md`, `web/README.md`, `docs/keycloak-implementation-e2e.md`, `docs/api-slice-s2-invite-signin-plan.md`.

---

## 1. What you will run

| Piece | Role | Typical URL |
| --- | --- | --- |
| Docker: Postgres 18 (app) | App DB (`pixorex`) | `localhost:5433` |
| Docker: Keycloak DB + Keycloak | Sign-in (email/SMS codes) | `http://localhost:8180` (or `:8080` if free) |
| Docker: Mailpit | Local inbox for codes / invites | UI `http://localhost:8025`, SMTP `:1025` |
| FastAPI (`uvicorn`) | `/api/v1/*` — `/me`, invites, business units | `http://127.0.0.1:8000` |
| Vite (`npm run dev`) | EA / BU Admin UI | `http://localhost:5173` |

Browser calls Keycloak for OIDC, then calls `/api/v1/...` on the Vite origin; Vite **proxies** `/api/v1` to FastAPI `:8000`.

```
Browser ──OIDC──► Keycloak (:8180)
   │
   └── /api/v1/* ──proxy──► FastAPI (:8000) ──► Postgres (:5433)
                                    │
                                    └── invite email ──► Mailpit or SendGrid
```

---

## 2. Prerequisites

| Tool | Notes |
| --- | --- |
| **Docker Desktop** | Running and healthy (`docker info`) |
| **PowerShell** | Scripts under `keycloak/scripts/` |
| **Python 3.11+** (3.12 preferred) | For the API venv |
| **Node.js** | Web package wants Node 24 (`.nvmrc`); Node 22 often works with an engine warning |
| **Git** | Clone of this repo |

Optional: `psql` on the host. If missing, use `docker compose exec -T postgres psql ...`.

---

## 3. One-time: environment files

From the **repo root** (`Pixorex/`):

### 3.1 Root `.env` (git-ignored)

Copy from `.env.example` and adjust ports if needed.

**If port 8080 is taken** (common on Windows), use 8180:

```env
KC_HTTP_PORT=8180
KC_HOSTNAME=http://localhost:8180
KC_ADMIN_USER=admin
KC_ADMIN_PASSWORD=local-only
KC_DB_PASSWORD=local-only
KC_SMS_PROVIDER=mailpit

# FastAPI (when uvicorn runs on the host)
DATABASE_URL=postgresql://pixorex_app:local-only@localhost:5433/pixorex
DATABASE_OWNER_URL=postgresql://pixorex_owner:local-only@localhost:5433/pixorex
KC_ISSUER=http://localhost:8180/realms/pixorex
KC_API_ADMIN_CLIENT_ID=pixorex-api-admin
KC_API_ADMIN_SECRET=<from Keycloak console — Clients → pixorex-api-admin → Credentials>
INVITE_APP_BASE_URL=http://localhost:5173

# Invite SMTP — Mailpit (local) OR SendGrid (same as Keycloak realm SMTP)
SMTP_HOST=localhost
SMTP_PORT=1025
# SMTP_HOST=smtp.sendgrid.net
# SMTP_PORT=587
# SMTP_USER=apikey
# SMTP_PASSWORD=<SendGrid API key>
# SMTP_STARTTLS=true
# SMTP_FROM=myworkmate@amzur.com
# SMTP_FROM_NAME=Pixorex
```

Also set web OIDC in the **same** file or in `web/.env.local` (Vite only reads `VITE_*`):

```env
VITE_OIDC_AUTHORITY=http://localhost:8180/realms/pixorex
VITE_OIDC_CLIENT_ID=pixorex-web
```

### 3.2 `web/.env.local`

```env
VITE_OIDC_AUTHORITY=http://localhost:8180/realms/pixorex
VITE_OIDC_CLIENT_ID=pixorex-web
# Optional: Prism mock instead of FastAPI
# VITE_API_PROXY_TARGET=http://127.0.0.1:4010
```

---

## 4. Start Keycloak stack (Docker)

From repo root:

```powershell
# First time: builds the SPI jar (~10–15 min), then starts containers
.\keycloak\scripts\kc.ps1 up

# Later starts (SPI already built)
.\keycloak\scripts\kc.ps1 up
```

If scripts are blocked:

```powershell
powershell -ExecutionPolicy Bypass -File .\keycloak\scripts\kc.ps1 up
```

Useful commands:

| Command | Purpose |
| --- | --- |
| `.\keycloak\scripts\kc.ps1 status` | Container health |
| `.\keycloak\scripts\kc.ps1 logs` | Keycloak logs |
| `.\keycloak\scripts\kc.ps1 build` | Rebuild SPI after Java changes |
| `.\keycloak\scripts\kc.ps1 reset` | Wipe Keycloak DB and re-import realm |
| `.\keycloak\scripts\kc.ps1 down` | Stop stack |
| `.\keycloak\scripts\kc.ps1 seed` | Seed synthetic Keycloak users |

### Verify Keycloak

| Check | URL / command |
| --- | --- |
| Admin console | `http://localhost:8180/admin` — user `admin` / `local-only` |
| Realm discovery | `http://localhost:8180/realms/pixorex/.well-known/openid-configuration` |
| Health | `http://localhost:9100/health/ready` (or your `KC_MGMT_PORT`) |
| Mailpit | `http://localhost:8025` |

**pixorex-api-admin secret:** Keycloak Admin → realm **pixorex** → Clients → **pixorex-api-admin** → Credentials → copy client secret into root `.env` as `KC_API_ADMIN_SECRET`.

**Optional — real email for Keycloak codes:** set realm SMTP in the console to SendGrid (`smtp.sendgrid.net:587`, user `apikey`, password = API key). Invite emails from FastAPI use the `SMTP_*` vars in `.env` separately.

---

## 5. App database (Postgres baseline)

Compose starts **Postgres 18** on host port **5433** (user/password `pixorex_owner` / `local-only`, DB `pixorex`).

### 5.1 First-time schema

If the volume is empty, create roles/grants and apply baseline SQL.

**Option A — Docker `psql` (no local install):**

```powershell
# From repo root, with postgres healthy:
docker compose exec -T postgres psql -U pixorex_owner -d pixorex -c "SELECT version();"

# If roles/app user missing, run setup as needed (see api/migrations/baseline/README.md).
# Apply baseline (00–09):
Get-Content api\migrations\baseline\run_all.sql -Raw |
  docker compose exec -T postgres psql -U pixorex_owner -d pixorex
```

**Option B — host `psql`:**

```powershell
$env:PGPASSWORD = "local-only"
psql -h localhost -p 5433 -U pixorex_owner -d pixorex -f api/migrations/baseline/run_all.sql
```

Details and role setup: `api/migrations/baseline/README.md`.

### 5.2 Bootstrap an Enterprise Admin (app user + Keycloak)

Creates tenant + EA in Postgres and ensures the Keycloak user (with `app_user_id` / `tenant_id` attributes):

```powershell
cd api
.\.venv\Scripts\Activate.ps1   # after section 6 venv exists
python scripts/bootstrap_tenant.py --ea-email you@company.com --ea-name "Your Name" --name "Demo Tenant"
```

Sign in on the web with that email; the OTP code arrives in Mailpit (or SendGrid if configured).

---

## 6. Start the API (FastAPI)

```powershell
cd api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -U pip
pip install -e .

# Ensure root .env values are loaded (uvicorn cwd = api/).
# config.py reads .env and ../.env. Prefer a clean shell so old SMTP_* env vars do not override the file.

uvicorn app.main:app --reload --port 8000
```

### Verify API

| Check | Expect |
| --- | --- |
| http://localhost:8000/api/v1/health | `{"status":"ok"}` |
| http://localhost:8000/docs | OpenAPI UI |
| http://localhost:8000/api/v1/ready | DB reachable |

Implemented Slice S2 (MVP) paths include: `/me`, `/invites/*`, `/business-units`, `/bu-admins`. Other contract routes (notifications, locations, scans, …) still return **404** until built.

---

## 7. Start the web app

```powershell
cd web
npm install
npm run dev
```

Open **http://localhost:5173**.

| Setting | Value |
| --- | --- |
| Proxy | `/api/v1` → `http://127.0.0.1:8000` (default) |
| Sign-in | Redirects to Keycloak `pixorex-web` |
| Callback | `/auth/callback` |
| Invite activate | `/activate#token=...` (token in the fragment) |

---

## 8. Daily start order (after first setup)

Three terminals from repo root:

```powershell
# 1 — Docker (Keycloak + Postgres + Mailpit)
.\keycloak\scripts\kc.ps1 up

# 2 — API
cd api
.\.venv\Scripts\Activate.ps1
uvicorn app.main:app --reload --port 8000

# 3 — Web
cd web
npm run dev
```

Then: browser → http://localhost:5173 → Sign in → code from Mailpit (or real mail).

---

## 9. Smoke test: invite a BU Admin

1. Sign in as Enterprise Admin (bootstrapped email).
2. **Overview** → **Create unit** → name, facility, **Invite a new BU Admin** with a *different* email.
3. Confirm `POST /api/v1/business-units` → **201** in the API terminal and the unit appears on Overview.
4. Invitee opens the magic link (`/activate#token=...`) → Activate → Keycloak email code → land in the dashboard as BU Admin.

**BU Admin rules (contracts 1.8 / 1.17):**

- Invite only when the unit has **no** BU Admin; otherwise **409 `unit-has-bu-admin`**.
- To replace an admin: remove them first (`POST /bu-admins/{userId}/remove`), optionally with `replacement_invite_email`.

Do **not** invite the same EA email as BU Admin for a clean first test.

---

## 10. Ports cheat sheet

| Service | Host port | Notes |
| --- | --- | --- |
| Keycloak HTTP | `8180` or `8080` | Must match `KC_HOSTNAME` |
| Keycloak management | `9100` (default) | Health |
| App Postgres | `5433` → container `5432` | Avoids clash with local Postgres on 5432 |
| Mailpit UI / SMTP | `8025` / `1025` | |
| FastAPI | `8000` | |
| Vite | `5173` | |

---

## 11. Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Keycloak won’t bind 8080 | Port in use | Set `KC_HTTP_PORT` + matching `KC_HOSTNAME` |
| `GET /me` “couldn’t load account” | User missing `app_user_id` / `tenant_id` in Keycloak | Re-run `bootstrap_tenant.py` for that email |
| Create unit 201 but Overview still empty | Old bug: transaction rollback on generator close | Use current API; recreate the unit |
| Invite in Mailpit not real inbox | `SMTP_*` still on Mailpit | Point FastAPI `SMTP_*` at SendGrid; restart uvicorn |
| `/activate` blank / incomplete | Token lost from `#token=` (Strict Mode) or truncated link | Open the **full** link from the email; keep current web build |
| Accept 409 `unit-has-bu-admin` | Unit already has a BU Admin | Remove via 1.17 (or vacant the role), then invite again |
| Accept 500 UniqueViolation | Same as above (older builds) | Update API; remove previous admin first |
| API ignores `.env` SMTP host | Shell still has old `SMTP_HOST` | Restart uvicorn in a **new** shell |
| Notifications / locations / scans 404 | Not implemented yet | Expected for this MVP |

---

## 12. What not to commit

- `.env`, `web/.env.local`
- `api/.venv/`, `web/node_modules/`
- `keycloak/providers/*.jar` (built by `kc.ps1`)
- SendGrid / SMS API keys

---

## 13. Quick reference — URLs

| What | URL |
| --- | --- |
| Web app | http://localhost:5173 |
| API health | http://localhost:8000/api/v1/health |
| API docs | http://localhost:8000/docs |
| Keycloak admin | http://localhost:8180/admin |
| Mailpit | http://localhost:8025 |
