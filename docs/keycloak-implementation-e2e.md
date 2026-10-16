# Keycloak Implementation — End-to-End Guide

| Field | Value |
|---|---|
| Audience | Team (Keycloak owner, web/mobile, API, ops) |
| Status | Local Keycloak stack implemented and testable |
| Design | `docs/keycloak.md` |
| Local ops | `keycloak/README.md` |
| App integration | `docs/keycloak-client-guide.md` |
| Web next steps | `docs/keycloak-web-developer-next-steps.md` |

This document describes **what was built**, **what you need installed**, **how the pieces fit**, and **how to verify** end-to-end on a laptop.

---

## 1. What we built (summary)

Pixorex uses **Keycloak** for sign-in only: email or SMS one-time codes, **no passwords**. Apps never render the code UI; they open Keycloak, get tokens, then call the API.

| Piece | Location | Purpose |
|---|---|---|
| Docker stack | `docker-compose.yml` | Keycloak 26.8, Postgres (`keycloak-db`), Mailpit, audit event-sink |
| Realm as code | `keycloak/realm/realm-pixorex.json` | Clients, roles, OTP browser flow, lockout, claims, SMTP (Mailpit locally) |
| Custom SPI (Java) | `keycloak/spi/` | Identifier, app gate, lock check, channel, OTP; SMS providers; audit listener |
| Login theme | `keycloak/themes/pixorex/` | Pixorex sign-in pages and code email templates |
| Helper scripts | `keycloak/scripts/kc.ps1` | `up`, `seed`, `login`, `smoke`, `build`, `reset`, … |
| CI | `.github/workflows/keycloak.yml` | Build SPI + headless smoke on Keycloak changes |

**Not in this Keycloak package (owned elsewhere):** Postgres app data, invite APIs, `GET /me`, React/Flutter OIDC wiring, production Vault, real SMS account credentials (P-3).

---

## 2. Requirements (what to install)

### 2.1 On the developer machine

| Requirement | Why |
|---|---|
| **Windows** (PowerShell) | Scripts under `keycloak/scripts/*.ps1` |
| **Docker Desktop** | Runs Keycloak, DB, Mailpit, event-sink |
| **Git** | Clone the repo |
| **Browser** | Admin console, Mailpit, interactive `login` test |
| **~4 GB free RAM** for containers | Keycloak + Postgres + Mailpit |

You do **not** need a local JDK for day-to-day use: `kc.ps1 build` compiles the SPI inside a Maven Docker image.

### 2.2 Optional / later

| Requirement | When |
|---|---|
| SendGrid (or other SMTP) API key | Real email codes instead of Mailpit |
| Amzur SMS gateway URL + API key | Real SMS (`KC_SMS_PROVIDER=amzur`) — from Amzur/ops (P-3) |
| Web app on port 5173 | Full app ↔ Keycloak redirect testing |
| API with `POST /internal/keycloak-events` | Real audit sink instead of event-sink |

### 2.3 Images / versions used locally

| Component | Version / image |
|---|---|
| Keycloak | `quay.io/keycloak/keycloak:26.8.1` |
| Keycloak DB | `postgres:16` |
| Mailpit | `axllent/mailpit:latest` |
| Event sink (mock audit) | `mendhak/http-https-echo:latest` |
| SPI build | `maven:3.9-eclipse-temurin-21` (one-off container) |

### 2.4 Default local credentials (synthetic only)

| Item | Default |
|---|---|
| Admin console | `admin` / `local-only` |
| Keycloak DB password | `local-only` |
| Ports | HTTP `8080`, management `9100` (override in `.env`; some machines use `8180`) |

Copy `.env.example` → `.env` only when you need port or SMS/SMTP overrides. Never commit `.env`.

---

## 3. Architecture (how login works)

```text
┌─────────────┐     redirect / system browser      ┌──────────────────┐
│ Web / Mobile│ ─────────────────────────────────► │ Keycloak         │
│ app         │ ◄── auth code → tokens (PKCE) ──── │ realm: pixorex   │
└──────┬──────┘                                    │ + SPI + theme    │
       │ Bearer + X-Device-Id                      └────────┬─────────┘
       ▼                                                     │
┌─────────────┐                                    ┌─────────▼─────────┐
│ Pixorex API │ ◄── GET /me (roles, units) ─────── │ Postgres (app)    │
│             │                                    └───────────────────┘
│             │     (API also creates KC users     ┌───────────────────┐
│             │      on invite via Admin API)      │ Mailpit (local)   │
└─────────────┘                                    │ email + fake SMS  │
                                                   └───────────────────┘
```

### 3.1 Sign-in flow (runtime)

1. App redirects to Keycloak (`pixorex-web` or `pixorex-mobile`).
2. Custom flow: identifier → app gate (web vs mobile roles) → lock check → channel → OTP.
3. Code sent by email (realm SMTP) or SMS (`mailpit` / `log` / `amzur`).
4. Correct code → authorization code → app exchanges for tokens (PKCE).
5. App calls **`GET /me`**; UI roles come from the API, not from the token.

### 3.2 Where users come from

| Environment | Who creates the Keycloak user |
|---|---|
| Local manual test | Admin console or `kc.ps1 seed` |
| Real product | **API** on invite/bootstrap (Admin API + `pixorex-api-admin` client) |

Keycloak stores identity for OTP. **Postgres** stores tenants, units, and authorization.

---

## 4. What is in the repo (implementation map)

### 4.1 Realm (`realm-pixorex.json`)

- Clients: `pixorex-web`, `pixorex-mobile` (public + PKCE), `pixorex-api`, `pixorex-api-admin`
- Roles: `pixorex-web`, `pixorex-mobile` (which **app** may sign in — not API RBAC)
- Claims scope `pixorex-claims`: `tenant_id`, `app_user_id`, audience `pixorex-api`
- Brute force: 5 failures → 30 minutes temporary lock
- Tokens: access 5 minutes; refresh rotation on; web without `offline_access` by default; mobile may use offline
- Login theme `pixorex`; SMTP host `mailpit` for local

### 4.2 SPI authenticators

| Step | Factory id | Role |
|---|---|---|
| Identifier | `pixorex-identifier` | Email (web) or email/phone (mobile); no account enumeration |
| App gate | `pixorex-app-gate` | Technician blocked on web; admin-only blocked on mobile |
| Lock check | `pixorex-lock-check` | Locked users see locked page before a code is sent |
| Channel | `pixorex-channel` | Email vs SMS rules by client and user state |
| OTP | `pixorex-otp` | Issue/verify 6-digit codes, throttle, activation flags |

### 4.3 SMS providers

| Provider | Use |
|---|---|
| `mailpit` (default) | Local: SMS appears in Mailpit |
| `log` | CI / logs only |
| `amzur` | Real HTTPS gateway via `PIXOREX_SMS_*` env vars |

### 4.4 Audit

Listener `pixorex-audit` POSTs signed events to `PIXOREX_AUDIT_ENDPOINT` (default: local `event-sink`). Production will point at `POST /internal/keycloak-events` with a shared HMAC secret.

### 4.5 Theme

Pages under `keycloak/themes/pixorex/login/` (identifier, channel, code, locked, etc.) and email templates for the code.

---

## 5. How to run and verify (E2E on laptop)

From the **repo root** (`Pixorex/`), with Docker Desktop running:

```powershell
.\keycloak\scripts\kc.ps1 up       # first run builds the SPI jar (~10–15 min)
.\keycloak\scripts\kc.ps1 seed     # synthetic users
.\keycloak\scripts\kc.ps1 login web
.\keycloak\scripts\kc.ps1 login mobile
.\keycloak\scripts\kc.ps1 codes    # latest codes in Mailpit
.\keycloak\scripts\kc.ps1 smoke    # automated headless checks
```

### Useful URLs (defaults; use your `.env` port if set)

| What | URL |
|---|---|
| Admin console | http://localhost:8080/admin |
| Discovery | http://localhost:8080/realms/pixorex/.well-known/openid-configuration |
| Health | http://localhost:9100/health/ready |
| Mailpit | http://localhost:8025 |
| Audit mock | `docker compose logs -f event-sink` |

### Seeded test users

See `keycloak/scripts/seed-users.json` and `keycloak/README.md` (e.g. `ea@demo.local`, `tech1@demo.local`).

### Notes from local testing

- **SSO:** After `login web`, `login mobile` in the same browser may skip the code screen (same Keycloak session). Use Incognito or logout:  
  `http://localhost:<port>/realms/pixorex/protocol/openid-connect/logout`
- **Real email:** Configure realm SMTP (e.g. SendGrid) in the console; prove with a pixorex user + `login web`. Admin **Test connection** may stay disabled for temporary admins — real sign-in is the proof.
- **Real SMS:** Requires Amzur gateway credentials in `.env`; without them keep `KC_SMS_PROVIDER=mailpit`.

---

## 6. Configuration reference (env)

| Variable | Purpose | Local default |
|---|---|---|
| `KC_HTTP_PORT` / `KC_HOSTNAME` | Host port and issuer URL | `8080` / `http://localhost:8080` |
| `KC_MGMT_PORT` | Health/metrics on host | `9100` |
| `KC_ADMIN_USER` / `KC_ADMIN_PASSWORD` | Bootstrap admin | `admin` / `local-only` |
| `KC_DB_PASSWORD` | Keycloak Postgres | `local-only` |
| `KC_SMS_PROVIDER` | `mailpit` \| `log` \| `amzur` | `mailpit` |
| `PIXOREX_SMS_*` | Amzur gateway (URL, auth, sender, format, body) | empty |
| `PIXOREX_AUDIT_ENDPOINT` / `PIXOREX_AUDIT_SECRET` | Audit POST target + HMAC | event-sink + local secret |

See `.env.example`. Deployed environments load secrets from **Vault**, not git.

---

## 7. Related documents

| Doc | Content |
|---|---|
| `docs/keycloak.md` | Full design (flows, threats, production) |
| `docs/keycloak-local-setup-plan.md` | Original phased build plan |
| `docs/keycloak-local-setup-summary.md` | Plain-language plan summary |
| `docs/keycloak-client-guide.md` | Code-level guide for web and mobile |
| `docs/keycloak-web-developer-next-steps.md` | What the web developer should do now |
| `keycloak/README.md` | Commands, URLs, troubleshooting |

---

## 8. Still out of scope / later

- Real SMS provider account wiring (P-3) and US 10DLC / India DLT as required
- Vault Agent rendering of Keycloak secrets
- Production image + keycloak-config-cli (no `--import-realm` as the update path)
- API invite activation endpoints and Keycloak user provisioning (PX-01-T05/T08)
- Phone change action (blocked on O-12)
