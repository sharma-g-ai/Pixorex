---
last_mapped_commit: 64405acfa13ec78cf102cb081212fd931bb8a4e4
last_mapped_at: 2026-10-11
---
# Codebase Structure

**Analysis Date:** 2026-10-11

## Directory Layout

```
LabelReader/
├── frontend/                           # Flutter mobile app (Pixorex)
│   ├── lib/                           # Dart application code
│   │   ├── main.dart                  # Entry point: EmailGate → home screen router
│   │   ├── branding/                  # App colors, theme constants
│   │   │   └── app_brand.dart         # AppBrand class (blue, navy, neutral colors)
│   │   ├── screens/                   # General/legacy screens (label scanner)
│   │   │   ├── home_screen.dart       # Label scanner hub
│   │   │   ├── capture_screen.dart    # Image picker for label scanner
│   │   │   ├── results_screen.dart    # Extraction results review
│   │   │   ├── extracting_screen.dart # Loading state during OpenAI call
│   │   │   └── history_detail_screen.dart # Extraction history detail
│   │   ├── services/                  # App-wide services
│   │   │   ├── app_state.dart         # ChangeNotifier: user email, schemas, extractions
│   │   │   ├── openai_service.dart    # OpenAI API client for label extraction
│   │   │   ├── supabase_service.dart  # Supabase auth, sync, RLS queries
│   │   │   ├── local_store.dart       # SQLite persistence for label-scanner extractions
│   │   │   ├── config.dart            # Hardcoded API keys, URLs (OpenAI model, Supabase)
│   │   │   ├── json_helpers.dart      # Utilities for field merging, review note management
│   │   │   └── review_provenance_helpers.dart # Track edited fields, adjust review flags
│   │   ├── widgets/                   # Reusable UI components
│   │   │   └── (custom widgets for label scanner)
│   │   └── features/                  # Feature modules (organized by feature)
│   │       └── ppg_delivery_note/     # Primary feature: PPG Delivery Note digitization
│   │           ├── domain/            # Pure domain models and business logic
│   │           │   ├── models.dart    # Core entities: ScanSession, PageCapture, DocumentLine, OcrElement, OcrObservation
│   │           │   ├── local_submission.dart  # Submission validation (article numbers, piece summary)
│   │           │   ├── source_correction.dart # Correction record type + helpers
│   │           │   ├── validation.dart        # Page/line verification helpers
│   │           │   └── can_article_reader.dart # CAN code validation logic
│   │           ├── services/          # Feature-specific business orchestration
│   │           │   └── ppg_session_controller.dart # ChangeNotifier: session lifecycle, OCR coordination
│   │           ├── persistence/       # Data layer for PPG
│   │           │   └── ppg_repository.dart # SQLite CRUD: sessions, pages, lines, OCR, corrections, adjustments
│   │           ├── ocr/               # Offline OCR integration
│   │           │   ├── ppg_ocr_adapter.dart # Android ML Kit MethodChannel bridge
│   │           │   └── total_qty_field_reader.dart # Specialized crop reader for "Total Qty" field
│   │           ├── parser/            # Document parsing & consolidation
│   │           │   ├── ppg_template_parser.dart # Regex-based delivery-note template parser
│   │           │   ├── ocr_line_builder.dart    # Reconstruct OCR lines from word elements
│   │           │   └── consolidator.dart        # Merge multiple OCR runs into canonical lines
│   │           ├── screens/           # PPG feature UI screens
│   │           │   ├── ppg_hub_screen.dart      # Delivery notes hub (session list, new delivery, open session)
│   │           │   ├── ppg_capture_screen.dart  # Camera/gallery for page capture
│   │           │   ├── ppg_session_screen.dart  # Multi-step form for session processing
│   │           │   ├── ppg_page_identity_screen.dart # Verify delivery note # and page count
│   │           │   ├── ppg_page_review_screen.dart   # Review OCR page details
│   │           │   ├── ppg_can_scanner_screen.dart   # Article number scanner/input
│   │           │   ├── ppg_review_screen.dart        # Full document review (lines, counts)
│   │           │   ├── ppg_confirmation_screen.dart  # Final review before submission
│   │           │   └── ppg_final_review_screen.dart  # Submission validation & confirm
│   │           ├── ui/                # PPG UI tokens, formats, and common widgets
│   │           │   ├── ppg_tokens.dart      # Colors, spacing, typography (Pixorex brand for PPG)
│   │           │   ├── ppg_format.dart      # Date/time/number formatters
│   │           │   ├── ppg_navigation.dart  # ppgPush(), ppgPopToHub() helpers
│   │           │   ├── ppg_page_status.dart # Page progress indicators
│   │           │   └── ppg_widgets.dart     # Common PPG UI components (cards, lists, buttons)
│   │           └── widgets/           # PPG-specific custom widgets
│   │               ├── four_corner_crop.dart   # Page boundary detector (UI for image positioning)
│   │               ├── perspective_warp.dart   # 2D perspective transformation for page rectification
│   │               ├── ppg_physical_quantity_control.dart # Input control for physical counts
│   │               └── ppg_source_summary.dart # Display parsed page summary
│   │
│   ├── test/                          # Test files (co-located with features)
│   │   └── ppg_delivery_note/         # PPG feature tests
│   │       ├── ppg_parser_test.dart   # Template parser unit tests
│   │       ├── ppg_receiving_workflow_test.dart # Integration test: full workflow
│   │       ├── ppg_session_resume_test.dart     # Session persistence test
│   │       ├── total_qty_field_reader_test.dart # Specialized reader unit tests
│   │       ├── can_article_reader_test.dart     # Article number validation tests
│   │       ├── image_preprocessing_test.dart    # Image geometry tests
│   │       ├── dn_5319358250_parser_test.dart   # Real delivery-note sample tests
│   │       ├── dn_5319364114.expected.json      # Golden output for sample test
│   │       ├── dn_5319364114_synthetic_ocr.json # Synthetic OCR fixture
│   │       ├── dn_5319364114_word_level_ocr.json # Word-level OCR fixture
│   │       └── review_provenance_helpers_test.dart
│   │
│   ├── pubspec.yaml                  # Flutter dependencies (Provider, Supabase, sqflite, camera, etc.)
│   ├── analysis_options.yaml          # Linter rules
│   ├── assets/                        # App assets
│   │   ├── app_icon.png              # App launcher icon
│   │   ├── branding/                 # Brand assets (logo, symbol)
│   │   ├── schemas/                  # JSON schema templates for label extraction
│   │   └── ppg/                      # PPG fixture files (synthetic OCR, expected outputs)
│   │
│   └── android/, ios/, macos/, windows/, web/ # Platform-specific Flutter bindings

├── backend/                           # FastAPI Python backend
│   ├── main.py                        # FastAPI app: routes for extract, schemas, extractions
│   ├── extraction.py                  # OpenAI integration: load_schema, build_prompt, extract_fields
│   ├── excel_store.py                 # Excel persistence for label-scanner extractions
│   ├── google_sheets.py               # Google Sheets sync (optional)
│   ├── check_extractions.py           # Utility for verification
│   ├── schemas/                       # JSON schema definitions (equipment_type.json files)
│   │   └── motor.json, generator.json, transformer.json, etc.
│   └── data/                          # Runtime data directory
│       ├── images/                    # Uploaded images
│       └── extractions.xlsx           # Generated Excel file

├── client_portal_poc/                 # Proof-of-concept client portal (not active)
│   ├── assets/, sql/
│   └── (legacy code)

├── supabase/                          # Supabase SQL schema & migrations
│   └── (database setup files)

├── .planning/                         # Project planning & analysis
│   ├── codebase/                      # Codebase documentation (this directory)
│   │   ├── ARCHITECTURE.md            # System architecture & patterns
│   │   └── STRUCTURE.md               # This file
│   └── (other planning artifacts)

├── documents/                         # Supporting documentation
│   └── (reference docs, screenshots)

├── output/                            # Generated output artifacts
│   ├── archive/
│   ├── documents/
│   └── qa/

├── ppg_handoff/                       # Delivery-note handoff documentation
│   └── contracts/

├── obs_r0_attempt_*_*/               # Observability sandbox attempts (not application code)
│   └── (archived analysis & screenshots)

└── .gitignore, .git/                  # Git configuration
```

## Directory Purposes

**frontend/lib:**
- Purpose: Dart source code for Flutter mobile application
- Contains: Screens, services, domain models, UI components
- Key files: `main.dart`, `services/app_state.dart`, `features/ppg_delivery_note/`

**frontend/lib/features/ppg_delivery_note:**
- Purpose: Isolated feature module for delivery-note digitization
- Contains: Domain models, business logic, persistence, UI screens
- Follows: Clean architecture layers (domain → services → screens)

**frontend/lib/services:**
- Purpose: Cross-feature shared services
- Contains: State management (AppState), external API clients (OpenAI, Supabase), local storage
- Used by: Both label-scanner and PPG workflows

**frontend/lib/screens:**
- Purpose: Legacy/general screens for label-scanner workflow
- Contains: Home screen, capture, results, history
- Note: PPG has its own screens directory; this is for the alternative home

**backend:**
- Purpose: FastAPI REST API for label extraction (optional backend; app can work offline)
- Contains: OpenAI integration, schema management, Excel/Google Sheets sync
- Deployment: Separate from Flutter app (cloud or local server)

**supabase:**
- Purpose: Remote backend for optional cloud sync
- Contains: SQL schema, RLS policies, real-time listeners
- Used by: Optional Supabase service in app (configured in `config.dart`)

**.planning/codebase:**
- Purpose: Architecture and structure documentation for future phases/refactoring
- Contains: ARCHITECTURE.md, STRUCTURE.md, CONVENTIONS.md, TESTING.md (other docs as needed)

**obs_r0_attempt_*, documents/, output/, ppg_handoff/:**
- Purpose: Non-application artifacts (archived experiments, screenshots, handoff docs)
- Note: Not part of active codebase; mentioned in Structure for completeness

## Key File Locations

**Entry Points:**
- `frontend/lib/main.dart` → `void main()` initializes Supabase & AppState, runs PixorexApp
- `frontend/lib/screens/home_screen.dart` → Label scanner home (if `LABEL_SCANNER=true`)
- `frontend/lib/features/ppg_delivery_note/screens/ppg_hub_screen.dart` → PPG delivery notes hub (default home)

**Configuration:**
- `frontend/lib/services/config.dart` → API keys, model name, Supabase URL/key, default client email
- `frontend/pubspec.yaml` → Flutter dependencies
- `backend/main.py` → FastAPI middleware, CORS, auth token check

**Core Logic:**
- `frontend/lib/services/app_state.dart` → Label-scanner workflow orchestration (schemas, extraction, sync)
- `frontend/lib/features/ppg_delivery_note/services/ppg_session_controller.dart` → PPG workflow orchestration
- `frontend/lib/features/ppg_delivery_note/persistence/ppg_repository.dart` → SQLite CRUD for PPG
- `backend/extraction.py` → OpenAI prompt building and API call

**State Management:**
- `frontend/lib/services/app_state.dart` → Label-scanner ChangeNotifier
- `frontend/lib/features/ppg_delivery_note/services/ppg_session_controller.dart` → PPG ChangeNotifier

**Testing:**
- `frontend/test/ppg_delivery_note/ppg_parser_test.dart` → Parser unit tests
- `frontend/test/ppg_delivery_note/ppg_receiving_workflow_test.dart` → Full workflow integration test
- Fixtures: `frontend/test/ppg_delivery_note/*.json` (synthetic OCR, expected outputs)

## Naming Conventions

**Files:**
- Snake case for Dart files: `app_state.dart`, `ppg_session_controller.dart`, `ppg_template_parser.dart`
- Exception: `main.dart` (convention)
- Python files: snake_case: `main.py`, `extraction.py`, `excel_store.py`

**Classes & Types:**
- PascalCase: `AppState`, `PpgSessionController`, `ScanSession`, `PageCapture`, `DocumentLine`
- Enums: PascalCase: `ScanSessionStatus`, `PageOcrStatus`, `PhysicalQuantityOrigin`, `CaptureMode`
- Interfaces/Abstract: Same as classes (no prefix): `LocalSubmissionService`, `PpgRepository`

**Variables & Functions:**
- camelCase: `userEmail`, `pageCapture`, `loadSchemas()`, `parseDeliveryNote()`
- Constants: `const _labelScannerHome`, `const ppgHubRouteName`
- Private members: `_controller`, `_db`, `_ocr`

**Directories:**
- snake_case: `ppg_delivery_note`, `ocr`, `parser`, `persistence`, `services`, `screens`, `widgets`, `domain`, `ui`
- Organized by feature or layer: `features/ppg_delivery_note/`, `lib/services/`, `lib/screens/`

**Routes & Navigation:**
- Named routes (if used): `ppgHubRouteName = '/ppg/delivery-notes'`
- Helper functions: `ppgPush()`, `ppgPopToHub()` (from `ui/ppg_navigation.dart`)

## Where to Add New Code

**New PPG Feature (e.g., "photo library import"):**
- Business logic: Add file to `frontend/lib/features/ppg_delivery_note/domain/` (e.g., `photo_library_importer.dart`)
- Service orchestration: Add method to `ppg_session_controller.dart` or new file in `services/`
- UI screen: Add to `frontend/lib/features/ppg_delivery_note/screens/` (e.g., `ppg_photo_library_screen.dart`)
- Tests: Add to `frontend/test/ppg_delivery_note/` (e.g., `photo_library_importer_test.dart`)
- Navigation: Update `ppg_navigation.dart` if new helper is needed

**New Label-Scanner Schema:**
- Backend schema file: `backend/schemas/[equipment_type].json` with fields array
- Test fixture: Add JSON file to `frontend/assets/schemas/` for demo
- Supabase: Insert row into `schema_templates` table with prompt template
- Frontend: Automatic discovery via `AppState.loadSchemas()`

**New PPG Workflow Stage:**
- Domain model updates: Modify `ScanSessionStatus` or add new enum in `domain/models.dart`
- Controller logic: Update `PpgSessionController` to handle new state transitions
- Screen: Add screen file in `features/ppg_delivery_note/screens/`
- UI tokens: Update `features/ppg_delivery_note/ui/ppg_tokens.dart` if new colors/spacing needed
- Navigation: Add route in `screens/ppg_hub_screen.dart` and `ppg_navigation.dart`

**New External Integration (e.g., "sync to warehouse system"):**
- Service class: Add to `frontend/lib/services/` (e.g., `warehouse_sync_service.dart`)
- API calls: Handle HTTP or method-channel calls
- Error handling: Wrap in try-catch, store in AppState or PpgSessionController error field
- Configuration: Add env vars to `config.dart` or `.env` file (not git-committed)

**New Validation Rule:**
- Domain: Add to `frontend/lib/features/ppg_delivery_note/domain/validation.dart` or create new file
- Integration: Call from `LocalSubmissionService` before submission
- Error messages: Populate `documentIssues` in `PpgSessionController` for UI display

**New Test Fixture (PPG):**
- Synthetic OCR JSON: Add to `frontend/test/ppg_delivery_note/` (e.g., `dn_[number]_synthetic_ocr.json`)
- Expected output: Add corresponding `.expected.json` file
- Test file: Create `frontend/test/ppg_delivery_note/dn_[number]_parser_test.dart`
- Load fixture: Use `loadFixture()` helper or read file directly in test

## Special Directories

**frontend/lib/branding/:**
- Purpose: App-wide theming and brand constants
- Generated: No
- Committed: Yes
- Contains: `AppBrand` class with colors (blue, navy, neutral, etc.)
- Example: `app_brand.dart` defines `blue: Color(0xFF0066FF)` used in `main.dart` theme

**frontend/assets/schemas/:**
- Purpose: JSON schema templates for label extraction (bundled with app for offline discovery)
- Generated: No (developer-created)
- Committed: Yes
- Example: `motor.json`, `generator.json` with field definitions
- Note: Supabase `schema_templates` table is source of truth; app assets are fallback

**frontend/lib/features/ppg_delivery_note/persistence/ppg_repository.dart:**
- Purpose: SQLite database access layer
- Database file: `ppg_delivery_note.db` in app documents directory
- Schema version: 9 (with migrations `_createV1` → `_upgradeToV9`)
- Evidence directory: `ppg_evidence/` alongside database for image storage

**backend/data/:**
- Purpose: Runtime data store (not committed)
- Generated: Yes
- Contains: `images/` (uploaded photos) and `extractions.xlsx` (generated spreadsheet)
- Note: Deleted on backend restart; not persistent storage

**frontend/test/ppg_delivery_note/ fixtures:**
- Purpose: Test data (synthetic OCR results, expected parser outputs, real delivery-note samples)
- Generated: No (manually curated)
- Committed: Yes
- Used by: Parser unit tests, workflow integration tests
- Example: `dn_5319364114_synthetic_ocr.json` is a fixture with word-level OCR elements

---

*Structure analysis: 2026-10-11*
