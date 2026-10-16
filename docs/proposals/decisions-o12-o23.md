# Decisions D-08, D-09, D-11: sign-in codes, multi-unit activation, web session

16 Oct 2026 · Vishnu (dashboard team, delegated by the lead: "take the best decision for a product going to the marketplace")

Open decisions O-12 and O-23 blocked dashboard screens: BU Admin activation (BU 01, 33) and sign-in and sign-out (PX-01-T12). O-7 (monthly scan limit) is not decided here: no screen shows it, so it stays open for the architect. This note records the decision for each, the options weighed, and every place that changes. Sources: PRD (FR-1.4, FR-6.5, J02, AT-03, open item 9), the V3 data model, contracts v0.3.x, STATE.md proposals, and the Keycloak server administration guide (brute force detection).

## D-08 (O-12): Keycloak sends and checks every one-time code

**Decision.** Keycloak is the only place that sends and checks codes: sign-in, activation (email for BU Admins, phone for technicians) and phone change. The API never stores, sends or checks a code.

- Codes come from the custom OTP authenticators already planned (PX-01-T02 email, PX-01-T03 SMS).
- One counter for all channels: realm brute force detection, temporary lockout, Max Login Failures 5, Wait Increment 30 min, Max Wait 30 min, Failure Reset Time 12 h. That is "5 wrong codes lock sign-in for 30 minutes, then unlock on their own" (PRD J02, AT-03). The authenticators must report a wrong code as a failed login (invalid credentials) so the counter sees it; PX-01-T02/T03 tests must prove this.
- **BU Admin activation (BU 01, 33):** the invite page calls 1.6 and 1.7. 1.7 creates the Keycloak user (email, email not yet verified) and returns `next_step: verify_email`. The web app then starts sign-in with the invited email as `login_hint`; Keycloak emails the code ("Verify your email" screen, BU 33). A correct code proves the inbox, so Keycloak marks the email verified. On the first `GET /me` with `email_verified = true` the API moves `app_user.status` from invited to active.
- **Technician activation and phone change:** the same pattern with the SMS authenticator. Phone change (1.4, 1.5) becomes a Keycloak application-initiated action; the API applies its side effects (save the number, end other sessions, email, audit) from the Keycloak event listener (PX-01-T04). Contract 1.4 and 1.5 are marked deprecated, not deleted, so the mobile team can confirm before removal.

**Why.** One lock counter across email and SMS is a PRD rule, and only one system can own it. Keeping codes out of our database removes a class of secrets from the API. A buyer's security review expects identity checks in the identity provider, not in application code.

**Rejected.** The API checks codes itself: duplicates Keycloak, splits the lock counter, and adds code storage, throttling and expiry to the API. Activation by link only, no code: the PRD (FR-1.4) requires a BU Admin to verify email by code.

## D-09 (O-23): one activation accepts every pending invite for that email

**Decision.** Accepting an invite also accepts every other pending, unexpired invite for the same email in the same tenant, of the same role. The primary unit is the unit of the oldest of those invites. Invites for a different role stay pending.

**Why.** The invite email is the identity; a second link to the same address would otherwise fail after the first activation. The person still proves the inbox with a code before the account is active (D-08). Oldest invite = the unit that has waited longest for this person.

## D-11: web session (completes PX-01-T12 within D-01)

- OIDC Authorization Code with PKCE (S256) through `oidc-client-ts` (already chosen in D-01), public client `pixorex-web`.
- Tokens are kept in `sessionStorage`, not `localStorage`; refresh with refresh tokens, no hidden iframe (third-party cookie blocking breaks iframes).
- Sign-out calls 1.3, then ends the Keycloak session.
- The invite link carries its token in the URL fragment (`/activate#token=…`), so it never reaches a server log or a `Referer` header; the page removes it from the address bar on load.
- Production builds refuse to start without the OIDC settings. The development mock keeps working without Keycloak.

## Places changed

| Place | D-08 | D-09 | D-11 |
|---|---|---|---|
| STATE.md decision table | ✓ | ✓ | ✓ |
| Google Doc "API Contracts" and `docs/api-contracts.md` (1.4, 1.5, 1.6, 1.7, open decisions table) | ✓ | ✓ | ✓ |
| `contracts/slice-s2-auth-rbac.yaml` | ✓ | ✓ | ✓ |
| Web app: activation page, sign-in and sign-out | ✓ | ✓ | ✓ |

## Not done here

- The Keycloak realm, authenticators and event listener (PX-01-T01 to T04) belong to FSD-B. This note sets what they must do.
- Docker and Java are not available on this machine, so sign-in was tested in a real browser against `oidc-provider` 9.12.2 (a certified OpenID Connect server) set up like the planned `pixorex-web` client: redirect to sign-in, PKCE S256, code exchange, return to the requested page, token on every API call, tokens only in `sessionStorage`, sign-out through 1.3 and the provider's logout, sign-in required again afterwards, and `login_hint` after activation. Repeat these checks against the real Keycloak realm once PX-01-T01 lands.
