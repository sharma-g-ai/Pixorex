# LabelReader — PoC App Flow (Mobile App)

Simplified PoC. React Native (Expo) mobile app + FastAPI backend. No auth, no database — Excel as storage.

---

```
USER (Mobile App — React Native / Expo)
  │
  ├─ 1. OPEN APP
  │    └─ Home screen with "Scan Label" button + history list
  │
  ├─ 2. SELECT EQUIPMENT TYPE
  │    └─ Picker: Motor | Label | Chiller | Generator | Transformer
  │
  ├─ 3. CAPTURE / PICK IMAGE
  │    ├─ Camera: open device camera with framing overlay
  │    └─ Gallery: pick existing photo from device
  │    └─ Show image preview before uploading
  │
  ├─ 4. TAP "EXTRACT"
  │    └─ POST image + equipment_type to backend /extract
  │    └─ Show loading spinner with progress text (~6-16s)
  │
  │
BACKEND (FastAPI — runs on local network or cloud)
  │
  ├─ 5. RECEIVE IMAGE
  │    └─ Save to /data/images/{timestamp}_{filename}
  │
  ├─ 6. LOAD SCHEMA
  │    └─ Read predefined field list from JSON files
  │         ├─ schemas/motor.json → 27 fields
  │         ├─ schemas/label.json → 11 fields
  │         ├─ schemas/chiller.json → 52 fields
  │         └─ schemas/{type}.json → N fields
  │
  ├─ 7. GPT-5.4 EXTRACTION
  │    ├─ Send: image + schema field list + CoT prompt
  │    ├─ Receive: structured JSON with field values
  │    └─ ~6s motor/label, ~11-16s chiller | $0.01
  │
  ├─ 8. POST-PROCESSING
  │    └─ Flag review_required = true for:
  │         ├─ model_no (always)
  │         ├─ serial_no (always)
  │         ├─ rpm (always)
  │         └─ bearings (always)
  │
  ├─ 9. SAVE TO EXCEL
  │    └─ Append row to data/extractions.xlsx
  │
  └─ 10. RETURN RESULTS
       └─ JSON response → fields + review flags
  │
  │
USER (Mobile App)
  │
  ├─ 11. VIEW RESULTS
  │    ├─ Scrollable card list: Field Name | Extracted Value
  │    ├─ Yellow badge on review_required fields
  │    └─ Tappable image thumbnail → full-screen original image
  │
  ├─ 12. EDIT FIELDS
  │    ├─ Tap any field → inline text input to correct
  │    └─ Changed fields marked with "edited" indicator
  │
  └─ 13. SUBMIT
       ├─ POST corrections to /review/correct
       └─ Updated values written back to Excel
       └─ Success toast → return to home screen
```

---

## Screens (Mobile App)

| # | Screen | Components |
|:-:|--------|------------|
| 1 | **Home** | "Scan Label" button, extraction history list, pull-to-refresh |
| 2 | **Capture** | Equipment type picker → Camera view with frame overlay OR gallery picker → Image preview |
| 3 | **Extracting** | Loading spinner, progress text ("Analyzing label..."), cancel button |
| 4 | **Results** | Image thumbnail (tap to expand), field list with values, yellow flags, "Edit" / "Submit" buttons |
| 5 | **Edit Field** | Tap a field → editable text input, "Save" / "Cancel" |
| 6 | **History Detail** | View past extraction (read-only or re-edit) |

---

## What's IN This PoC

| Feature | Included | Details |
|---------|:--------:|---------|
| Mobile app (iOS + Android) | YES | React Native (Expo) |
| Camera capture | YES | expo-camera with framing overlay |
| Gallery picker | YES | expo-image-picker |
| Equipment type selector | YES | Picker from predefined list |
| Image preview before upload | YES | Confirm before sending |
| GPT-5.4 extraction | YES | Core extraction with schema prompt |
| Review flags | YES | model_no, serial_no, rpm, bearings |
| Edit + submit corrections | YES | Inline edit on results screen |
| Excel storage | YES | openpyxl — extractions.xlsx |
| Extraction history | YES | List of past extractions on home screen |
| Predefined schemas | YES | JSON files for 3-5 equipment types |

## What's NOT in This PoC

| Feature | Reason |
|---------|--------|
| Login / auth | Not needed for demo |
| PostgreSQL / SQLite | Excel is simpler, easy to share |
| Image preprocessing | Send raw image to GPT |
| On-device quality gate | Skip blur/glare checks for PoC |
| Two-pass auto-discovery | Only known equipment types |
| Batch extraction | One image at a time |
| Offline queue | Requires network for GPT call |
| Docker | Backend runs locally with `uvicorn` |

---

## API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/` | GET | Serve web UI (HTML page) |
| `/extract` | POST | Image + type → GPT extraction → save to Excel → return JSON |
| `/schemas` | GET | List available equipment types |
| `/extractions` | GET | Read all extractions from Excel |
| `/review/correct` | POST | Update corrected field values in Excel |
| `/download` | GET | Download extractions.xlsx |

---

## File Structure

```
LabelReader/
├── backend/
│   ├── main.py                  # FastAPI app + all endpoints
│   ├── extraction.py            # GPT-5.4 call + prompt builder
│   ├── excel_store.py           # Read/write extractions.xlsx (openpyxl)
│   ├── schemas/
│   │   ├── motor.json           # 27 fields
│   │   ├── label.json           # 11 fields
│   │   ├── chiller.json         # 52 fields
│   │   ├── generator.json
│   │   └── transformer.json
│   ├── static/
│   │   ├── index.html           # Main web UI
│   │   ├── style.css
│   │   └── app.js               # Upload, display, edit logic
│   ├── data/
│   │   ├── images/              # Uploaded images stored here
│   │   └── extractions.xlsx     # All extraction results
│   ├── requirements.txt
│   └── .env                     # OPENAI_API_KEY
├── documents/
│   ├── APP_FLOW.md              # Full production flow
│   ├── POC_APP_FLOW.md          # This file
│   ├── PRESENTATION_SUMMARY.md
│   └── report.md
└── frontend/                    # Empty (not used in PoC)
```

---

## Technology Stack (PoC Only)

### Backend

| Component | Choice | Why |
|-----------|--------|-----|
| **API** | FastAPI | Async, typed, auto-docs at /docs |
| **GPT client** | OpenAI Python SDK | Async, structured output |
| **Excel storage** | openpyxl | Read/write .xlsx, no DB setup |
| **Image handling** | Pillow | Resize for GPT, save uploads |
| **Config** | python-dotenv | Load OPENAI_API_KEY from .env |

### Mobile App (Flutter)

| Component | Choice | Why |
|-----------|--------|-----|
| **Framework** | Flutter (Dart) | Cross-platform, better camera control |
| **Camera** | camera package | Full camera access with preview |
| **Image picker** | image_picker package | Gallery selection |
| **HTTP client** | http package (Dart) | Official Dart team, lightweight |
| **State** | Provider (ChangeNotifier) | Simple, built-in Flutter pattern |
| **Navigation** | Navigator (built-in) | No extra dependency needed |
| **UI** | Material 3 (built-in) | Native Material Design widgets |

### Backend requirements.txt

```
fastapi
uvicorn[standard]
python-multipart
openai
openpyxl
pillow
python-dotenv
```

### Frontend pubspec.yaml (key dependencies)

```yaml
dependencies:
  flutter:
    sdk: flutter
  camera: ^0.11.1
  image_picker: ^1.1.2
  http: ^1.3.0
  provider: ^6.1.5
```

---

## Excel Structure — extractions.xlsx

### Sheet: "extractions"

| Column | Type | Example |
|--------|------|---------|
| extraction_id | UUID | a1b2c3d4-... |
| timestamp | datetime | 2026-04-02 14:30:00 |
| equipment_type | string | motor |
| image_filename | string | 20260402_143000_nameplate.jpg |
| fields_json | JSON string | {"model_no":"BO254YLL3AM","volts":"230/460",...} |
| review_flags_json | JSON string | {"model_no":true,"serial_no":true,"rpm":true} |
| status | string | pending / reviewed / submitted |
| reviewed_by | string | (empty for PoC — no auth) |

One row per extraction. Fields stored as JSON string in a single cell — easy to parse, easy to view in Excel.

---

## Schema JSON Format

Example: `schemas/motor.json`

```json
{
  "equipment_type": "motor",
  "display_name": "Motor Nameplate",
  "fields": [
    "manufacturer", "location", "country", "model_no", "type", "form",
    "frame_no", "duty", "hp", "poles", "ins_class", "nema_des",
    "nema_code", "service_factor", "volts", "hz", "rpm", "amp",
    "serial_no", "max_amb_c", "nom_fl_eff", "bearing_ls", "bearing_os",
    "usable_208v_amp", "temp_device_type", "csa_temp_code",
    "hazardous_locations"
  ],
  "always_review": ["model_no", "serial_no", "rpm", "bearing_ls", "bearing_os"]
}
```

---

## Build Plan

### Backend (~3 hours)

| # | Task | Time | Deliverable |
|:-:|------|:----:|-------------|
| 1 | FastAPI project setup + schema JSON files | 30m | Server running at :8000, 3-5 schemas |
| 2 | `/extract` endpoint + GPT-5.4 integration | 60m | Image upload → GPT returns structured JSON |
| 3 | Excel read/write (openpyxl) + review flags | 30m | Extractions saved to .xlsx |
| 4 | Remaining endpoints (`/schemas`, `/extractions`, `/review/correct`, `/images`) | 30m | Full API complete |
| 5 | Test all endpoints via /docs | 30m | Verified with Swagger UI |

### Mobile App (~5 hours)

| # | Task | Time | Deliverable |
|:-:|------|:----:|-------------|
| 1 | Flutter project setup + Provider state | 30m | App launches, screens navigate |
| 2 | Home screen — "Scan Label" button + history list | 30m | Lists past extractions from API |
| 3 | Capture screen — equipment picker + camera + gallery | 60m | Take photo or pick from gallery |
| 4 | Frame overlay + image preview before upload | 30m | User confirms image before sending |
| 5 | Extracting screen — API call + loading animation | 30m | Sends image, shows spinner |
| 6 | Results screen — field list + yellow review badges | 45m | Scrollable card list with flags |
| 7 | Edit field + submit corrections | 45m | Tap to edit, POST corrections |
| 8 | Polish + error handling + real device testing | 30m | Handles network errors, empty states |

### Integration (~1 hour)

| # | Task | Time | Deliverable |
|:-:|------|:----:|-------------|
| 1 | End-to-end test: capture → extract → review → submit | 30m | Full flow works on device |
| 2 | Bug fixes | 30m | Stable demo |

### Total: ~9 hours (1 developer + Copilot)

---

## Timing (User Perspective)

| Step | User Sees | Duration |
|------|-----------|----------|
| Open app | Home screen | <1s |
| Pick equipment type | Picker modal | 2-3s |
| Take photo / pick from gallery | Camera / gallery | 5-10s |
| Preview + tap Extract | Image preview | 2s |
| Extraction in progress | Loading spinner | ~6-16s |
| Review results | Field card list | User-dependent |
| Edit + submit | Inline editing | User-dependent |
| Back to home | Updated history | <1s |
