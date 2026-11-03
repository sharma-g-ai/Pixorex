# Phone-change event: proposal for Keycloak → API

Status: **proposal, to agree with Iswarya (Keycloak).** Vishnu, 2 Nov 2026.
Background: D-08 (phone change runs in Keycloak), [keycloak.md §6.9](../keycloak.md), [decisions-o12-o23.md](decisions-o12-o23.md).

## What Keycloak sends

The `pixorex-update-phone` required action, after the code to the new number is correct and `phone_number` / `phone_verified` are saved, fires one event. The existing listener (`AuditPayload`, `POST /internal/keycloak-events`, HMAC-signed) forwards it like the others:

```json
{
  "id": "<Keycloak event id>",
  "type": "CUSTOM_REQUIRED_ACTION",
  "time": 1793611319000,
  "client_id": "pixorex-mobile",
  "user_id": "<Keycloak user id>",
  "app_user_id": "<app_user id>",
  "tenant_id": "<tenant id>",
  "session_id": "<the session that made the change>",
  "ip_address": "10.0.0.7",
  "error": null,
  "details": { "custom_required_action": "pixorex-update-phone" }
}
```

Keycloak changes needed:
1. The required action sends `EventType.CUSTOM_REQUIRED_ACTION` with detail `custom_required_action = pixorex-update-phone`.
2. `AuditPayload.FORWARDED` adds `CUSTOM_REQUIRED_ACTION`.

**The new number is not in the event.** Keycloak stores events for 7 days, so the number would sit in its event table. The API reads it from the user's `phone_number` attribute through the admin API, which it can already do.

A failed attempt (wrong code, number in use) sends nothing to the API. Keycloak keeps its own 5-wrong-codes / 30-minute counter for this action.

## What the API does with it

Once, keyed on the event id (same as other events; the reconciliation job also picks it up):
1. Reads `phone_number` from the Keycloak user, then sets `app_user.phone_number` and `phone_verified_at` (event time). If the number is taken in the database, it logs an alert and changes nothing.
2. Ends the user's other sessions: `user_session` rows except `session_id`'s, and Keycloak sessions and offline tokens except the current one.
3. Emails the user that their number changed (outbox).
4. Writes an audit row: category `users`, action `user.phone_changed`, with the last 4 digits only.

## To agree

- [ ] Event type and detail as above (Iswarya)
- [ ] Number read from Keycloak, not sent in the event (Iswarya, Vishnu)
- [ ] Contracts 1.4 / 1.5 stay deprecated (mobile team, Amrutha)
