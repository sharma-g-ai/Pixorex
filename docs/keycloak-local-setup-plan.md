# Keycloak Local Setup — Implementation Plan

| Field | Value |
|---|---|
| Goal | A local Keycloak that the web and mobile developers can sign in against with email and SMS codes, lockout, the right claims, audit events and the Pixorex login theme. Synthetic data only |
| Design | `docs/keycloak.md` (design), `docs/keycloak-client-guide.md` (what the apps expect) |
| Spec / tasks | SPEC-PX-01 · `STATE.md` tasks PX-10-T01 (Keycloak part), PX-01-T01, T02, T03, T04, T10 |
| Grade | **A0** — realm config and SPI code are written by hand. Every PR needs an architect co-sign (CONSTITUTION §5) |
| Machine | Windows, PowerShell, Docker 29.6 / Compose v5. No Java, Maven, `make` or bash installed: the plugin builds **inside a Maven container**, and every command below is PowerShell |
| Branch base | `pixorex-phase-1` |

---

## 0. Before you start

### 0.1 Decisions to record in `STATE.md` (proposed values are fine for local)

| Item | Local value used in this plan | Final decision by |
|---|---|---|
| Keycloak version | **26.8.1** (24.x is unsupported) — needs architect approval to change the constitution pin | Architects |
| Code TTL / resend cooldown / request limit | 5 min / 60 s / 5 per 15 min | Spec owner |
| Web SSO idle / max | 30 min / 10 h | Owner |
| Mobile offline idle / max | 14 days / 30 days | Owner |
| O-12 (activation and phone-change codes in Keycloak) | Assumed yes for activation. Phone change is **not** in this plan | Manager / TA |

If the architects keep 24.x, steps still apply, with three differences: use `KEYCLOAK_ADMIN` instead of `KC_BOOTSTRAP_ADMIN_*`, health is on port 8080 rather than 9000, and the SPI dependency version changes. Re-verify the lockout behaviour (Phase 5).

### 0.2 Prerequisites

| Tool | Needed? | Notes |
|---|---|---|
| Docker Desktop | ✅ installed | Give it ≥ 4 GB RAM |
| JDK 21 + Maven | Optional | Only for IDE autocomplete in IntelliJ / VS Code. Builds run in `maven:3.9-eclipse-temurin-21` |
| IDE with Java support | Recommended | IntelliJ Community or VS Code + Extension Pack for Java |
| Browser | ✅ | For the admin console, Mailpit and test sign-ins |

### 0.3 Rules that apply to every phase

- One phase ≈ one PR, ≤ 300 lines diff (generated realm JSON may need an exclusion — agree with DevOps on the PR-size exclude list).
- No real secrets. Values in compose and the realm are local-only placeholders.
- Never commit `keycloak/providers/*.jar`, `keycloak/export/`, or anything with a real email or phone.
- Update `STATE.md` in each PR.

---

## Phase overview

| Phase | Output | STATE task | Est. |
|---|---|---|---|
| 1 | Keycloak 26.8 boots in compose with health, Mailpit wiring, helper scripts | PX-10-T01 (KC part) | 0.5 day |
| 2 | Realm as code: settings, roles, clients, claims, brute force, SMTP, events | PX-01-T01 | 1 day |
| 3 | SPI Maven project builds in Docker and loads into Keycloak | PX-01-T02 (setup) | 0.5 day |
| 4 | Email-code sign-in: identifier, lock-check, channel, OTP authenticators + per-client flows | PX-01-T02 | 2 days |
| 5 | Lockout and code-request throttling verified | PX-01-T02 / T03 | 0.5 day |
| 6 | SMS channel with the Mailpit SMS provider | PX-01-T03 | 1 day |
| 7 | Event listener posting to a mock receiver | PX-01-T04 | 1 day |
| 8 | Pixorex login theme | PX-01-T10 | 1–2 days (with the web dev) |
| 9 | Test users script, PKCE test-login script, phone/LAN testing, README | PX-04-T06 (KC part), PX-10-T08 | 0.5 day |
| 10 | CI smoke test | PX-10-T04 | 0.5 day |

S2 ends **Tue Oct 20**. Phases 1, 2, 3, 4 and 9 are demo-critical. Phases 6 and 7 are next. The theme (8) can start in parallel with the web developer as soon as Phase 4 has working pages.

---

## Phase 1 — Keycloak 26.8 boots in compose

### Files

| File | Change |
|---|---|
| `docker-compose.yml` | Upgrade the `keycloak` service (below) |
| `.gitignore` | Add `keycloak/providers/*.jar`, `keycloak/export/`, `keycloak/spi/target/` |
| `scripts/kc.ps1` | Helper commands (Windows replacement for the Makefile targets) |
| `keycloak/realm/realm-pixorex.json` | Minimal realm so the import works (`{"realm":"pixorex","enabled":true}`) |
| `keycloak/themes/pixorex/login/theme.properties` | `parent=keycloak.v2` placeholder so the mount exists |

### `docker-compose.yml` — keycloak service

```yaml
  keycloak:
    image: quay.io/keycloak/keycloak:26.8.1
    command: ["start-dev", "--import-realm"]
    environment:
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://keycloak-db:5432/keycloak
      KC_DB_USERNAME: keycloak
      KC_DB_PASSWORD: ${KC_DB_PASSWORD:-local-only}
      KC_BOOTSTRAP_ADMIN_USERNAME: ${KC_ADMIN_USER:-admin}
      KC_BOOTSTRAP_ADMIN_PASSWORD: ${KC_ADMIN_PASSWORD:-local-only}
      KC_HEALTH_ENABLED: "true"
      KC_METRICS_ENABLED: "true"
      KC_HOSTNAME: ${KC_HOSTNAME:-http://localhost:8080}
      KC_LOG_LEVEL: ${KC_LOG_LEVEL:-info,com.amzur.pixorex:debug}
      KC_SPI_THEME_CACHE_THEMES: "false"
      KC_SPI_THEME_CACHE_TEMPLATES: "false"
    ports: ["8080:8080", "9000:9000"]
    volumes:
      - ./keycloak/realm:/opt/keycloak/data/import:ro
      - ./keycloak/themes/pixorex:/opt/keycloak/themes/pixorex:ro
      - ./keycloak/providers:/opt/keycloak/providers:ro
    healthcheck:
      test: ["CMD-SHELL", "exec 3<>/dev/tcp/127.0.0.1/9000 && printf 'GET /health/ready HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n' >&3 && grep -q '\"UP\"' <&3"]
      interval: 10s
      retries: 30
    depends_on:
      keycloak-db: { condition: service_healthy }
      mailpit: { condition: service_started }
```

(The Keycloak image has no `curl`, which is why the health check uses bash `/dev/tcp`.)

### `scripts/kc.ps1` — helper commands

| Command | Does |
|---|---|
| `.\scripts\kc.ps1 up` | `docker compose up -d keycloak-db mailpit keycloak` |
| `.\scripts\kc.ps1 logs` | `docker compose logs -f keycloak` |
| `.\scripts\kc.ps1 build` | Builds the SPI jar in Docker and copies it to `keycloak/providers/` (Phase 3) |
| `.\scripts\kc.ps1 restart` | `docker compose restart keycloak` (needed after a new jar) |
| `.\scripts\kc.ps1 reset` | Stops `keycloak` and `keycloak-db`, removes volume `pixorex_kcdata`, starts again → fresh realm import |
| `.\scripts\kc.ps1 export` | Exports the realm to `keycloak/export/realm-pixorex.json` (Phase 2) |
| `.\scripts\kc.ps1 seed` | Creates synthetic users (Phase 9) |
| `.\scripts\kc.ps1 login web\|mobile` | PKCE test login (Phase 9) |

### Steps

1. Create the files above; `mkdir keycloak\providers` (add `.gitkeep`).
2. `.\scripts\kc.ps1 up`, then `docker compose ps` until keycloak is `healthy` (first start ~60 s).
3. Open `http://localhost:8080/admin` → sign in `admin` / `local-only`.

### Done when

- [ ] `http://localhost:9000/health/ready` returns `"status": "UP"`
- [ ] Realm `pixorex` exists after a clean `reset`
- [ ] Mailpit at `http://localhost:8025` is up
- [ ] README "Quick start" lists the PowerShell commands

---

## Phase 2 — Realm as code (PX-01-T01)

Work in the admin console, then **export** and commit. That's faster and less error-prone than hand-writing the JSON (especially the user profile and flow ids). Review every line of the export diff.

### 2.1 Realm settings

| Console location | Setting |
|---|---|
| Realm settings → General | Display name `Pixorex`, unmanaged attributes **Disabled** |
| Realm settings → Login | User registration off, Forgot password off, Remember me off, Email as username off, Login with email **on**, Duplicate emails off, Verify email off, Edit username off |
| Realm settings → Email | From `no-reply@pixorex.local`, host `mailpit`, port `1025`, no auth, no SSL/StartTLS. Click **Test connection** (needs an email on the admin user) |
| Realm settings → Themes | Login theme `pixorex` (after Phase 8; keep default until then) |
| Realm settings → Sessions | SSO idle 30 min, SSO max 10 h, Offline idle 14 days, Offline max limited **on** 30 days |
| Realm settings → Tokens | Access token lifespan 5 min, Revoke refresh token **on**, max reuse 0 |
| Realm settings → Security defenses → Brute force | Lockout temporarily · Max login failures 5 · Strategy Multiple · Wait increment 30 min · Max wait 30 min · Failure reset time 30 min · Quick login check 1000 ms · Minimum quick login wait 1 min · Max temporary lockouts 0 · **Max secondary auth failures 0** |
| Realm settings → Security defenses → Headers | CSP `frame-src 'self'; frame-ancestors 'self' http://localhost:5173; object-src 'none';` |
| Realm settings → User events | Save events **on**, expiration 7 days. Event listeners: `jboss-logging` (add `pixorex-audit` in Phase 7) |
| Realm settings → Admin events | Save events on, include representation **off** |
| Realm settings → User profile | Add attributes `app_user_id`, `tenant_id`, `phone_number`, `phone_verified`. For each: **Who can edit = Admin**, **Who can view = Admin**, not required. Validator on `phone_number`: pattern `^\+[1-9]\d{7,14}$` |
| Realm roles | Create `pixorex-web`, `pixorex-mobile` |
| Realm roles → `default-roles-pixorex` | Remove `manage-account` and `view-profile` (account console off) |

### 2.2 Client scope `pixorex-claims`

Client scopes → Create `pixorex-claims` (OpenID Connect, include in token scope off). Mappers:

| Mapper | Type | Config |
|---|---|---|
| `tenant_id` | User Attribute | attribute `tenant_id`, claim `tenant_id`, String, access + ID + userinfo |
| `app_user_id` | User Attribute | attribute `app_user_id`, claim `app_user_id`, String, access + ID + userinfo |
| `phone_verified` | User Attribute | attribute `phone_verified`, claim `phone_verified`, boolean, access token only |
| `api-audience` | Audience | included custom audience `pixorex-api`, access token |

### 2.3 Clients

| Client | Settings |
|---|---|
| `pixorex-web` | Client authentication **off** · Standard flow **on** · Direct access grants **off** · Implicit off · Device grant off · Root/Home URL `http://localhost:5173` · Valid redirect URIs `http://localhost:5173/auth/callback`, `http://localhost:5173/auth/silent` · Post-logout `http://localhost:5173/` · Web origins `http://localhost:5173` · Advanced → PKCE method **S256** · Client scopes: add `pixorex-claims` (Default), **remove** `offline_access` |
| `pixorex-mobile` | Same toggles · Redirect URIs `com.pixorex.mobile:/oauth2redirect` · Post-logout `com.pixorex.mobile:/logout` · No web origins · PKCE **S256** · `pixorex-claims` (Default), `offline_access` (Optional) |
| `pixorex-api-admin` | Client authentication **on** · Standard flow off · Direct grants off · **Service accounts on** · Service account roles: `realm-management` → `manage-users`, `view-users`, `query-users` · Credentials: regenerate secret (local only; the API reads it from dev Vault later) |
| `pixorex-api` | Client authentication on, every flow off (audience target only) |

### 2.4 Export and commit

```powershell
.\scripts\kc.ps1 export
# runs: docker compose run --rm --no-deps -v "${PWD}\keycloak\export:/export" keycloak `
#        export --realm pixorex --users skip --file /export/realm-pixorex.json
```

Then:

1. Copy `keycloak/export/realm-pixorex.json` → `keycloak/realm/realm-pixorex.json`.
2. Remove or blank the `pixorex-api-admin` secret in the committed file (`"secret": "**********"` or delete the key). The import generates a new one, and the API gets it from Vault later.
3. `.\scripts\kc.ps1 reset` and confirm everything comes back from the file alone.

### Verification (no sign-in needed yet)

- Clients → `pixorex-web` → Client scopes → **Evaluate** → pick a test user (create one manually with attributes `tenant_id`, `app_user_id`) → **Generated access token** shows `tenant_id`, `app_user_id`, `aud: pixorex-api`.
- Password grant refused (REQ-01.01):

  ```powershell
  Invoke-RestMethod -Method Post http://localhost:8080/realms/pixorex/protocol/openid-connect/token `
    -Body @{grant_type='password'; client_id='pixorex-web'; username='x'; password='y'}
  # expect 400/401 with unauthorized_client
  ```

- Discovery works: `http://localhost:8080/realms/pixorex/.well-known/openid-configuration`.

### Done when

- [ ] Clean `reset` recreates the full realm with no manual steps
- [ ] Evaluated token contains the claims and audience
- [ ] Password grant refused on both public clients
- [ ] No secrets in the committed JSON

---

## Phase 3 — SPI project that builds in Docker

### Layout

```text
keycloak/spi/
├── pom.xml
└── src/
    ├── main/java/com/amzur/pixorex/keycloak/
    │   ├── auth/            IdentifierAuthenticator(+Factory), LockCheckAuthenticator(+Factory),
    │   │                    ChannelAuthenticator(+Factory), OtpAuthenticator(+Factory)
    │   ├── otp/             CodeGenerator, CodeStore (auth-session notes), Throttle (SingleUseObjectProvider)
    │   ├── sms/             SmsSender, SmsSenderFactory, SmsSpi, MailpitSmsSender, LogSmsSender
    │   └── events/          AuditEventListener(+Factory)   (Phase 7)
    ├── main/resources/
    │   ├── META-INF/services/org.keycloak.authentication.AuthenticatorFactory
    │   ├── META-INF/services/org.keycloak.events.EventListenerProviderFactory
    │   ├── META-INF/services/org.keycloak.provider.Spi
    │   ├── META-INF/services/com.amzur.pixorex.keycloak.sms.SmsSenderFactory
    │   └── theme-resources/templates/   (optional: FTL pages shipped with the jar)
    └── test/java/...        JUnit 5 + Mockito unit tests
```

### `pom.xml` essentials

- `packaging jar`, `maven.compiler.release 21`, artifact `pixorex-keycloak-spi`, `finalName pixorex-keycloak-spi`.
- Dependencies, **scope `provided`**, version `26.8.1`: `org.keycloak:keycloak-core`, `keycloak-server-spi`, `keycloak-server-spi-private`, `keycloak-services`.
- Test: `junit-jupiter`, `mockito-core`.
- No other runtime dependencies (they would have to be shaded into the jar). Use JDK `java.net.http.HttpClient` for HTTP calls.

### Build command (inside `scripts/kc.ps1 build`)

```powershell
docker run --rm `
  -v "${PWD}\keycloak\spi:/src" `
  -v "$env:USERPROFILE\.m2:/root/.m2" `
  -w /src maven:3.9-eclipse-temurin-21 `
  mvn -B -q package
Copy-Item keycloak\spi\target\pixorex-keycloak-spi.jar keycloak\providers\ -Force
docker compose restart keycloak
```

The `.m2` mount caches dependencies, so the first build is slow (~2–3 min) and later builds take seconds.

### First provider: a do-nothing authenticator

Ship `PixorexIdentifierAuthenticatorFactory` with id `pixorex-identifier`, returning a form that just says "hello". This proves the build-load loop works.

### Done when

- [ ] `.\scripts\kc.ps1 build` produces the jar and Keycloak restarts cleanly
- [ ] Keycloak log shows the provider loaded (no `ServiceConfigurationError`)
- [ ] Authentication → Create flow → Add step lists **Pixorex Identifier**
- [ ] `mvn test` runs inside the same container

---

## Phase 4 — Email-code sign-in (PX-01-T02)

### 4.1 Authenticators to implement

| Id | Behaviour | Key details |
|---|---|---|
| `pixorex-identifier` | Form with one field. Web config: email only. Mobile config: email or E.164 phone | Resolve by email (`session.users().getUserByEmail`) or by phone (`searchForUserByUserAttributeStream(realm, "phone_number", value)` filtered to `phone_verified=true`, or the pending number for invited users). Honour `login_hint` (prefill or skip). **Unknown or disabled user**: set no user, store a "ghost" flag, continue to a code screen that never accepts anything (no enumeration, nothing sent). `requiresUser() = false` |
| `pixorex-lock-check` | Stops locked users before a code is sent | `session.getProvider(BruteForceProtector.class).isTemporarilyDisabled(session, realm, user)` → render `pixorex-locked.ftl` with minutes left (from the user's login-failure record + 30 min). `requiresUser() = true` |
| `pixorex-channel` | Chooses SMS or email | Execution config `allowedChannels` = `email` (web) or `sms,email` (mobile). Invited technician (`phone_verified != true`) on mobile → SMS only. One channel → set note `otp.channel` and `success()` without UI |
| `pixorex-otp` | Generates, sends, verifies | Factory `getReferenceCategory()` returns **`"otp"`** (otherwise lockout never counts). Generate 6 digits with `SecureRandom`. Store `HMAC-SHA256(code, salt)`, salt, expiry and channel as auth-session notes. Email via `session.getProvider(EmailTemplateProvider.class).setRealm(realm).setUser(user).send(...)` with template `pixorex-code.ftl`. Wrong or expired → `context.failureChallenge(AuthenticationFlowError.INVALID_CREDENTIALS, form)`. Resend action with 60 s cooldown. Success → clear notes. Activation: if email channel and `!user.isEmailVerified()` → `setEmailVerified(true)`; if SMS channel and `phone_verified != true` → set `phone_verified=true`; add event detail `activation=true` |

Execution config values (TTL 300 s, cooldown 60 s, max sends 5 per 900 s, code length 6) come from the factory's `getConfigProperties()`. Defaults are in code, so the realm JSON stays small.

### 4.2 Flows (console, then export)

Authentication → Duplicate `browser` → name `pixorex-web-browser`, then rebuild it:

```text
pixorex-web-browser
├── Authenticate                        sub-flow  REQUIRED
│   ├── Cookie                                   ALTERNATIVE
│   └── Code sign-in                    sub-flow  ALTERNATIVE
│       ├── Pixorex Identifier                   REQUIRED  (config: email)
│       ├── Web access gate             sub-flow  CONDITIONAL
│       │   ├── Condition - user role            REQUIRED  (role pixorex-web, negate on)
│       │   └── Deny access                      REQUIRED  (message: "Use the Pixorex mobile app")
│       ├── Pixorex Lock Check                   REQUIRED
│       ├── Pixorex Channel                      REQUIRED  (config: email)
│       └── Pixorex OTP                          REQUIRED
└── Web access gate (post-cookie)       sub-flow  CONDITIONAL  (same two steps)
```

Repeat for `pixorex-mobile-browser`: identifier config `email,phone`, gate role `pixorex-mobile`, channel config `sms,email`.

Bind them: Clients → `pixorex-web` → Advanced → Authentication flow overrides → Browser flow = `pixorex-web-browser`. Do the same for mobile. Leave the realm's default browser flow as is (the admin console uses the `master` realm, so this is safe). Then export (Phase 2.4).

Ghost users (unknown identifier) skip the gate and lock check because there is no user. Make both steps return `success()` when the context has no user and the ghost flag is set, and let `pixorex-otp` show the code form that always fails **without** calling `failureChallenge` (there is no user to count against).

### 4.3 Minimal templates (proper styling in Phase 8)

`keycloak/themes/pixorex/login/`: `pixorex-identifier.ftl`, `pixorex-channel.ftl`, `pixorex-code.ftl`, `pixorex-locked.ftl`, `messages/messages_en.properties`, and email templates `email/html/pixorex-code.ftl` + `email/text/pixorex-code.ftl`. Set realm login theme and email theme to `pixorex`. Extend `keycloak.v2` so unstyled pages still look acceptable.

### 4.4 Unit tests (write first)

- Code generator: always 6 digits, uniform distribution sanity check, uses `SecureRandom`.
- Verify: correct, wrong, expired, reused-after-success, constant-time compare used.
- Channel rules: web → email; mobile invited → sms; mobile active → both; config parsing.
- Factory category is `"otp"`.

### 4.5 Manual verification

1. `.\scripts\kc.ps1 seed` (Phase 9 script; you can create one admin user by hand until then) → EA user `ea@demo.local`, role `pixorex-web`, `emailVerified=false`.
2. `.\scripts\kc.ps1 login web` → browser opens Keycloak → enter `ea@demo.local` → code arrives in Mailpit → enter it → script prints decoded tokens with `tenant_id` and `app_user_id`. `emailVerified` is now `true` (activation).
3. Enter an unknown email → code screen appears, nothing in Mailpit, no failure counted.
4. Technician-only user on web → "Use the Pixorex mobile app", nothing in Mailpit.
5. Expired code (temporarily set TTL to 30 s in the execution config) → explicit expired message, counted as a wrong code.

### Done when

- [ ] Email sign-in works for `pixorex-web` and `pixorex-mobile`
- [ ] Admin on web gets only email; technician-only user is denied on web before any send
- [ ] Unknown identifier: same screens, nothing sent
- [ ] First sign-in sets `emailVerified=true`
- [ ] Unit tests green in the Docker build; flows and bindings survive `reset`

---

## Phase 5 — Lockout and throttling

### Lockout (AT-03, REQ-01.03)

| Test | Expected |
|---|---|
| 4 wrong codes, then the right one | Signs in. Users → user → **Brute force** shows 0 failures |
| 5 wrong codes | 5th shows the locked page. Admin console shows the user temporarily locked. `GET /admin/realms/pixorex/attack-detection/brute-force/users/{id}` → `disabled: true` |
| Try again while locked | Locked page with minutes left, **no** email sent |
| Wrong codes split across SMS and email (after Phase 6) | Same counter, locks at the 5th |
| Wait 30 min (or locally set wait to 2 min to test, then restore) | Next correct code signs in; one wrong code does not re-lock immediately |

### Throttling (REQ-01.04)

| Test | Expected |
|---|---|
| Press Resend twice within 60 s | Second press refused with a countdown, one email |
| 6 code requests within 15 min (across new sign-in attempts) | 6th refused, nothing sent |
| Two accounts sharing one phone destination (SMS, Phase 6) | Limit applies per destination too |

Throttle keys in `SingleUseObjectProvider`: `pxotp:u:{userId}:{windowStart}` and `pxotp:d:{sha256(destination)}:{windowStart}`, with a lifespan equal to the window.

### Done when

- [ ] All rows above pass. Record the results in the PR description as AT-03 evidence for the S2 demo

---

## Phase 6 — SMS channel (PX-01-T03)

### Implement

| Class | Purpose |
|---|---|
| `SmsSpi` (+ `META-INF/services/org.keycloak.provider.Spi`) | Declares a new SPI `pixorex-sms` |
| `SmsSender` / `SmsSenderFactory` | `void send(String e164, String text)` |
| `MailpitSmsSender` (id `mailpit`) | Sends the SMS text as an email to `sms+<digits>@pixorex.local` via Mailpit SMTP. **Local only** |
| `LogSmsSender` (id `log`) | Logs `SMS to +1555••••001: [code redacted]`. For CI |
| `AmzurSmsSender` (id `amzur`) | Real provider. **Not in this plan** (P-3 open). Stub that throws `UnsupportedOperationException` |

Select the provider with `KC_SPI_PIXOREX_SMS_PROVIDER=mailpit` in compose (add to the keycloak `environment`).

SMS text format:

```text
Pixorex sign-in code: 482913. It expires in 5 minutes. Never share it.

@localhost #482913
```

The domain line is the issuer host (`auth.<domain>` in deployed environments). It enables one-tap autofill on phones.

### Verify

- [ ] Mobile flow, active technician → choose "Text me" → message in Mailpit to `sms+15550100001@pixorex.local` → code works
- [ ] Invited technician (`phone_verified=false`) → only SMS offered, to the pending number → success sets `phone_verified=true` and the token claim `phone_verified: true`
- [ ] Sign-in by phone number as identifier works only for verified numbers (plus the invited pending number)
- [ ] No full number or code in Keycloak logs

---

## Phase 7 — Event listener (PX-01-T04)

The API endpoint `POST /internal/keycloak-events` doesn't exist yet. Use a **mock receiver** locally.

### Compose addition

```yaml
  event-sink:
    image: mendhak/http-https-echo:latest
    environment: { HTTP_PORT: "8888" }
    ports: ["8888:8888"]
```

### Implement `pixorex-audit` (`EventListenerProviderFactory`)

- Config through SPI options: `KC_SPI_EVENTS_LISTENER_PIXOREX_AUDIT_ENDPOINT=http://event-sink:8888/internal/keycloak-events` (later `http://api:8000/internal/keycloak-events`) and the HMAC secret (local placeholder; Vault in Phase 2 of DevOps work).
- Events forwarded: `LOGIN`, `LOGIN_ERROR`, `LOGOUT`, `CODE_TO_TOKEN_ERROR`, `REFRESH_TOKEN_ERROR`, plus the `activation` detail.
- Payload: event id, type, time, realm, client id, user id, `app_user_id` and `tenant_id` (read from the user), IP, error, details. **Never the code, never tokens.**
- Header `X-Pixorex-Signature: sha256=<HMAC of the body>`.
- Delivery happens **after the transaction commits** (`session.getTransactionManager().enlistAfterCompletion(...)`), handed to a bounded executor with 3 retries and backoff. It never throws into the sign-in path.
- Enable it: Realm settings → User events → Event listeners → add `pixorex-audit`, then export.

### Verify

- [ ] Successful sign-in → `docker compose logs event-sink` shows the JSON with a valid signature
- [ ] Wrong code → `LOGIN_ERROR` / `invalid_user_credentials`
- [ ] `docker compose stop event-sink` → sign-in still works and is not slower than ~100 ms extra; the log shows retries then a give-up warning
- [ ] Events also visible in Realm settings → Events (the reconciliation source the API will read later)

---

## Phase 8 — Pixorex login theme (PX-01-T10, with the web developer)

- Base: extend `keycloak.v2` (PatternFly 5), override CSS and the templates from Phase 4. Optional: **Keycloakify** if the web dev wants to write the pages in React. Decide before starting, because it changes the build (the theme becomes a jar in `providers/`).
- Pages: identifier, channel choice (masked destinations), code entry (`autocomplete="one-time-code"`, `inputmode="numeric"`, resend countdown), expired, locked (minutes left), denied ("Use the Pixorex mobile app"), generic error. Mobile-first layout; the same theme serves web.
- Email template `pixorex-code` (HTML + text).
- Theme caching is off in compose, so template edits show on browser refresh without a restart.
- Match the design canvases in `docs/design/README.md` (MOB-01, admin sign-in).

### Done when

- [ ] All pages match MOB-01 / the admin sign-in screens on a phone-size and desktop viewport
- [ ] No Keycloak default pages reachable in the normal flows

---

## Phase 9 — Developer tooling, test users and phone testing

### 9.1 `scripts/kc-seed.ps1` (called by `kc.ps1 seed`)

Uses `kcadm.sh` inside the container, so you don't need to install anything:

```powershell
$kc = { docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh @args }
& $kc config credentials --server http://localhost:8080 --realm master --user admin --password local-only
& $kc create users -r pixorex -s username=<uuid> -s email=ea@demo.local -s enabled=true `
     -s emailVerified=false -s 'attributes.app_user_id=["<uuid>"]' -s 'attributes.tenant_id=["<tenant-uuid>"]'
& $kc add-roles -r pixorex --uusername <uuid> --rolename pixorex-web
```

Synthetic users (fixed UUIDs, so they match the API seed script `seed_synthetic.py` later):

| User | Email | Phone | Roles | State |
|---|---|---|---|---|
| EA | `ea@demo.local` | — | `pixorex-web` | invited (email unverified) |
| BU Admin Plant 04 | `buadmin.p04@demo.local` | — | `pixorex-web` | active |
| Technician 1 | `tech1@demo.local` | `+15550100001` (verified) | `pixorex-mobile` | active |
| Technician 2 (invited) | `tech2@demo.local` | `+15550100002` (pending) | `pixorex-mobile` | invited |
| Admin + technician | `dual@demo.local` | `+15550100003` | both | active |
| Removed | `gone@demo.local` | — | none | disabled |

The script is idempotent: it skips existing usernames. Once the API exists, `bootstrap_tenant.py` and `seed_synthetic.py` replace this script.

### 9.2 `scripts/kc-test-login.ps1` (called by `kc.ps1 login web|mobile`)

A PKCE sign-in without any app, for you and for demos:

1. Generate `code_verifier` (random 64 chars) and `code_challenge` = base64url(SHA-256).
2. Open the browser at `/realms/pixorex/protocol/openid-connect/auth?client_id=...&response_type=code&scope=openid&redirect_uri=http://localhost:5173/auth/callback&code_challenge=...&code_challenge_method=S256&state=...`
3. After sign-in the browser lands on the (not running) callback URL. Paste that URL into the script.
4. The script exchanges the code at the token endpoint and prints the decoded access and ID token claims.

For the mobile client, temporarily add `http://localhost:5173/auth/callback` as an extra redirect URI **only in your local realm**, or have the script listen on `http://127.0.0.1:<port>` (loopback redirect, RFC 8252) and add that to `pixorex-mobile` locally. Do not commit either change.

Optionally, the script reads the code from the Mailpit API (`GET http://localhost:8025/api/v1/messages`) to print it for you.

### 9.3 Phone and emulator testing (PX-10-T08 network check)

1. Find the laptop IP: `(Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Wi-Fi").IPAddress`.
2. Create `.env` (git-ignored) with `KC_HOSTNAME=http://<IP>:8080`, then `.\scripts\kc.ps1 restart`.
3. Allow inbound 8080 and 8025 on the Windows firewall for the **Private** profile only:
   `New-NetFirewallRule -DisplayName "Pixorex KC dev" -Direction Inbound -LocalPort 8080,8025 -Protocol TCP -Action Allow -Profile Private`
4. From the phone browser, open `http://<IP>:8080/realms/pixorex/.well-known/openid-configuration` → `issuer` must show the IP.
5. Give the mobile dev that issuer. The API (when it exists) must use the **same** issuer.
6. Web devs on the same laptop can keep `localhost` only if the API accepts that issuer too. Simplest: everyone uses the IP during the demo week.

### 9.4 README

Add a "Keycloak (local)" section: commands from `kc.ps1`, URLs (admin console, Mailpit, health), seeded users, how to read codes, how to reset, and phone testing.

---

## Phase 10 — CI smoke test (PX-10-T04 keycloak workflow)

On changes under `keycloak/`:

1. Build the SPI with `mvn -B verify` (unit tests).
2. `docker compose up -d keycloak-db mailpit keycloak` and wait for health.
3. Run the seed script (a bash twin of `kc-seed.ps1`, since CI runs on Linux).
4. Headless sign-in test (Playwright or a small Python script with `requests` + HTML form parsing): email code from the Mailpit API → token has `tenant_id`, `app_user_id`, `aud=pixorex-api`.
5. Password grant refused.
6. 5 wrong codes → attack-detection API says `disabled: true`.
7. Trivy scan of the Keycloak image.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Realm changes in the JSON don't show | `--import-realm` skips an existing realm. Run `.\scripts\kc.ps1 reset` |
| New jar not picked up | `.\scripts\kc.ps1 restart`. Check the log for `Updating the configuration and installing your custom providers` |
| `ServiceConfigurationError` at start | Wrong class name in `META-INF/services` or a non-provided dependency missing. Keep all Keycloak deps `provided` |
| Custom step missing in "Add step" | Factory not registered in `META-INF/services/org.keycloak.authentication.AuthenticatorFactory`, or `getId()` collides with a built-in |
| Lockout never triggers | `getReferenceCategory()` isn't `"otp"`, or `failure()` was used instead of `failureChallenge()`, or no user was set before failing |
| Locks permanently after many tests | Max secondary auth failures is not 0, or permanent lockout is on |
| Email not in Mailpit | Realm SMTP host must be `mailpit` (container name), not `localhost` |
| `Invalid parameter: redirect_uri` | URI not registered exactly (port, path, trailing slash) |
| Token `iss` differs between laptop and phone | `KC_HOSTNAME` not set to the LAN IP, or the container was not restarted |
| Docker volume mount errors on Windows | Run commands from the repo root. Use `${PWD}`, and enable file sharing for drive D in Docker Desktop |
| `exec /opt/keycloak/bin/kc.sh: no such file` in `export` | The `run` override must pass `export ...` as arguments, not a full command, because the image entrypoint is `kc.sh` |

---

## Final checklist (local Keycloak "done")

- [ ] Clean clone → `.\scripts\kc.ps1 up` → `seed` → `login web` works in under 15 minutes
- [ ] Realm, clients, flows, mappers, brute force, SMTP, events all come from `keycloak/realm/realm-pixorex.json`
- [ ] Email and SMS (Mailpit) codes work on both clients with the right channel rules
- [ ] Lockout 5 → 30 min → auto-unlock, plus throttling, verified and recorded
- [ ] Activation flips `emailVerified` / `phone_verified` on first sign-in
- [ ] Event listener delivers signed events to the mock sink without ever blocking sign-in
- [ ] Theme matches the designs
- [ ] Web and mobile developers have the issuer, client ids and redirect URIs (`docs/keycloak-client-guide.md` §3) and can sign in from their apps
- [ ] `STATE.md` updated: PX-01-T01/T02/T03/T04/T10 status, decisions recorded (version, TTLs, session lengths)

## Not in this plan

Phone change (blocked by O-12), real SMS provider (P-3), Vault-sourced Keycloak secrets (PX-10-T03), production image and keycloak-config-cli (see `docs/keycloak.md` §10), the API's internal events endpoint and activation logic (PX-01-T05/T08).
