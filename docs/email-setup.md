# Email: Mailpit and SendGrid together

Two things send email:

| Sender | Sends |
|---|---|
| Keycloak | 6-digit sign-in codes |
| API | Invite emails (activation link) |

## How routing works (no .env flip)

When SendGrid is configured, **both** paths stay available:

| Address | Where the message goes |
|---|---|
| Real inbox (`you@company.com`) | SendGrid → that inbox |
| Synthetic (`*@demo.local`, `*@pixorex.local`, any `*.local`) | Mailpit → http://localhost:8025 |

You do **not** need to comment/uncomment SMTP lines to switch between demo users and real people.

## Use Mailpit only

1. In `.env`, put `# ` in front of every `PIXOREX_SMTP_` SendGrid line (or leave host as `mailpit`).
2. Run `.\scripts\setup-local.ps1`
3. Codes and invites arrive at http://localhost:8025

## Use SendGrid (real email) + Mailpit (demo)

1. In `.env`, add (or un-comment) these lines. Get the values privately, never through chat:
   ```
   PIXOREX_SMTP_HOST=smtp.sendgrid.net
   PIXOREX_SMTP_PORT=587
   PIXOREX_SMTP_USER=apikey
   PIXOREX_SMTP_PASSWORD=<SendGrid API key>
   PIXOREX_SMTP_STARTTLS=true
   PIXOREX_SMTP_FROM=<verified sender address>
   PIXOREX_SMTP_FROM_NAME=Pixorex
   ```
2. Run `.\scripts\setup-local.ps1` (this also pushes SMTP into Keycloak).
3. Sign in:
   - `ea@demo.local` → code in Mailpit
   - a **real invited** address → code in that inbox

## Real addresses must already be users

Keycloak only sends a code when the email already exists (invited / seeded). Typing a new address shows the code page but **sends nothing** (anti-enumeration). Invite the person first (EA → invite), then they can sign in.

## Check which provider the API uses for real mail

```powershell
docker compose exec api python -c "from app.core.config import get_settings; print(get_settings().smtp_host)"
```
`mailpit` = Mailpit for everyone, `smtp.sendgrid.net` = SendGrid for real addresses (demo still Mailpit).

## When a code doesn't arrive

1. On the sign-in page you see **"We could not send your code"**, or the page appears but nothing arrives.
2. Find the reason:
   ```powershell
   docker compose logs keycloak | Select-String "Failed to send|Authentication failed|Could not send"
   ```
3. Match it:

| Log / symptom | Meaning | Fix |
|---|---|---|
| `Maximum credits exceeded` | SendGrid quota used up | Wait / upgrade; demo users still work via Mailpit |
| `535` / `Bad username / password` | Wrong or revoked key | New key in `.env`, run setup again |
| `550` / sender not verified | `PIXOREX_SMTP_FROM` isn't verified in SendGrid | Use the verified address |
| Code page but no mail (real address) | That email is not a Keycloak user yet | Invite them first |
| Demo user, empty Mailpit | Plugin not rebuilt after an update | `.\keycloak\scripts\kc.ps1 build` then `restart` |

## Rules

- `.env` is git-ignored: never commit it, never paste keys in chat.
- A key that was shared in chat counts as exposed: revoke it and create a new one.
- Resetting Keycloak (`kc.ps1 reset`) goes back to Mailpit realm SMTP; run the setup script again after for SendGrid.
- Deployed environments: the same settings come from Vault, not `.env` (PX-10-T03).
