# PPG Delivery Note Scanner — Implementation Status

**Branch:** `feature/ppg-delivery-note-scanner`  
**Updated:** 24 September 2026  
**Host app:** Pixorex Flutter (`frontend/`)

## Android can scanner — build 36 (5 October 2026)

Version 1.0.5+36 adds a visible scanner action to the receiving list and each
editable receiving row. Live NV21 camera frames use a dedicated bundled ML Kit
channel. The article reader requires a readable Article anchor and three fresh
agreeing frames, preserves leading zeros, and matches the exact current-DN
article before enabling deliberate +1 acceptance. Repeated article occurrences
remain separate and require a target choice in the global scanner.

Accepted scan events and counts share the existing atomic SQLite write. A
stable event ID prevents duplicate acceptance on retries. Current DN/session,
form revision, source checks, target article, PC unit, and count state are
rechecked when saving. Existing manual counting, Finish, Reopen, and source
correction controls remain available.

Validation: 71 Flutter tests passed; static analysis reported no issues. No
Android device was connected for physical camera/cylinder validation. This is
an implementation for device testing, not a measured scanner accuracy claim.

## Repository audit (Phase 0)

| Finding | Detail |
|---|---|
| Framework | Flutter SDK `^3.11.0` in `frontend/pubspec.yaml` |
| Existing OCR | Cloud OpenAI Vision via `openai_service.dart` — **not used by PPG** |
| Existing sync | Supabase + Google Sheets — **not used by PPG** |
| Local store today | JSON (`local_store.dart`) for nameplate extractions |
| Native code | Stock `MainActivity` only before this feature |
| Backend / portal | Out of scope for this slice |

## Decisions

1. **Keep Flutter host app.** PPG is an isolated feature module under `frontend/lib/features/ppg_delivery_note/`.
2. **Android-first OCR.** Bundled ML Kit Latin text recognition via Kotlin MethodChannel `com.amzur.equiptrack/ppg_ocr`. Camera capture reuses Flutter `camera` / `image_picker` with in-app four-corner crop; no Play Document Scanner.
3. **SQLite** via `sqflite` for PPG sessions only — separate from nameplate JSON store.
4. **No network egress** from PPG feature paths (no OpenAI, Supabase, Sheets).
5. **Entry point:** Home screen action → PPG session hub (existing Pixorex flow unchanged).

## Source identity

| Asset | Value |
|---|---|
| PDF | `ppg_handoff/source/DN_5319364114.pdf` |
| SHA-256 | `7c4e1acec8441193375ca36c8f77f935630913adbebd31f78dea3e82d886780c` |
| Golden fixture | `ppg_handoff/fixtures/dn_5319364114.expected.json` |

## Dependency plan

| Package / lib | Purpose |
|---|---|
| `sqflite`, `path` | Local PPG persistence |
| `uuid` (existing) | IDs |
| `camera`, `image_picker` (existing) | Capture / import |
| `com.google.mlkit:text-recognition` (bundled) | On-device OCR |
| Flutter four-corner UI | Perspective crop without Document Scanner |

## Device validation

Automated evidence:

- `python3 ppg_handoff/tools/validate_handoff.py` → **PASS**
- `flutter test test/ppg_delivery_note/` → **13 passed** (phrase + word-level OCR geometry, batch-header isolation, picking-list reject)

Still pending on hardware:

- On-device ML Kit against phone photos of Seastock pages → `NOT_RUN_DEVICE_REQUIRED`
- Physical-paper camera workflow → `NOT_RUN_DEVICE_REQUIRED`

## Post-review hardening (2026-09-24)

Addressed review gaps:

1. Word-level OCR line rebuild; Total/Qty adjacent anchors; scoped batch exclusion; SET from joined lines
2. Original photo retained separately from perspective-warped rectified image; rotate controls
3. Page 1…N checklist; OCR suggests page # without overwriting; confirm/correct + retake
4. Page-count conflict no longer cleared after set
5. Manual shutter always available; optional Auto assist timer
6. ML Kit bridge exports lines + optional symbols

## Isolation rule

PPG code must not call `OpenAiService`, `SupabaseService`, or `SheetsService`.
