# Team status and handover (19 Oct 2026)

Branch: `feature/PX-02-mobile-api`. Read this first. It says what is done, what each person does next, and what is waiting on a decision.

| Person | Owns | Works in |
|---|---|---|
| Vishnu | The web dashboard and the whole API (including everything the mobile app calls) | `web/`, `api/`, `contracts/`, `docker-compose.yml` |
| Amrutha | The Flutter mobile app | `mobile/` |
| Iswarya | Keycloak (realm, sign-in codes, SMS, event listener) | `keycloak/` |

**To avoid conflicts:** each person changes only their own folder, on their own branch. Shared points are listed in [section 4](#4-where-we-touch-and-the-rule-for-each).

---

## 1. Done so far

**Web dashboard** (Enterprise Admin and BU Admin), built from the canvas screens:
- Overview, units and the unit page; BU Admins; invites; technicians.
- Location tree setup and publish; equipment types and fields.
- Review queue, scan review, approve and reject, override; delegation to technicians.
- Escalated scans; all scans; audit log; notifications bell; CSV export (large exports as a download link).

**API** (FastAPI, `api/`):
- Every endpoint the web screens use (contracts S2–S5), checked against `contracts/*.yaml` by an automatic test.
- **For the mobile app:** create scan, upload photos, upload complete, scan detail, retry, re-extract, discard, My Scans, submit and resubmit, my review batches. The full guide is [mobile-api.md](mobile-api.md).
- **Worker:** emails, the 24-hour escalation, waiting and stuck-batch alerts, invite expiry, and building large CSV exports into MinIO.
- **Keycloak events:** `POST /internal/keycloak-events` turns sign-in, failed sign-in, session end and lock events into audit rows.
- 193 automatic tests pass.

**Local setup:** one command, [local-setup.md](local-setup.md). Email options: [email-setup.md](email-setup.md).

---

## 2. Amrutha: the mobile app

**Start here:** [mobile-api.md](mobile-api.md). It has how to run the backend, testing on a phone, test accounts, sign-in settings, every endpoint the app calls, the capture flow and the submit rules.

**What to build** (screens: the canvas `Mobile-*` artboards; rules: `ARCHITECTURE.md`, `CONSTITUTION.md`):

| # | Work | Notes |
|---|---|---|
| 1 | Flutter app in `mobile/` (Flutter 3.x, iOS 16+, Android 10+) | Standard Dart lints (CONSTITUTION) |
| 2 | API client, `X-Device-Id` made once per install, tokens in secure storage | Headers and errors: mobile-api.md §3 |
| 3 | Sign-in in the system browser with PKCE (`pixorex-mobile`) | **A0:** token handling needs architect sign-off |
| 4 | Home and unit switch, location picker, equipment types (cached for offline) | |
| 5 | Camera capture, photo checks, offline queue | Queue encrypted (AES-256, hardware-backed key); architect co-signs the encryption |
| 6 | Upload, results, flagged-field review, submit, retake, retry, discard | mobile-api.md §5–6 |
| 7 | My Scans, delegated review, notifications, profile, sign-out | mobile-api.md §4, §7 |
| 8 | Root/jailbreak detection, certificate pinning | ARCHITECTURE: security |
| 9 | Android and iOS builds, testing on real phones | iOS needs a Mac |

**Status (21 Oct 2026), branch `feature/PX-02-Mobile-app`:** rows 1–3 are built. Screens: launch, Sign in (phone and email), Activate from invite, Invite expired/used/cancelled, plus a temporary signed-in screen until Home is built. Signed in and out on a real Android phone against the local stack; 38 app tests pass. Token handling still needs the A0 architect sign-off. How to run it: [mobile/README.md](../mobile/README.md). For Vishnu: the "invite expired" error has no inviter name, which the T 04 screen shows ("R. Kowalski · Process Manager", unit).

**Before you build these, check with Vishnu:**
- How a technician's invite link opens the app (deep link). Not decided yet. Needed for the activation screens (T 03–05).
- Any screen that needs data the API doesn't give. Ask; don't work around it.

**Not ready on the API side yet:** AI extraction. Scans stay "extracting" until it is built. Vishnu can set a test scan to "ready to review" with AI values so you can build the results screens.

---

## 3. Iswarya: Keycloak

| # | Work | Notes |
|---|---|---|
| 1 | **Phone-change event.** Phone change is a Keycloak action (D-08), but the listener does not send an event for it yet. Today it forwards only LOGIN, LOGIN_ERROR, LOGOUT, CODE_TO_TOKEN_ERROR and REFRESH_TOKEN_ERROR (`AuditPayload.java`). | Agree the event format (type name, new number, user) with Vishnu **in writing before building**. The API then saves the number, signs out the other devices, emails the user and writes the audit row. |
| 2 | **Know the new default:** Keycloak's events now go to the API (`http://api:8000/internal/keycloak-events`), checked with the same shared secret. | To only print them again: `PIXOREX_AUDIT_ENDPOINT=http://event-sink:8888/internal/keycloak-events` in `.env`. |
| 3 | **Make the code screens match the canvas `Mobile-*` artboards** (T 05, 08–12). The app hands over to these Keycloak pages (`keycloak/themes/pixorex/login/pixorex-code.ftl`, `template.ftl`) after "Send code", so on the phone they are part of the app. Checked on a real Android phone on 20 Oct against the canvas; differences: <br>• Navy header with the white wordmark (as on the app's own screens), not the white card with the "P" tile. <br>• Six digit boxes, not one input. <br>• Navy pill **Verify** next to a **Resend in 0:42** pill, not a square "Sign in" button and a "Resend code" link. <br>• Separate "Code expires in 5 minutes" line; "2 of 3 resends left" under the buttons. <br>• Red box: "After 5 incorrect codes, sign-in locks for 30 minutes, then unlocks on its own." <br>• Switch link: "No text message? Email the code to …" / "Didn't get it? Text the code to …", not "Use a different email or number". <br>• Wrong code (T 10): red digit boxes and "Incorrect code — 3 tries left", not a red banner. <br>• Title "Enter code" (sign-in); activation (T 05) shows the green "Account activated" badge and "Verify your phone". <br>• Font IBM Plex Sans (the app bundles it; the theme uses the system font). | The canvas is the reference (section 4, Screens). Amrutha can show the phone screenshots side by side. |
| 4 | **Ask "text or email?" only once.** The app's Sign in screen already has the Phone number / Email tabs and sends the choice as `login_hint` (E.164 number or email), but Keycloak then shows its own channel page again before sending the code. | Agree with Amrutha how the app passes the choice (e.g. phone hint means SMS, email hint means email), then skip the channel page when it is given. |
| 5 | **Sign-in events are refused by the API (401).** On the local stack every `POST /internal/keycloak-events` from the listener gets HTTP 401 ("gave up after 3 attempts"), so sign-in, failure and lock audit rows are not written. Looks like the shared secret differs between Keycloak and the API. | Check together with Vishnu (his side checks the secret). |

**API side, so not your work:** the job that re-reads Keycloak's stored events in case some were lost (`docs/keycloak.md` §8.4), and the lock state on the technicians list (O-13). Vishnu does those.

---

## 4. Where we touch, and the rule for each

| Shared point | Rule |
|---|---|
| API contract (`contracts/`, `docs/api-contracts.md`) | Vishnu owns it. To change it: ask Vishnu; the contract changes first, then the code. |
| Keycloak events | Iswarya sets the event format; Vishnu builds the API side to match. Agree it in writing first. |
| `docker-compose.yml`, `.env.example` | Vishnu changes them; others only run them. Ask for a change. |
| Screens | The app follows the canvas `Mobile-*` artboards exactly. A mismatch with the API goes to Vishnu. |

---

## 5. Waiting on decisions

| Item | Waiting for |
|---|---|
| AI extraction through Portkey (scans and "AI assist" for equipment types) | Vishnu: the Portkey key, the model, and OK for the photo-upload library |
| DLP check on exports (O-14) | Lead: what to check, block or warn |
| Retention job (FR-6.6) | Lead: legal hold, minimum values, table shape, delete or anonymise |
| Storing idempotency keys | Lead: a new table (data model change) |
| `photo_count` on a scan | Lead: a new column (data model change). Until then, photos 1..n with no gap |
| Monthly scan limit (402) | Lead: where the limit is stored (PRD open item 9). Scans are counted, not refused |
| A0 security code (signed photo and export links, Keycloak event signature, token handling in web and app) | Architect review and sign-off |
