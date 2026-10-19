# Pixorex API for the mobile app

For the Flutter app (technician screens). Written 19 Oct 2026 by the API side. The machine-readable source of truth is `contracts/*.yaml`; this page is the guide.

**Who owns what.** The API and the contracts belong to the API side; `mobile/` belongs to the app. If a screen needs data the API doesn't give, ask the API side and we change the contract first, then the code. Don't work around it.

---

## 1. Run the backend on your laptop

Follow [local-setup.md](local-setup.md) (`docker compose up -d` from the repo root). Then:

| What | Address |
|---|---|
| API | `http://<host>:8000/api/v1` |
| Keycloak (sign-in) | `http://<host>:8080/realms/pixorex` |
| Mailpit (emails **and** SMS codes) | `http://localhost:8025` |

**Testing on a phone or emulator.** The phone can't use `localhost`. Put your laptop's network address in `.env` and restart:

```
KC_HOSTNAME=http://192.168.1.20:8080
```

This changes both the sign-in address and the token issuer the API checks, so they stay the same. Then use `http://192.168.1.20:8000/api/v1` for the API. If the phone can't connect, allow ports 8000 and 8080 through the laptop's firewall.

**Test accounts** (all in company "PPG", unit Plant 04):

| Email | Phone | Role |
|---|---|---|
| tech1@demo.local | +15550100001 | Technician, active |
| tech2@demo.local | +15550100002 | Technician, invited (phone not verified yet) |
| dual@demo.local | +15550100003 | Technician in Plant 04 and BU Admin in Plant 05 |

Sign-in codes go to Mailpit. An SMS shows up there as an email to `sms+<digits>@…`.

---

## 2. Sign-in (Keycloak)

| Setting | Value |
|---|---|
| Client id | `pixorex-mobile` (public client, no secret) |
| Flow | Authorization Code + PKCE (S256) in the system browser (AppAuth) |
| Redirect URI | `com.pixorex.mobile:/oauth2redirect` |
| Sign-out redirect | `com.pixorex.mobile:/logout` |
| Optional scope | `offline_access` |

Keep tokens in secure storage (Keychain / Keystore). Refresh without asking the user. Five wrong codes lock sign-in for 30 minutes (Keycloak shows the lock).

**Sign-out:** call `POST /me/sign-out`, then end the Keycloak session.

The **token handling in the app is A0**: it needs architect sign-off (CONSTITUTION §5).

---

## 3. Every API call

| Header | When | Notes |
|---|---|---|
| `Authorization: Bearer <access token>` | Always, except invite preview and accept | Missing or expired → 401 |
| `X-Device-Id` | Every call, except invite preview and accept | Make it once per install and keep it. Missing → 400 |
| `Idempotency-Key: <uuid>` | Every create and every POST the contract marks | For creating a scan it **must equal** `client_capture_id` |

**Errors** are `application/problem+json`. Read the `type`: `/problems/<code>`, e.g. `/problems/scan-attempts-used`. `detail` is a sentence you can show. Validation errors (400) also carry `errors: [{field, message}]`; some 409s carry `fields` (the labels to show).

**Timestamps** are ISO 8601 with a UTC offset, e.g. `2026-10-19T09:30:00Z`. A time without an offset is refused.

**Lists** are paged: `?limit=` (1–100, default 25) and `?cursor=` from `page.next_cursor` (null on the last page).

---

## 4. Endpoints the app uses

All of these are built and tested.

| Screen area | Endpoint | Contract |
|---|---|---|
| Activation | `POST /invites/preview`, `POST /invites/accept` | 1.6, 1.7 |
| Home, unit switch | `GET /me`, `PUT /me/active-unit` | 1.1, 1.2 |
| Sign-out | `POST /me/sign-out` | 1.3 |
| Location picker (cache it) | `GET /business-units/{buId}/locations/published` | 2.9 |
| Equipment types (cache them) | `GET /business-units/{buId}/equipment-types?include=fields`, `GET /equipment-types/{typeId}` | 2.10, 2.12 |
| Capture | `POST /business-units/{buId}/scans` | 2.21 |
| Photos | `PUT /scans/{scanId}/photos/{photoNo}` | 2.22 |
| Upload done | `POST /scans/{scanId}/upload-complete` | 2.23 |
| Results | `GET /scans/{scanId}` | 2.24 |
| Retry, type mismatch | `POST /scans/{scanId}/retry-extraction`, `POST /scans/{scanId}/re-extract` | 2.25, 2.26 |
| Discard | `POST /scans/{scanId}/discard` | 2.27 |
| My Scans | `GET /me/scans` | 3.1 |
| Submit, fix and resubmit | `POST /scans/{scanId}/revisions` | 3.2 |
| Delegated review | `GET /me/review-batches`, `GET /review-batches/{batchId}`, `GET /scans/{scanId}/review`, `POST /scans/{scanId}/decisions` | 3.15, 3.11, 3.4, 3.5 |
| Notifications | `GET /me/notifications`, `POST /me/notifications/{id}/read`, `POST /me/notifications/read-all` | 3.19–3.21 |

---

## 5. Capture, step by step

1. **On the phone:** make `client_capture_id` (a UUID) when the photo is taken, and keep it with the queued scan. The offline queue lives only on the phone.
2. **Create the scan** with `client_capture_id`, `equipment_type_id`, `location_node_id`, `photo_count` (1–4), `captured_at`, and `retake_of_scan_id` for a retake. Send `Idempotency-Key` = `client_capture_id`.
   - **201:** new scan, `processing_status: "uploading"`, with its `record_no`, e.g. `REC-12`.
   - **200:** the same capture was sent before; this is the same scan. Safe after a lost connection, and never counted twice.
   - **409:**
     - `idempotency-conflict`: same id, different details;
     - `type-not-published`;
     - `location-not-published`;
     - `invalid-state`: a retake target that isn't yours, or isn't rejected or "retake required".
3. **Upload each photo**: `PUT /scans/{scanId}/photos/1` … with header `Content-Type: image/jpeg`, the raw JPEG bytes as the body, and header `Content-Digest: sha-256=:<base64 of the SHA-256>:` (RFC 9530).
   - Max 2 MB (2 × 1024 × 1024 bytes).
   - Sending the same number again replaces it.
   - **400:**
     - `photo-too-large`;
     - `digest-mismatch`;
     - `validation`: not a JPEG, or a photo number outside 1–4.
4. **Confirm**: `POST /scans/{scanId}/upload-complete` → **202** `{attempt_no: 1, processing_status: "extracting"}`.
   - Safe to repeat.
   - **409** `photos-missing`: a photo number is missing.
5. **Wait for the AI:** poll `GET /scans/{scanId}` until `processing_status` is `ready_to_review` or `failed`. There is no push.
6. **Results** (`GET /scans/{scanId}`):
   - `fields`: each with `ai_value`, `confidence` and `flag_reasons`.
   - `latest_attempt`: holds `detected_label` and `suggested_type_id` for the type mismatch screen.
   - `photos[].view_url`: signed, valid 15 minutes. Fetch a new one after that.
7. **Then one of these:**
   - **Retry**, only when `failed`;
   - **Re-extract** as another type, only when `ready_to_review`;
   - **Discard**, only before submitting.

   Retry and re-extract need the scan still unsubmitted. **3 attempts** in total, then `409 scan-attempts-used`: retake only.

**Status names** (`processing_status`): `uploading`, `extracting`, `ready_to_review`, `failed`, `retake_required`. `queued_on_phone` exists only on the phone. `review_status`: `draft`, `waiting_for_approval`, `approved`, `rejected`, `closed` (replaced by a retake), `discarded`.

---

## 6. Self-review and submit (`POST /scans/{scanId}/revisions`)

Allowed when the scan is a draft that's `ready_to_review`, or when it was `rejected` (fix and resubmit). Send `Idempotency-Key`.

```json
{
  "fields": [
    {"field_key": "serial", "verification_state": "corrected", "value": "SN-1077"},
    {"field_key": "barcode", "verification_state": "unreadable", "unreadable_reason": "label_worn"},
    {"field_key": "model", "verification_state": "accepted"}
  ],
  "submit_anyway": false
}
```

**Rules:**
- Every field the AI flagged (non-empty `flag_reasons`) needs an entry, else `409 flags-not-reviewed`.
- `accepted` keeps the AI value. Fields you don't send are kept as the AI read them.
- `corrected` needs `value`.
- `unreadable` needs `unreadable_reason` (`label_worn`, `not_on_nameplate`, `covered_or_unreachable`, `other`). `other` needs a `note`.
- A **required** field that ends with no value is empty. Marked unreadable doesn't count as empty.
  - Empty without `submit_anyway: true` → `409 required-fields-empty`, with the labels in `fields`.
  - With it, send those fields as `left_empty`; they're listed in `empty_required_fields`.
- **201:** the scan is now `waiting_for_approval`. After a rejection, the fix goes back to whoever rejected it.

Progress before submitting stays on the phone.

---

## 7. My Scans (`GET /me/scans`)

Your own scans, newest change first. Filters: `bu_id`, `tab`, `review_status`, `equipment_type_id`, `from`, `to` (dates, on the capture time), `q`.

| Tab | Contains |
|---|---|
| `needs_action` | Drafts that are `ready_to_review`, `failed` or `retake_required`, and any `rejected` scan |
| `in_progress` | Drafts that are `uploading` or `extracting`, and `waiting_for_approval` |
| `approved` | `approved` |
| `all` (or none) | Everything, including closed and discarded |

`q` searches the type name, the submitted values (serial etc.) and the location path.

---

## 8. Not ready yet, or different from what you might expect

| Item | What it means for the app |
|---|---|
| **AI extraction is not running yet** (waiting for the AI service key) | After upload-complete, scans stay `extracting`. Ask the API side to move a test scan to `ready_to_review` with AI values if you need to build the results screens before then. |
| Invite link opens the web page `/activate#token=…` | How a technician's link opens the app (deep link or app link) is **not decided**. Agree it with the API side before building T 03–05. |
| Phone number change (1.4, 1.5) | Deprecated (D-08): done inside Keycloak as an application-initiated action. Keycloak doesn't send the event to the API yet (Iswarya). |
| Photo link name | `view_url` in `GET /scans/{scanId}`, `url` in `GET /scans/{scanId}/review`, as each contract says. |
| `photo_count` | Not stored (no database column yet). Upload-complete checks photos 1..n have no gap. Send exactly the photos you said. |
| Monthly scan limit (402) | Counted, never refused yet: where the limit lives is undecided. |
| Rate limit (429) | Not built yet. |
| Photo upload route (O-17) | Through the API, as above. If it changes to direct-to-storage links, the contract changes first. |
