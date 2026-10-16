# Keycloak Local Setup — Simple Summary

A plain-language summary of `docs/keycloak-local-setup-plan.md`: what we are building for Keycloak on our laptops, and what the web and mobile developers can do once each part is ready.

## What we are building

Keycloak is the service that **signs people in** to Pixorex. Nobody has a password. Users type their email (or phone number on mobile), get a **6-digit code** by email or SMS, and type it in. Keycloak then gives the app a **token**, a signed pass the app sends to our API on every call.

We are setting this up to run **on our own laptops** with Docker, using fake (synthetic) users only. Locally, emails and SMS messages are not really sent. They all land in a test inbox called **Mailpit** (`http://localhost:8025`), so anyone can read the codes.

## The pieces, in order

| Step | What it means in simple terms |
|---|---|
| 1. Start Keycloak | Keycloak runs in Docker next to the database and Mailpit |
| 2. Set up the realm | Create the "Pixorex" space in Keycloak: the two apps (web and mobile), which links each app returns to, what the token contains, how long sessions last, and the lockout rule |
| 3. Plugin project | A small Java add-on for Keycloak, because Keycloak can't send sign-in codes by email or SMS out of the box. It builds inside Docker, so nobody needs Java installed |
| 4. Email code sign-in | The sign-in screens: enter email or phone, choose SMS or email, enter the code. Web users (admins) get email only. Technicians are blocked from the web dashboard |
| 5. Lockout | 5 wrong codes lock sign-in for 30 minutes, then it unlocks by itself. Plus limits so nobody can spam codes |
| 6. SMS codes | Technicians can get the code by text. Locally the "text" shows up in Mailpit |
| 7. Sign-in history | Keycloak reports every sign-in, failure and lock so the API can record it in the audit log |
| 8. Pixorex look | The sign-in pages styled to match our designs (MOB-01 and the admin sign-in screen) |
| 9. Helpers | Ready-made test users, a script to try sign-in without any app, and a way to test from a real phone on the same Wi-Fi |
| 10. CI check | An automatic test that sign-in still works whenever Keycloak files change |

## What stays the same for everyone

- The apps **never build their own sign-in form** and never handle codes or passwords. They open Keycloak, Keycloak does the sign-in, and the user comes back to the app signed in.
- After sign-in, the app asks our API **`GET /me`** who the user is and which units and roles they have. Roles are **not** read from the token.
- Every API call sends the token and a device id (`X-Device-Id`).
- Switching units is an API call, not a new sign-in.

## What the web developer can do

| When this is ready | The web developer can… |
|---|---|
| Step 2 (realm) | Point the React app at Keycloak (`pixorex-web`, `http://localhost:8080/realms/pixorex`) and build the sign-in button, the callback page and the "stay signed in after reload" logic |
| Step 4 (email codes) | Sign in for real as an admin with the code from Mailpit and see the token. Build the role-based navigation (Enterprise Admin vs BU Admin) from `GET /me`, using the mock API until the real endpoint is ready |
| Step 4 + test users | Try every admin case: first-time sign-in (activation), returning admin, a technician being refused on the web |
| Step 5 (lockout) | See the "locked, try again in N minutes" page (Keycloak shows it; nothing to build) and show lock status in the staff list (BU-01) |
| Step 8 (look) | Help style the sign-in pages so they match the dashboard |
| Anytime | Build the admin **invite page** (`/invite`): it calls our API, then sends the user to Keycloak to receive their first email code |

## What the mobile developer can do

| When this is ready | The mobile developer can… |
|---|---|
| Step 2 (realm) | Set up `flutter_appauth` with `pixorex-mobile` and the `com.pixorex.mobile` return link, and build sign-in, token storage and silent refresh |
| Step 4 (email codes) | Sign in on an emulator or phone with an email code, keep the user signed in for days (needed for offline work), and open Home from `GET /me` (mock API until the real endpoint is ready) |
| Step 6 (SMS) | Sign in with SMS codes (read from Mailpit). Test the **technician invite**: accept the invite in the app, then the first SMS code verifies the phone and activates the account |
| Step 9 (phone testing) | Test on a real phone over Wi-Fi using the laptop's IP address as the Keycloak address |
| Anytime | Build the invite deep link screens, sign-out, and the offline queue rule (scans stay tied to the user and unit they were captured under) |
| Later | Phone-number change. Waiting on a team decision (O-12), so don't build it yet |

## What developers get from the Keycloak owner

- Keycloak address, app ids and return links (in `docs/keycloak-client-guide.md`, section 3)
- A list of ready-made test users (admin, BU Admin, technicians, an invited user, a removed user)
- Where to find codes: Mailpit, `http://localhost:8025`
- Help when something doesn't connect (wrong return link, wrong Keycloak address on a phone)

## Not part of this local setup

Real SMS sending, production servers, keeping Keycloak passwords in Vault, and phone-number change. These come later.

The API side is built separately: `GET /me`, invites, and turning an invited user into an active one. Until those exist, the apps can sign in with Keycloak and use the mock API for everything else.

## More detail

- How Keycloak is designed for Pixorex: `docs/keycloak.md`
- Step-by-step guide with code for app developers: `docs/keycloak-client-guide.md` (short version: `docs/keycloak-client-guide-summary.md`)
- Full build plan: `docs/keycloak-local-setup-plan.md`
