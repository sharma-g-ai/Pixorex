---
last_mapped_commit: 64405acfa13ec78cf102cb081212fd931bb8a4e4
last_mapped_at: 2026-10-11
---
<!-- refreshed: 2026-10-11 -->

# Architecture

**Analysis Date:** 2026-10-11

## System Overview

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                      Flutter Mobile App (Pixorex)                        │
│  ┌──────────────────┬──────────────────────┬──────────────────────────┐ │
│  │  Label Scanner   │  PPG Delivery Notes  │    Home Screen / Conf    │ │
│  │  (HomeScreen)    │  (PpgHubScreen)      │    (EmailGate/Router)    │ │
│  │  `screens/`      │  `features/ppg_*/`   │    `screens/` general    │ │
│  └──────────────────┴──────────────────────┴──────────────────────────┘ │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │                    State & Service Layer                              │ │
│  │  ┌────────────────────────────────────────────────────────────────┐  │ │
│  │  │ AppState (Provider)      │  PpgSessionController (Provider)  │  │ │
│  │  │ • User email             │  • Session & page lifecycle       │  │ │
│  │  │ • Schemas (Supabase)     │  • OCR coordination              │  │ │
│  │  │ • Extraction history     │  • Document parsing              │  │ │
│  │  │ • Current result         │  • Physical count verification   │  │ │
│  │  │ `services/app_state.dart`│  `services/ppg_session_ctrl.dart`│  │ │
│  │  └────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  │  ┌──────────────┬──────────────┬──────────────┬─────────────────┐   │ │
│  │  │ OpenAiService│LocalStore    │SupabaseServ.│ PpgRepository   │   │ │
│  │  │ (extraction) │ (extraction) │ (sync/auth) │(PPG offline DB) │   │ │
│  │  │              │              │             │                 │   │ │
│  │  └──────────────┴──────────────┴──────────────┴─────────────────┘   │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │                 PPG Feature: Domain & Processing                      │ │
│  │  ┌───────────────────────────────────────────────────────────────┐   │ │
│  │  │ Domain Models        OCR & Parsing        Validation          │   │ │
│  │  │ • ScanSession        • PpgOcrAdapter      • SourceCorrection  │   │ │
│  │  │ • PageCapture        • PpgTemplateParser  • LocalSubmission   │   │ │
│  │  │ • DocumentLine       • OcrLineBuilder     • Consolidator      │   │ │
│  │  │ • OcrObservation     • TotalQtyFieldRdr   • CanArticleReader  │   │ │
│  │  └───────────────────────────────────────────────────────────────┘   │ │
│  │  `domain/` `ocr/` `parser/` `domain/` `domain/` `parser/`             │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │              Local Storage: SQLite + Filesystem                       │ │
│  │  • ppg_delivery_note.db (ScanSession, PageCapture, DocumentLine)     │ │
│  │  • ppg_evidence/ (source/rectified images, OCR observations)         │ │
│  │  • SharedPreferences (user email, lightweight settings)              │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
         │                                   │
         ▼                                   ▼
┌──────────────────────┐       ┌───────────────────────────────┐
│  Android ML Kit      │       │  Supabase                     │
│  (On-device OCR)     │       │  • Auth & RLS                 │
│  via MethodChannel   │       │  • Extraction sync            │
│  com.amzur.equiptrack│       │  • Schema templates           │
│  /ppg_ocr            │       │  • Client portal backend      │
└──────────────────────┘       └───────────────────────────────┘
         │                            │
         └────────────┬───────────────┘
                      ▼
         ┌──────────────────────────┐
         │  FastAPI Backend         │
         │  `backend/main.py`       │
         │  • /schemas              │
         │  • /extract (→ OpenAI)   │
         │  • /extractions          │
         │  • /review/correct       │
         │  • /download (Excel)     │
         └──────────────────────────┘
                      │
                      ▼
         ┌──────────────────────────┐
         │  OpenAI API (gpt-5.4)    │
         │  • Label extraction      │
         │  • PPG → Not used here   │
         └──────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| **EmailGate** | Auth entry point: load/persist user email via SharedPreferences | `main.dart` (lines 98–228) |
| **PpgHubScreen** | Hub for delivery note sessions; manages session lifecycle and stage transitions (document → count → submit) | `features/ppg_delivery_note/screens/ppg_hub_screen.dart` (lines 16–60) |
| **PpgSessionController** | Central orchestrator for PPG workflow; manages sessions, pages, OCR, parsing, physical count state | `features/ppg_delivery_note/services/ppg_session_controller.dart` |
| **PpgRepository** | SQLite persistence for sessions, pages, lines, OCR observations, corrections, physical adjustments | `features/ppg_delivery_note/persistence/ppg_repository.dart` |
| **PpgOcrAdapter** | Bridges Android ML Kit OCR via MethodChannel; on-device text recognition, no fallback | `features/ppg_delivery_note/ocr/ppg_ocr_adapter.dart` |
| **PpgTemplateParser** | Parses OCR elements into delivery-note structure; detects form layout, page identity, piece counts, article numbers | `features/ppg_delivery_note/parser/ppg_template_parser.dart` |
| **OcrLineBuilder** | Reconstructs OCR lines from word-level elements; handles multi-resolution input | `features/ppg_delivery_note/parser/ocr_line_builder.dart` |
| **PpgConsolidator** | Merges multiple OCR runs or manual corrections into canonical DocumentLine records | `features/ppg_delivery_note/parser/consolidator.dart` |
| **LocalSubmissionService** | Validates article numbers, physical counts, piece summaries before Supabase sync | `features/ppg_delivery_note/domain/local_submission.dart` |
| **TotalQtyFieldReader** | Specialized OCR crop reader for "Total Qty" field using target coordinates | `features/ppg_delivery_note/ocr/total_qty_field_reader.dart` |
| **CanArticleReader** | Validates article numbers (CAN codes) against patterns and business rules | `features/ppg_delivery_note/domain/can_article_reader.dart` |
| **AppState** | Manages label-scanner workflows: user email, schemas from Supabase, extraction history, OpenAI sync | `services/app_state.dart` |
| **OpenAiService** | Calls OpenAI API for label/equipment nameplate extraction using dynamic schemas | `services/openai_service.dart` |
| **SupabaseService** | Handles Supabase auth, extraction sync, schema fetch, RLS-protected queries | `services/supabase_service.dart` |
| **LocalStore** | On-device extraction history storage; merges with Supabase before displaying | `services/local_store.dart` |
| **FastAPI Backend** | REST API: schema listing, extraction via OpenAI, Excel/Google Sheets sync, image serving | `backend/main.py` |

## Pattern Overview

**Overall:** Layered mobile-first architecture with feature-based organization (PPG delivery notes as primary feature) and shared services for label scanning.

**Key Characteristics:**
- **Offline-first SQLite database** with Supabase sync, not a primary source
- **Provider-based state management** with ChangeNotifier for reactive UI updates
- **On-device OCR** (Android ML Kit) eliminates cloud dependency for document capture
- **Deterministic parsing** of delivery-note template via regex and geometry heuristics
- **Progressive disclosure** of workflows: stages are unlocked only when prerequisites are met (pages scanned → counts verified → submission ready)
- **Audit trail** persisted: corrections, adjustments, and OCR observations tied to session/page/line

## Layers

**Presentation Layer:**
- Purpose: Material 3 UI screens with form inputs, image preview, progress indicators
- Location: `screens/`, `features/ppg_delivery_note/screens/`
- Contains: StatefulWidgets for navigation, custom UI components (four_corner_crop, perspective_warp, ppg_widgets)
- Depends on: State management (Provider), domain models
- Used by: Users via Flutter app

**State & Services Layer:**
- Purpose: Business logic orchestration, external API calls, local persistence coordination
- Location: `services/`, `features/ppg_delivery_note/services/`
- Contains: AppState (label scanner), PpgSessionController (PPG), OpenAiService, SupabaseService, LocalStore, PpgRepository
- Depends on: Domain models, external SDKs (OpenAI, Supabase, sqflite)
- Used by: Presentation layer (Provider context)

**Domain & Processing Layer:**
- Purpose: Core business entities and offline workflows (OCR, parsing, validation)
- Location: `features/ppg_delivery_note/domain/`, `ocr/`, `parser/`
- Contains: Models (ScanSession, PageCapture, DocumentLine), OCR adapter, template parser, consolidator, validation logic
- Depends on: None (no cross-layer dependencies)
- Used by: PpgSessionController, business logic

**Persistence Layer:**
- Purpose: SQLite CRUD, image file storage, SharedPreferences for lightweight config
- Location: `persistence/ppg_repository.dart`, `services/local_store.dart`, `services/config.dart`
- Contains: Database schema (v9 with migrations), evidence directory management, extraction record indexing
- Depends on: Domain models
- Used by: Services layer for data retrieval/storage

**External Integration Layer:**
- Purpose: API calls to OpenAI and Supabase
- Location: `services/openai_service.dart`, `services/supabase_service.dart`
- Contains: HTTP clients, credential management, payload serialization
- Depends on: Configuration (API keys from environment or dart-define)
- Used by: AppState and submission logic

## Data Flow

### Primary PPG Workflow

1. **Session Start** (`PpgHubScreen._startNewDelivery()` → `ppg_session_controller.dart:63–81`)
   - User taps "New Delivery"
   - Controller closes previous session, opens capture screen

2. **Page Capture** (`PpgCaptureScreen`)
   - User frames page in camera, captures image
   - Image saved to `ppg_evidence/` filesystem
   - `PageCapture` record created, marked pending

3. **OCR Recognition** (`PpgSessionController.acceptPageCapture()` or similar method)
   - `PpgOcrAdapter.recognizeFile()` invokes Android MethodChannel 'com.amzur.equiptrack/ppg_ocr'
   - ML Kit returns word/line/symbol elements with bounding boxes
   - `OcrObservation` record persisted in database

4. **Template Parsing** (`PpgSessionController` → `PpgTemplateParser.parse()`)
   - `OcrLineBuilder` reconstructs OCR lines from elements
   - Parser detects form layout (delivery-note anchors, summary section, picking-list layout)
   - Extracts: page identity (printed/declared), delivery note number, piece count, table structure
   - Returns `ParsedPageResult` with article numbers and quoted quantities

5. **Page Review** (`PpgPageReviewScreen` or similar)
   - Operator reviews delivery note identity (number, page count)
   - Corrects page-level values if OCR failed
   - Page marked "reviewed" in database

6. **Line Consolidation** (On entering count stage)
   - All active pages' OCR observations fed to `PpgConsolidator`
   - Merges duplicate article numbers across pages
   - Creates canonical `DocumentLine` records with `OccurrenceRole` (quantityBearing vs. setHeaderNoPrintedQuantity)
   - Stores in `document_lines` table

7. **Physical Quantity Entry** (`PpgPhysicalQuantityControl` widgets)
   - User enters actual counted quantities per line
   - `PhysicalQuantityOrigin` tracks source (default, user-entered, confirmed)
   - Quantities saved to `document_lines.physical_quantity`, `physical_quantity_origin`
   - Variance calculated: `document_quantity - physical_quantity`

8. **Variance Review** (`PpgReviewScreen` or final review)
   - Lines with non-zero variance flagged
   - User enters variance reason or retakes page
   - `variance_reason` persisted; line marked verified (`review_confirmed`)

9. **Submission** (`PpgFinalReviewScreen` → `LocalSubmissionService.validatePieceSummary()`)
   - Validation checks:
     - All lines verified
     - All variances have reasons
     - Piece summary (sum of quantities) matches document total
   - If valid, `ScanSession` status set to `submittedLocal`
   - `SubmittedForm` created with metadata

10. **Supabase Sync** (`PpgSessionController.submitDelivery()` or post-submission hook)
    - `SupabaseService.saveDelivery()` or similar
    - Posts session, pages, lines, corrections to remote tables
    - RLS enforces operator email or default client email scoping
    - Local record linked via `supabase_record_id`

### Label Scanner Workflow (Secondary, Alt Home)

1. **Image Selection** (`HomeScreen`)
   - User picks image from gallery or camera

2. **Schema Selection** → **Extract** 
   - `AppState.extractFields()` calls `OpenAiService.extractFields()`
   - OpenAI processes image + dynamic schema (loaded from Supabase)
   - Returns JSON fields + `field_confidence`, `review_flags`, `mismatch_warning`

3. **Result Display** (`ResultsScreen`)
   - User reviews extracted data
   - Can edit fields before submission

4. **Local + Supabase Persist**
   - `AppState.submitExtraction()`:
     - Saves to `LocalStore` (SQLite in `extractions` table)
     - Syncs to `SupabaseService` if configured
   - Image stored locally at `_store.saveImage(imagePath)`

### State Management & Notification

- **AppState** (ChangeNotifier): notifies listeners on `setUserEmail()`, `loadSchemas()`, `loadExtractions()`, `submitExtraction()`
- **PpgSessionController** (ChangeNotifier): notifies after session load, page acceptance, line updates, submission
- **UI rebuilds** via `Provider.watch()` / `context.read()` in widgets
- No explicit event bus; Provider's built-in invalidation handles cascade

## Key Abstractions

**ScanSession (Session entity):**
- Purpose: Root aggregate for a delivery-note capture workflow
- Examples: `frontend/lib/features/ppg_delivery_note/domain/models.dart` line 20
- Pattern: Value object with mutable fields (status, delivery note number, page count) and immutable identity (UUID)
- Lifecycle: created (draft) → reviewed → submittedLocal

**PageCapture (Page entity):**
- Purpose: Represents one scanned/captured page of a delivery note
- Examples: lines 48–101 of models.dart
- Pattern: Tracks multiple revisions (`captureRevision`), pending replacement, OCR status, image paths
- Constraint: Can only have one active page per printed-page slot; pending replacements wait for user acceptance

**DocumentLine (Line entity):**
- Purpose: Extracted row from delivery note table (article + quoted qty)
- Examples: lines 102+ of models.dart
- Pattern: Stores document quantity (from OCR/PDF) and physical quantity (operator-counted)
- Role system: quantityBearing (normal row), setHeaderNoPrintedQuantity (grouping header without qty), unresolved (ambiguous)

**OcrObservation (Audit trail):**
- Purpose: Immutable record of one OCR run's output (elements, lines, symbols, timings)
- Pattern: Persisted in database for forensics; enables comparison of multiple OCR engines
- Example: Used by `TotalQtyFieldReader` to retry small fields with higher zoom

**Consolidator (Business logic):**
- Purpose: Merge OCR from multiple pages; resolve duplicates and role conflicts
- Pattern: Stateless; accepts list of OcrObservations and returns consolidated DocumentLine list
- Constraint: Deterministic (same input always yields same output) for predictable UI

## Entry Points

**Mobile App Start:**
- Location: `main.dart` line 16–29
- Triggers: `flutter run` or app launch
- Responsibilities: Initialize Supabase, create AppState provider, build PixorexApp material shell

**EmailGate:**
- Location: `main.dart` line 98–228
- Triggers: Widget tree after app start
- Responsibilities: Check SharedPreferences for user email; show dialog if missing; route to home screen (PPG or label scanner)

**PPG Hub:**
- Location: `features/ppg_delivery_note/screens/ppg_hub_screen.dart` line 16–100
- Triggers: EmailGate after email entry (default home)
- Responsibilities: Display list of saved delivery-note sessions; route to new-delivery or open-session flows

**Capture Screen:**
- Location: `features/ppg_delivery_note/screens/ppg_capture_screen.dart`
- Triggers: "New Delivery" button from hub
- Responsibilities: Camera preview, take photo, on-device preview, accept/retake

**Session Screen:**
- Location: `features/ppg_delivery_note/screens/ppg_session_screen.dart`
- Triggers: New delivery with accepted capture or existing session open
- Responsibilities: Multi-step form for page identity, OCR review, navigation to count/review

## Architectural Constraints

- **Threading:** Single-threaded Flutter event loop; heavy work (OCR, parsing) runs on `compute()` or method channel. Supabase client is async-first.
- **Global state:** `AppState` and `PpgSessionController` are singletons per app run (created once, shared via Provider). Database connection (`_db`) in PpgRepository is singleton.
- **Circular imports:** None observed; feature imports only `domain/`, services import `domain/` and external SDKs, presentation imports state + domain.
- **Offline capability:** SQLite-first; all session/page/line data persists locally. Supabase sync is best-effort; app does not block on network.
- **Image storage:** Large images stored in filesystem (`ppg_evidence/`), not database blobs. Database stores only paths and metadata.
- **OCR coupling:** Android-only via MethodChannel; iOS/Web unsupported (raises UnsupportedError in `PpgOcrAdapter.recognizeFile()`).
- **Supabase config:** Loaded from hardcoded constants in `config.dart`; not environment-specific. API key is publishable (RLS enforces data filtering).

## Anti-Patterns

### OCR Observation Not Persisted Immediately

**What happens:** After capture, OCR observation may be stored in memory before database write completes; if app crashes, observation is lost.
**Why it's wrong:** Breaks audit trail; operator cannot see what OCR returned if session state is incomplete.
**Do this instead:** Persist OcrObservation to database immediately after recognition in `ppg_session_controller.dart`. Use transaction to ensure both PageCapture status and OcrObservation are atomic.

### Manual Field Edits Not Tracked

**What happens:** When operator corrects a delivery note number or page identity, the change is saved but no `Correction` record is created.
**Why it's wrong:** No forensic trail; cannot audit what operator changed or why.
**Do this instead:** Before updating PageCapture or DocumentLine, save a `Correction` record with before/after values, reason, timestamp, and operator email (from AppState). Query `corrections` table in reports.

### Variance Reason Optional

**What happens:** Operator can mark a line "verified" with non-zero variance but empty variance reason.
**Why it's wrong:** Cannot explain discrepancies; makes auditing impossible.
**Do this instead:** In `LocalSubmissionService.validatePieceSummary()`, enforce that lines with `variance != 0` MUST have a non-empty, non-whitespace `variance_reason`. Block submission if violated.

### Page-Replacement State Not Atomic

**What happens:** Operator can accept a retake while the old page is still active; UI logic must handle both active and pending simultaneously.
**Why it's wrong:** Complex state space; high risk of bugs (e.g., counting lines from wrong page).
**Do this instead:** Introduce a dedicated workflow state (e.g., `PageReplaceFlow` enum) and ensure only one of {active page, pending page} can be used for OCR/counting at a time. Transition atomically.

## Error Handling

**Strategy:** Graceful degradation with user-facing messaging.

**Patterns:**
- **OpenAI failures:** Caught in `AppState.extractFields()` (line 206); error stored in `_error` field; user sees snackbar/dialog
- **Supabase failures:** Caught in `_syncToSupabase()` (line 235); `debugPrint()` logs; continues without sync if optional; throws if critical
- **OCR failures:** Caught in method-channel invoke; `PageCapture.ocrError` set; user invited to retake page
- **Database errors:** Propagated as exceptions; no silent failures (e.g., `PpgRepository.init()` throws if database open fails)
- **Validation failures:** `LocalSubmissionService` returns list of issue strings; UI displays before form submission

## Cross-Cutting Concerns

**Logging:** 
- `debugPrint()` used throughout for development
- Key events: session creation, OCR completion, Supabase sync result
- No structured logging framework (Firebase Crashlytics not integrated)

**Validation:** 
- Input validation: regex checks in parser (article numbers, page counts)
- Business logic validation: in domain classes (e.g., `PhysicalCountState` enum enforces legal transitions)
- Supabase RLS: enforces that users see only their own extractions or default-client records

**Authentication:** 
- Email-based (no OAuth; user enters email, stored in SharedPreferences)
- Supabase uses email for RLS row-level scoping
- Backend has hardcoded bearer token (env var `LABEL_READER_BACKEND_TOKEN`)

---

*Architecture analysis: 2026-10-11*
