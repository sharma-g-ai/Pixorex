# SPEC-PX-01 — Identity, sessions & invites

| Field | Value |
|---|---|
| Bounded context | BC-01 |
| Grade | **A0** for Keycloak config, OTP authenticators, event listener, request-context middleware and client auth code · A1 for endpoints |
| PRD | FR-1.4, FR-1.5, FR-1.6, FR-1.7, FR-1.8 · journey J02 · screens MOB-01, MOB-02, EA-01, BU-01 |
| Contracts | Slice 1: 1.1–1.11 |
| Release tests | AT-03, AT-12 (part) |
| Sprint | S2 (ends Oct 20, 2026) |
| Status | Draft — awaiting G1 (spec owner + architect) |

## Decisions this spec depends on

| Ref | Question | Proposed answer | Status |
|---|---|---|---|
| O-1, O-2 | Roles; admin login | Settled by PRD: 3 roles; admins sign in by email code, no SAML | Settled |
| O-11 | Active unit location | `user_session.active_bu_id` keyed by `X-Device-Id` (V3 model) | **Decide today** |
| O-12 | Who sends/checks activation and phone-change codes | Keycloak, via required actions using the same OTP authenticator and lock counter; Keycloak event listener tells the API the verified value. Endpoints 1.4–1.5 change accordingly | **Decide today** |
| O-22 | Invites in S2 or S5 | S2 (the contracts already place them in Slice 1) | Settled |
| O-23 | Multi-unit activation | Accepting one link accepts all pending invites for that email; `is_primary` = unit of the oldest invite | **Decide today** |
| P-3 | SMS provider | Amzur's existing account; confirm DLT sender + OTP template | **Confirm today** |
| P-4 | Admin MFA | Email code only for V1 pending owner decision | Open (not blocking S2 build) |
| — | Email provider | Outbox → SMTP adapter; Mailpit locally; provider chosen before a shared environment exists | Open (not blocking) |

Requirements that depend on an undecided item are marked **BLOCKED** and must not be built until the decision is recorded in `STATE.md`.

---

## Requirements

### REQ-01.01 Keycloak realm as code (A0)
Realm `pixorex` is defined in `keycloak/realm-pixorex.json` and imported on container start. Public clients `pixorex-web` and `pixorex-mobile` use Authorization Code + PKCE; no passwords; protocol mappers emit `tenant_id` and `app_user_id` claims.
- GIVEN a clean Compose stack WHEN Keycloak starts THEN the realm, both clients and the mappers exist without manual steps.
- GIVEN a signed-in user WHEN the access token is decoded THEN it contains `tenant_id` and `app_user_id` matching the `app_user` row.
- GIVEN any client WHEN a password grant is attempted THEN Keycloak refuses it.

### REQ-01.02 Sign-in by one-time code (A0) — FR-1.5
Technicians choose SMS or email; admins get email only. Codes are single-use and short-lived **[TBD: TTL, e.g. 5 min]**.
- GIVEN an active technician with a verified phone WHEN they choose SMS and enter the correct code THEN they receive tokens and land in the app.
- GIVEN an active technician WHEN they choose email and enter the correct code THEN they receive tokens.
- GIVEN an active admin WHEN the sign-in page loads THEN only the email option is offered.
- GIVEN a used or expired code WHEN it is entered THEN sign-in fails with an explicit expired/invalid message (MOB-01) and counts as a wrong code.
- GIVEN a user whose `app_user.status` is not `active` WHEN they try to sign in THEN no code is sent and sign-in fails.

### REQ-01.03 Lockout (A0) — FR-1.5, AT-03
- GIVEN a user WHEN the 5th wrong code is entered (counting both channels) THEN sign-in is locked for 30 minutes and the app shows the locked state with time remaining.
- GIVEN a locked user WHEN 30 minutes pass THEN sign-in works again with no admin action.
- GIVEN a lock WHEN it starts THEN one `audit_log` row (category `sign_in`, actor `system`) is written via the event listener.
- GIVEN 4 wrong codes then a correct one THEN sign-in succeeds and the counter resets.

### REQ-01.04 Code-request throttling (A0)
- GIVEN a user WHEN they request more than **[TBD: 5]** codes in **[TBD: 15 min]** THEN further requests are refused without sending, for that user and that destination.

### REQ-01.05 Sign-in event listener (A0) — FR-1.5
A Keycloak event listener posts LOGIN, LOGIN_ERROR and lockout events to an internal, network-restricted API endpoint (not in the public contract) authenticated by a Vault-held shared secret.
- GIVEN a successful sign-in WHEN the event fires THEN an `audit_log` row (`sign_in`) is written with user, tenant and device, and no code value.
- GIVEN the API is unreachable WHEN an event fires THEN the listener retries and does not block sign-in.

### REQ-01.06 Request context middleware (A0) — FR-1.6, FR-1.7, NFR access control
Implements ARCHITECTURE §4.4.
- GIVEN no token, an expired token or a token for another realm WHEN any authenticated endpoint is called THEN 401.
- GIVEN a valid token WHEN `app_user.status` is `removed` THEN 401.
- GIVEN a session whose `revoked_at` is set WHEN a call is made THEN 401 within 60 seconds of revocation.
- GIVEN a valid call WHEN the transaction starts THEN `app.tenant_id`, `app.user_id`, `app.bu_ids`, `app.is_ea` are set with `SET LOCAL` and are absent on the next pooled connection.
- GIVEN `/health`, `/ready`, `/invites/preview`, `/invites/accept` WHEN called without a token THEN they work; every other path requires one.
- GIVEN any call WHEN it completes THEN `app_user.last_active_at` is updated at most once per **[TBD: 5 min]**.

### REQ-01.07 GET /me — contract 1.1
- GIVEN a technician in units X and Y WHEN they call `/me` THEN the response lists both units with role, `is_primary`, `assigned_by_name`, plus `active_bu_id`, `last_bu_id` and `tenant.name`.
- GIVEN an EA WHEN they call `/me` THEN units list the tenant's units with role `enterprise_admin`.
- GIVEN a user removed from unit Y WHEN they call `/me` THEN Y is not listed.

### REQ-01.08 PUT /me/active-unit — contract 1.2 (depends on O-11)
- GIVEN a user with an active role in unit Y WHEN they set `bu_id = Y` with header `X-Device-Id` THEN `user_session.active_bu_id` for that device and `app_user.last_bu_id` become Y, with no new sign-in.
- GIVEN a unit where the user holds no active role WHEN they set it THEN 403.
- GIVEN two devices WHEN one switches unit THEN the other device's active unit is unchanged.

### REQ-01.09 POST /me/sign-out — contract 1.3
- GIVEN a signed-in device WHEN sign-out is called THEN that device's `user_session.revoked_at` is set, an `audit_log` row (`sign_in`) is written, and 204 is returned; the other devices stay signed in.

### REQ-01.10 Create and manage invites — contracts 1.8–1.11, FR-1.4
- GIVEN a BU Admin of unit X WHEN they invite a technician for X THEN one `invite` row per unit is created with the same `token_hash`, `expires_at = now + 24h`, an `outbox_event` for the email, and an `audit_log` row (`users`) — all in one transaction.
- GIVEN a BU Admin WHEN they invite for a unit they do not run THEN 403.
- GIVEN an EA WHEN they invite a BU Admin for a unit that already has one THEN 409 `unit-has-bu-admin`.
- GIVEN a stored invite WHEN the table is read THEN only the token hash is stored, never the token.
- GIVEN `GET /invites` WHEN a BU Admin calls it THEN they see technician invites of their units only; an EA sees BU Admin invites; rows past `expires_at` show `expired`.
- GIVEN a pending or expired invite WHEN it is resent THEN a new token and a new 24 h window are issued and the old link stops working.
- GIVEN an invite WHEN it is cancelled THEN status becomes `cancelled` and the link stops working.
- GIVEN an invite that expires unused THEN an `invite_expired` notification is raised (notification table lands in S4; until then the outbox records the intent) **[confirm with spec owner]**.

### REQ-01.11 Invite preview and accept — contracts 1.6–1.7, FR-1.4 (part BLOCKED by O-12, O-23)
- GIVEN a valid token in the body WHEN preview is called THEN role, email, units, inviter and expiry are returned; the token never appears in a URL or log.
- GIVEN an expired, used or cancelled token THEN 409 `invite-expired` / `invite-used` / `invite-cancelled`.
- GIVEN a valid token WHEN accept is called THEN `app_user` (status `invited`) and one `user_unit_role` per invite row are created, the Keycloak user is created with `app_user_id`/`tenant_id` attributes, the invite is marked used, and an `audit_log` row (`users`) is written in one transaction.
- GIVEN the user then verifies their phone (technician) or email (admin) THEN `app_user.status` becomes `active` — **BLOCKED (O-12)** for the verification mechanism.
- GIVEN a technician WHEN they accept THEN they never gain web dashboard access.
- Multi-invite activation and `is_primary` choice — **BLOCKED (O-23)**.

### REQ-01.12 Phone change — contracts 1.4–1.5, FR-1.8 — **BLOCKED (O-12)**
Target behaviour once decided: change saved only after the code sent to the new number is verified; 5 wrong codes lock phone changes for 30 minutes; success revokes every other session of the user, emails the user and writes an `audit_log` row (`users`); a number already in use → 409 `phone-in-use`.

### REQ-01.13 Client sign-in (A0 for token handling, A2 for screens)
- **Web:** OIDC Authorization Code + PKCE against `pixorex-web`; tokens in memory only; silent refresh; sign-out ends the Keycloak session and calls 1.3.
- **Mobile:** system browser (AppAuth) + PKCE against `pixorex-mobile`; tokens in secure storage (Keychain / Keystore); `X-Device-Id` generated once per install and sent on every call.
- GIVEN a signed-in user WHEN the access token expires THEN the client refreshes without user action.
- GIVEN a locked account WHEN the user returns to the app THEN MOB-01 shows the locked state.

---

## Out of scope for this spec
SAML SSO, role change endpoint (O-16), trusted-reviewer flag (O-18), any password flow, notification bell (S4).
