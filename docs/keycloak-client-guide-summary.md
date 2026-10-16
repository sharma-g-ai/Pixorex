# Keycloak for Web and Mobile — Summary

Short version of `docs/keycloak-client-guide.md`. Read that for code samples and checklists.

## How it works

1. The app never shows a sign-in form, sees a code or stores a password. It opens **Keycloak** (redirect on web, system browser on mobile).
2. Keycloak asks for email or phone, sends the code (SMS or email), checks it, and handles lockout (5 wrong codes → 30-minute lock that lifts on its own).
3. Keycloak returns to the app, and the library exchanges the code for tokens (Authorization Code + PKCE).
4. Every API call sends `Authorization: Bearer <access token>` and `X-Device-Id`.
5. After sign-in, call **`GET /me`** for units, roles and active unit. **Never read roles from the token.**
6. Access tokens last 5 minutes; the library refreshes them silently.
7. Invites are API calls (`/invites/preview`, `/invites/accept`). After accept, a normal sign-in **activates** the account.

## Who builds what

| Keycloak owner | Web developer | Mobile developer |
|---|---|---|
| Realm, clients, redirect URIs, token lifetimes | OIDC sign-in, callback, silent renew, sign-out | AppAuth sign-in, refresh, sign-out |
| Login pages: identifier, SMS/email choice, code, resend timer, expired/invalid/locked messages | API client with headers and 401/403 handling | API client with headers and 401/403 handling |
| Code sending, lockout, throttling, audit events | `/invite` page for admins | Invite deep link for technicians |
| Phone-change action | Role-based navigation from `/me` | Home, unit switch, offline queue tied to the user |

## Key config

| Item | Value |
|---|---|
| Issuer | `http://localhost:8080/realms/pixorex` locally (phones: the laptop's LAN IP) |
| Client ids | `pixorex-web`, `pixorex-mobile` (public, no secret) |
| Web redirect | `/auth/callback` (silent: `/auth/silent`) on port 5173 locally |
| Mobile redirect | `com.pixorex.mobile:/oauth2redirect` |
| Scopes | Web `openid profile email` · Mobile adds `offline_access` |
| Codes locally | Mailpit `http://localhost:8025` (email and SMS) |

## Rules for both

- On 401: refresh once, retry once, then sign the user out locally and show sign-in.
- On 403: the user lost access to that unit. Re-fetch `/me`.
- On invite 409s (`invite-expired`, `invite-used`, `invite-cancelled`, `phone-in-use`): show a clear message.
- Unit switch is `PUT /me/active-unit`, never a new sign-in.
- Don't use embedded WebViews, password grants, or tokens in URLs or logs. Don't build your own wrong-code or locked screens.
- Client auth code is **A0**: written by hand, architect co-signs the PR.

## Web essentials

- `oidc-client-ts`, tokens **in memory**.
- On page load, try a silent sign-in (SSO cookie). If that fails, show the Sign in button.
- Admin invite: read the token from `#t=`, remove it from the address bar, then preview, then accept `{token, full_name}`, then `signinRedirect({login_hint: email})`. The email code activates the account.
- Sign-out: `POST /me/sign-out`, then `signoutRedirect` with `id_token_hint`.
- A technician trying the web app is blocked by Keycloak before any code is sent.

## Mobile essentials

- `flutter_appauth` + `flutter_secure_storage` + `app_links`. Register the `com.pixorex.mobile` scheme on Android and iOS.
- Refresh tokens **rotate** and are single-use. Store the new one every time, and never run two refreshes at once.
- Technician invite: link opens the app, then preview, then accept `{token, full_name, phone_number}`, then `signIn(loginHint: email)`. Keycloak offers **SMS only** to the new number, and that code verifies the phone and activates the account. If the browser is closed midway, offer "Finish setting up" and sign in again; don't repeat the accept call.
- Offline queue: tag each scan with `app_user_id` and `bu_id`. Sync only for the same user, to the original unit. Keep the queue when the session expires.
- Sign-out: `POST /me/sign-out`, revoke the refresh token, clear tokens, keep `X-Device-Id`. Warn if scans are still queued.
- Phone change (`kc_action=pixorex-update-phone`) is **blocked until O-12** is decided.
- Testing on a phone: use the same LAN-IP issuer everywhere. Allow HTTP in debug builds only.

## Delivery order from the Keycloak owner

Realm and clients (PX-01-T01), then email codes (T02), then SMS codes (T03), then login theme (T10), then activation (T05/T08), then test users (PX-04-T06), then phone change (T09, after O-12). Until email codes work, build against the mock API (PX-01-T11) with a stubbed auth service.
