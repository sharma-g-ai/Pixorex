---
last_mapped_commit: 64405acfa13ec78cf102cb081212fd931bb8a4e4
last_mapped_at: 2026-10-11
---
# External Integrations

**Analysis Date:** 2026-10-11

## APIs & External Services

**OpenAI Vision API:**
- Service: GPT-4/GPT-5.4 multimodal OCR extraction
- What it's used for: Extracts structured field data from equipment nameplates, delivery notes, and industrial labels from images
- SDK/Client: `openai` Python package, Flutter `http` with manual JSON serialization
- Auth: Environment variable `OPENAI_API_KEY` (sent in Authorization header as Bearer token)
- Implementation files:
  - Flutter: `frontend/lib/services/openai_service.dart` (lines 493-674: `extractFields()` method)
  - Backend: `backend/extraction.py` (lines 55-115: prompt construction and API calls)
  - Supabase: `supabase/functions/schema-assist/index.ts` (lines 125-142: schema generation from images)
- Model: `gpt-5.4` (configurable via `frontend/lib/services/config.dart`)
- Temperature: 0 (deterministic extraction)
- Max tokens: 4096 (Flutter), 1400 (schema assist)
- Batch size: Up to 3 images per call

**Google Sheets API:**
- Service: Google Sheets for extraction result syncing and history
- What it's used for: Real-time append of extraction results to a shared Google Sheet, worksheet creation per equipment type
- SDK/Client: `gspread` Python library with `gspread-formatting` for styling
- Auth: Google service account JSON file (path in `GOOGLE_APPLICATION_CREDENTIALS` env var)
- Implementation: `backend/google_sheets.py`
- Scope: `https://www.googleapis.com/auth/spreadsheets`, `https://www.googleapis.com/auth/drive`
- Spreadsheet ID: Environment variable `GOOGLE_SHEET_ID`
- Features:
  - Auto-creates worksheet per equipment type (e.g., "Motor", "Generator")
  - Header formatting: bold white text on indigo background, frozen rows
  - Auto-append on successful extraction
  - Update capability for corrections/reviews

## Data Storage

**Databases:**
- **Supabase PostgreSQL** (primary production backend)
  - Connection: `supabaseUrl` and `supabaseAnonKey` in `frontend/lib/services/config.dart`
  - URL: `https://pdxdwbfzujbqnwmgenas.supabase.co`
  - Client: `supabase_flutter` (Dart) and Supabase JS SDK (Deno)
  - Tables:
    - `records` - Extraction metadata (id, record_type, schema_name, user_email, status, timestamps)
    - `record_images` - Image storage references (storage_path, mime_type, order)
    - `record_current` - Latest extraction state (fields, review_flags, field_confidence)
    - `record_approved` - Human-approved corrections (approved_fields, approved_by)
    - `extraction_runs` - OCR extraction history (provider, model, parsed_output, field_confidence)
    - `schema_templates` - Equipment schemas (schema_name, fields, field_descriptions, mandatory_fields)
    - `prompt_templates` - Extraction prompts (prompt_key, template_body, version)
  - Implementation: `frontend/lib/services/supabase_service.dart` (complete database layer)

- **SQLite** (local device storage fallback)
  - Package: `sqflite` 2.4.2
  - Purpose: Local cache of extractions when offline
  - Location: Device application documents directory

**File Storage:**
- **Supabase Storage** (production image/scan storage)
  - Bucket: `scans`
  - Path pattern: `{recordId}/{imageNumber}_image.{ext}`
  - Signed URL expiry: 1 hour (3600 seconds)
  - Upload method: Multipart with MIME type detection
  - Implementation: `frontend/lib/services/supabase_service.dart` (lines 220-243: upload, lines 472-476: signed URL generation)

- **Local File System** (development/temporary)
  - Backend: `backend/data/images/` directory
  - Frontend: Application documents directory (via `path_provider`)
  - Format: JSON extraction files (`extractions.json`)

**Caching:**
- No external cache service (Redis/Memcached)
- Local device caching via `shared_preferences` for app state
- Supabase uses built-in HTTP caching headers

## Authentication & Identity

**Auth Provider:**
- **Supabase Auth** (for future user login if enabled)
  - Currently disabled; app uses hardcoded `defaultClientEmail: 'client.ppg.demo@amzur.com'`
  - Configuration: `frontend/lib/services/config.dart` (line 15)
  - Airtable: Only Supabase publishable key (not Supabase Auth configured)

**Backend API Authentication:**
- Bearer token in Authorization header
- Token: Environment variable `LABEL_READER_BACKEND_TOKEN`
- Implementation: `backend/main.py` (lines 27-32: `require_api_token()` dependency)

## Monitoring & Observability

**Error Tracking:**
- None detected (no Sentry, Rollbar, or similar)

**Logs:**
- Backend: Stdout/stderr via `console.error()` in Supabase functions
- Frontend: No centralized logging
- Transient errors: Caught and displayed in UI with user-friendly messages

**Analytics:**
- None detected

## CI/CD & Deployment

**Hosting:**
- Frontend: Multi-platform (Android APK, iOS, macOS, Windows, Linux, Web)
- Backend: Python FastAPI server (local development on port 8002)
- Edge Functions: Supabase hosting

**CI Pipeline:**
- None detected (no GitHub Actions, GitLab CI, or equivalent)
- Manual build process documented in `ppg_handoff/BUILD_INSTRUCTIONS.md`

**Build Commands:**
- Flutter: `flutter pub get`, `flutter build apk --debug/--release`, `flutter build ios/macos/windows/linux`
- Python: `pip install -r backend/requirements.txt`
- Deploy: Manual via Supabase CLI for edge functions

## Environment Configuration

**Required Environment Variables:**

**Frontend (Dart):**
- `OPENAI_API_KEY` - Injected via `--dart-define` or build args
- Build flag: `LABEL_SCANNER` (boolean, default: false) controls initial screen

**Backend (Python):**
- `OPENAI_API_KEY` - OpenAI authentication
- `LABEL_READER_BACKEND_TOKEN` - API authentication token
- `LABEL_READER_ALLOWED_ORIGINS` - CORS allow-list (default: `http://localhost:3000,http://127.0.0.1:3000`)
- `GOOGLE_APPLICATION_CREDENTIALS` - Path to Google service account JSON file
- `GOOGLE_SHEET_ID` - Target Google Sheet ID

**Secrets Location:**
- `.env` file in project root (backend directory)
- Note: Secrets are NOT checked into git (file ignored)
- Credentials: Google service account JSON stored separately

## Webhooks & Callbacks

**Incoming:**
- Backend `/extract` endpoint (POST) - receives image upload and extraction request from mobile app
- Backend `/review/correct` endpoint (POST) - receives human corrections

**Outgoing:**
- OpenAI API (HTTP POST) - extraction requests
- Google Sheets API - worksheet creation and row appends
- Supabase - direct HTTP(S) calls for CRUD operations

**Data Flow:**
1. Mobile app captures images → sends to backend or calls OpenAI directly
2. OpenAI API returns JSON with extracted fields
3. Backend saves to Supabase and Google Sheets
4. Supabase Edge Functions (`schema-assist`) call OpenAI for schema generation

## Integration Points Summary

| Service | Purpose | Flow | Implementation |
|---------|---------|------|-----------------|
| OpenAI | OCR extraction | Image → JSON fields | `openai_service.dart`, `extraction.py`, `schema-assist/index.ts` |
| Supabase | Backend storage | App ↔ Supabase DB/Storage/Functions | `supabase_service.dart` |
| Google Sheets | Result sync | Extract → append row | `google_sheets.py` |
| Local Storage | Offline fallback | Device → SQLite/JSON | `local_store.dart` |

---

*Integration audit: 2026-10-11*
