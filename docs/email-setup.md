# Email: Mailpit or SendGrid

Two things send email:

| Sender | Sends |
|---|---|
| Keycloak | 6-digit sign-in codes |
| API | Invite emails (activation link) |

Both use the same setting, so they always go to the same place.

## The two choices

| | Mailpit (default) | SendGrid (real email) |
|---|---|---|
| Where mail goes | Local test inbox: http://localhost:8025 | The person's real inbox |
| Who can sign in | Demo users (`ea@demo.local` …) and anyone | Only real, invited email addresses |
| Needs | Nothing | A SendGrid API key and a verified sender |
| Limits | None | SendGrid plan limit (free: about 100 emails a day) |
| Use it for | Daily development | Testing with real people |

## Use Mailpit

1. In `.env`, put `# ` in front of every `PIXOREX_SMTP_` line (or delete those lines).
2. Run `.\scripts\setup-local.ps1`
3. The script prints `Local email: Keycloak sends codes to Mailpit`.
4. Codes and invites now arrive at http://localhost:8025

## Use SendGrid

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
2. Run `.\scripts\setup-local.ps1`
3. The script prints `Real email: Keycloak sends codes through smtp.sendgrid.net`.
4. Sign in with a real email that was invited. `@demo.local` addresses get no code.

## Check which one is on

```powershell
docker compose exec api python -c "from app.core.config import get_settings; print(get_settings().smtp_host)"
```
`mailpit` = Mailpit, `smtp.sendgrid.net` = SendGrid.

## When a code doesn't arrive

1. On the sign-in page you see **"We could not send your code"**.
2. Find the reason:
   ```powershell
   docker compose logs keycloak | Select-String "Failed to send|Authentication failed"
   ```
3. Match it:

| Log says | Meaning | Fix |
|---|---|---|
| `Maximum credits exceeded` | The SendGrid account has used up its emails | Switch to Mailpit now; ask the SendGrid owner to upgrade or wait for the reset |
| `535` / `Bad username / password` | Wrong or revoked key | Put the new key in `.env`, run the setup script again |
| `550` / sender not verified | `PIXOREX_SMTP_FROM` isn't a verified sender in SendGrid | Use the verified address |
| Nothing, but no mail | Mailpit is on and you checked your real inbox, or the email was typed wrong | Look in http://localhost:8025 |

## Rules

- `.env` is git-ignored: never commit it, never paste keys in chat.
- A key that was shared in chat counts as exposed: revoke it and create a new one.
- Resetting Keycloak (`kc.ps1 reset`) goes back to Mailpit; run the setup script again after.
- Deployed environments: the same settings come from Vault, not `.env` (PX-10-T03).
