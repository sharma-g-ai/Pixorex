# What the Web Developer Should Do Now

| Field | Value |
|---|---|
| Audience | Web developer (React + TypeScript, `web/`) |
| Keycloak status | Local Keycloak is up: realm, OTP sign-in, theme, seed users, smoke tests |
| Full code guide | `docs/keycloak-client-guide.md` (§5 Web) |
| Short summary | `docs/keycloak-client-guide-summary.md` |
| How Keycloak was built | `docs/keycloak-implementation-e2e.md` |

Keycloak’s job is done for local sign-in. **Your job** is to wire the React app to Keycloak and to the API (or mock API until `/me` exists).

---

## 1. Mental model (what you build vs Keycloak)

| You build | Keycloak already provides |
|---|---|
| Landing page with **Sign in** button | Email / code pages (theme) |
| `/auth/callback` and `/auth/silent` | OTP send/verify, lockout, technician block on web |
| Token storage (memory) + silent renew | Tokens via Authorization Code + PKCE |
| API client with Bearer + `X-Device-Id` | Claims: `tenant_id`, `app_user_id`, `aud: pixorex-api` |
| Shell / nav from **`GET /me`** | Not roles in the token |
| `/invite` admin flow | First email code activates the account |

You **never** build a password form, code input, or “account locked” screen.

---

## 2. Prerequisites on your machine

1. Docker Desktop running.
2. From repo root:
   ```powershell
   .\keycloak\scripts\kc.ps1 up
   .\keycloak\scripts\kc.ps1 seed
   ```
3. Confirm discovery (use your port if `.env` sets `KC_HTTP_PORT`, e.g. `8180`):
   - http://localhost:8080/realms/pixorex/.well-known/openid-configuration  
4. Optional: prove sign-in without the app:
   ```powershell
   .\keycloak\scripts\kc.ps1 login web
   ```
   Codes: http://localhost:8025  

Ask the Keycloak owner for the exact **issuer URL** on your team’s laptops if ports differ.

---

## 3. Config to put in the web app

Use env vars (e.g. Vite); do not hard-code secrets (there is **no** client secret).

| Variable | Local value |
|---|---|
| Issuer / authority | `http://localhost:8080/realms/pixorex` (or `http://localhost:8180/realms/pixorex` if that is your Keycloak port) |
| Client id | `pixorex-web` |
| Redirect URI | `http://localhost:5173/auth/callback` |
| Silent renew URI | `http://localhost:5173/auth/silent` |
| Post-logout URI | `http://localhost:5173/signed-out` |
| Scopes | `openid profile email` |
| API base | Vite proxies `/api/v1` → `http://127.0.0.1:8000` (real FastAPI). Prism: set `VITE_API_PROXY_TARGET=http://127.0.0.1:4010` |

These redirect URIs are already registered on the Keycloak client. If your Vite port is not `5173`, tell the Keycloak owner so the realm can be updated.

---

## 4. Build checklist (in order)

### Step A — OIDC library and auth module

- Add `oidc-client-ts` (recommended).
- Create `UserManager` with the config above.
- Keep tokens **in memory** only (REQ-01.13). See `docs/keycloak-client-guide.md` §5.1.

### Step B — Routes

| Route | Behaviour |
|---|---|
| `/auth/callback` | `signinRedirectCallback()` → navigate to saved return path |
| `/auth/silent` | `signinSilentCallback()` (iframe renew) |
| Landing / Sign in | `signinRedirect()` |
| Protected app routes | Require user; else redirect to Sign in |

### Step C — Bootstrap on load

1. Try `signinSilent()` (SSO cookie).
2. If it fails → show Sign in.
3. After a user exists → call **`GET /me`** (or mock) and render the shell.

### Step D — API client

Every authenticated call:

```text
Authorization: Bearer <access_token>
X-Device-Id: <uuid once per browser, e.g. localStorage>
```

- On **401**: silent refresh once, retry once; still 401 → clear user, Sign in.
- On **403**: re-fetch `/me`, show unit-access message.
- Never use password grant.

### Step E — Role-based UI from `/me`

- Enterprise Admin vs BU Admin navigation comes from **`GET /me`**, not JWT claims.
- Unit switch: `PUT /me/active-unit` — never a new Keycloak login.

Prefer the real FastAPI on `:8000` (Phase E). Use Prism only if the API is down (`VITE_API_PROXY_TARGET=http://127.0.0.1:4010` + `npm run api:mock`).

### Step F — Admin invite page (`/invite`)

1. Read invite token from `#t=…`, then strip it from the URL.
2. `POST /invites/preview` → `POST /invites/accept { token, full_name }`.
3. `signinRedirect({ login_hint: email })` → user enters **email code** in Keycloak → activation.
4. Details: client guide §5.5.

### Step G — Sign-out

1. `POST /me/sign-out` (when API exists).
2. `signoutRedirect({ id_token_hint })`.

---

## 5. How to test with the running Keycloak

| Scenario | How |
|---|---|
| First-time / invited admin | Seed user `ea@demo.local` (email not verified) or your invite flow; code in Mailpit |
| Returning admin | `buadmin.p04@demo.local` |
| Technician on web | `tech1@demo.local` → Keycloak should block (“use the mobile app”), no code sent |
| Dual role on web | `dual@demo.local` → email code only |
| Token claims | After callback, decode access token: `tenant_id`, `app_user_id`, `aud` includes `pixorex-api` |

Mailpit: http://localhost:8025  

If SSO skips the login UI, open Incognito or logout:  
`http://localhost:<port>/realms/pixorex/protocol/openid-connect/logout`

---

## 6. What you wait on from others

| Dependency | Owner | Impact |
|---|---|---|
| Exact local issuer port | Keycloak owner / `.env` | Authority URL in Vite env |
| Real `GET /me`, invites, sign-out | API | Use mock until ready |
| Production issuer / HTTPS redirects | Ops | Swap env for deploy |
| Theme polish vs dashboard | Optional with Keycloak owner | Visual only |

You do **not** wait on SMS gateway for web — web is **email only**.

---

## 7. Done when

- [ ] Sign in from the React app opens Keycloak and returns to `/auth/callback` with tokens  
- [ ] Reload uses silent renew / SSO when the Keycloak session exists  
- [ ] API calls send Bearer + `X-Device-Id`  
- [ ] Shell uses `/me` (or mock) for roles; token is not used for RBAC  
- [ ] Technician seed user cannot complete web sign-in  
- [ ] Sign-out clears the app session and Keycloak SSO  
- [ ] `/invite` happy path works against API or mock + Keycloak email code  

---

## 8. Pointers

| Need | Doc / command |
|---|---|
| Copy-paste React samples | `docs/keycloak-client-guide.md` §5 |
| Design / threat model | `docs/keycloak.md` |
| Start Keycloak | `.\keycloak\scripts\kc.ps1 up` |
| Seed users | `.\keycloak\scripts\kc.ps1 seed` |
| Headless Keycloak checks | `.\keycloak\scripts\kc.ps1 smoke` |
| E2E implementation overview | `docs/keycloak-implementation-e2e.md` |

Grade reminder: client token handling is **A0** — write it by hand; architect co-signs the PR (`docs/keycloak-client-guide.md`).
