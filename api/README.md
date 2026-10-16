# Pixorex API (FastAPI)

Slice S2 bridge between **Keycloak** (tokens / Admin API) and **Postgres** (`app_user`, invites, sessions).

Plan: `docs/api-slice-s2-invite-signin-plan.md`.

## Run locally (host)

```powershell
cd api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e .

# From repo root, ensure Postgres + Keycloak + Mailpit are up, then:
$env:KC_ISSUER="http://localhost:8180/realms/pixorex"
$env:KC_API_ADMIN_SECRET="<from Keycloak Clients → pixorex-api-admin → Credentials>"
$env:SMTP_HOST="localhost"
$env:SMTP_PORT="1025"
uvicorn app.main:app --reload --port 8000
```

Or use Compose (`api` service) once the image is built.

## Bootstrap an EA

```powershell
cd api
python scripts/bootstrap_tenant.py --ea-email ea@demo.local --name "Demo Tenant"
```

## Health

- http://localhost:8000/api/v1/health  
- http://localhost:8000/api/v1/ready  

## Web

Point Vite at this API (stop Prism mock) and set:

```env
VITE_OIDC_AUTHORITY=http://localhost:8180/realms/pixorex
VITE_OIDC_CLIENT_ID=pixorex-web
```
