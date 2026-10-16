# Keycloak (local)

Sign-in for the Pixorex web dashboard and mobile app: one-time codes by email or SMS, no passwords.
Design: `docs/keycloak.md`. What web and mobile developers need: `docs/keycloak-client-guide.md`.
End-to-end implementation (what was built, install requirements, how to verify): `docs/keycloak-implementation-e2e.md`.
What the web developer should do next: `docs/keycloak-web-developer-next-steps.md`.
Synthetic data and local-only credentials only. This folder is A0 (architect review required).

## Folder

| Path | What it is |
| --- | --- |
| `realm/realm-pixorex.json` | The `pixorex` realm as code: clients, the `pixorex-browser` sign-in flow, lockout, token settings, mappers |
| `spi/` | Java plugin (Maven): the five sign-in steps, code sending and checking, SMS senders, audit event listener |
| `themes/pixorex/` | Sign-in pages (`login/`) and the code email (`email/`) |
| `providers/` | Where the built plugin jar goes (git-ignored, built by `kc.ps1`) |
| `scripts/` | `kc.ps1` (all commands), seed users, interactive login test, headless smoke test |

## Commands

Run from the repo root (or give the full path to the script from anywhere). Docker Desktop must be running.

```powershell
.\keycloak\scripts\kc.ps1 up            # builds the plugin the first time (about 12 minutes), then starts everything
.\keycloak\scripts\kc.ps1 seed          # creates the synthetic users below
.\keycloak\scripts\kc.ps1 login web     # sign in through the real pages in your browser, prints the token claims
.\keycloak\scripts\kc.ps1 login mobile
.\keycloak\scripts\kc.ps1 codes         # latest codes in Mailpit
.\keycloak\scripts\kc.ps1 smoke         # 53 headless end-to-end checks (also run in CI)
.\keycloak\scripts\kc.ps1 build         # rebuild the plugin after Java changes (runs unit tests), restart Keycloak
.\keycloak\scripts\kc.ps1 reset         # after editing realm-pixorex.json: wipe the Keycloak DB and re-import
.\keycloak\scripts\kc.ps1 export        # export console changes to keycloak/export/ to review and copy into realm/
.\keycloak\scripts\kc.ps1 down | status | logs | restart
```

If scripts are blocked, prefix with `powershell -ExecutionPolicy Bypass -File`.
Theme (`.ftl`, `.css`, `.properties`) edits show on the next page load; Java edits need `build`; realm JSON edits need `reset`.

## URLs

Ports are the defaults; a git-ignored `.env` can change them (see `.env.example`).

| What | URL |
| --- | --- |
| Admin console | http://localhost:8080/admin (local-only credentials in `docker-compose.yml`) |
| Realm discovery (issuer) | http://localhost:8080/realms/pixorex/.well-known/openid-configuration |
| Health | http://localhost:9100/health/ready |
| Mailpit (every email and SMS code) | http://localhost:8025 |
| Audit events sent to the mock API | `docker compose logs -f event-sink` |

## Seeded users (`scripts/seed-users.json`)

The username is the app user id (the API will create users the same way). SMS codes appear in Mailpit addressed to
`sms+<digits>@pixorex.local`.

| Email | Phone | Can use | State |
| --- | --- | --- | --- |
| `ea@demo.local` | - | web | Enterprise Admin, invited: the first email code activates |
| `buadmin.p04@demo.local` | - | web | BU Admin, active |
| `tech1@demo.local` | +15550100001 (verified) | mobile | Technician, active: SMS or email |
| `tech2@demo.local` | +15550100002 (pending) | mobile | Technician, invited: SMS only, the first SMS code activates |
| `dual@demo.local` | +15550100003 (verified) | web and mobile | Admin and technician |
| `gone@demo.local` | - | nothing | Disabled: sees the normal pages, nothing is ever sent |

`seed reset` recreates them as new (invited users invited again).

## Rules the flow enforces

- Web: email only. Mobile: SMS or email for a verified phone; SMS only for an invited technician.
- 6-digit code, valid 5 minutes, resend after 60 seconds, at most 5 codes per 15 minutes per user and per number/email.
- 5 wrong codes lock the account for 30 minutes; a correct code resets the count.
- Unknown, disabled or locked-out identifiers see the same pages and nothing is sent (no account discovery).
- A technician on web is told to use the mobile app, an admin on mobile is told to use the web dashboard.

## Testing on a phone (same Wi-Fi)

1. Find the laptop's LAN IP (`ipconfig`, e.g. `192.168.1.50`).
2. In `.env` set `KC_HOSTNAME=http://192.168.1.50:<KC_HTTP_PORT>`, then `kc.ps1 reset` (the token issuer changes).
3. Allow the port through Windows Firewall on the Private profile only (admin PowerShell):
   `New-NetFirewallRule -DisplayName "Pixorex Keycloak" -Direction Inbound -Protocol TCP -LocalPort 8080 -Profile Private -Action Allow`
4. Point the app at `http://192.168.1.50:<port>/realms/pixorex`. Codes still arrive in Mailpit on the laptop.
5. Remove the rule when done: `Remove-NetFirewallRule -DisplayName "Pixorex Keycloak"`.

## Real values (never in git)

Locally they go in `.env`; in deployed environments they come from Vault.

| Setting | Variables |
| --- | --- |
| Real SMS gateway | `KC_SMS_PROVIDER=amzur`, `PIXOREX_SMS_URL`, `PIXOREX_SMS_AUTH_HEADER`, `PIXOREX_SMS_AUTH_VALUE`, `PIXOREX_SMS_SENDER`, `PIXOREX_SMS_FORMAT`, `PIXOREX_SMS_BODY_TEMPLATE` |
| Audit events to the API | `PIXOREX_AUDIT_ENDPOINT`, `PIXOREX_AUDIT_SECRET` (same secret the API verifies `X-Pixorex-Signature` with) |
| Admin and database passwords | `KC_ADMIN_PASSWORD`, `KC_DB_PASSWORD` |

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Port already in use on `up` | Set `KC_HTTP_PORT` and the matching `KC_HOSTNAME` (or `KC_MGMT_PORT`) in `.env`, then `reset` |
| Realm change not visible | `--import-realm` skips an existing realm: run `reset` |
| No code in Mailpit | `kc.ps1 logs` and look for `Could not send`; check the send limit (5 per 15 minutes) |
| "Account locked" while testing | Admin console > Users > the user > unlock, or wait 30 minutes |
| `invalid_grant` / issuer mismatch on a phone | `KC_HOSTNAME` must be the LAN IP the phone uses, then `reset` |
| Plugin not loaded after a Java change | `kc.ps1 build` (copies the jar into `providers/` and restarts) |
