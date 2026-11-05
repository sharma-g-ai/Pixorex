# Central Repository Implementation Plan

## Purpose

This document replaces the earlier "Flutter app writes directly to Supabase" PoC plan with the architecture that better fits the current product direction:

- **internal operator app** for capture, extraction, review, and approval
- **central repository** for extracted and approved data
- **client-facing UI/API** for approved results only
- **local Postgres first**, then **Supabase** as the hosted target

This keeps the backend contract stable while changing the persistence layer underneath it.

---

## Executive Decision

### Recommended path

Implement the work in two tracks:

#### Track A: PoC delivery now

1. **Keep the current operator mobile flow for the demo branch**
2. **Use Supabase as the hosted central repository for approved records**
3. **Add a static client-facing web portal (Option 2)**
4. **Expose approved records only through Supabase-backed reads**

#### Track B: architecture hardening next

1. **Rewire the app to backend mode**
2. **Replace Excel / Google Sheets with local Postgres-backed storage**
3. **Keep the existing mobile app as the internal review UI**
4. **Keep the client-facing approved-results UI**
5. **After local validation, move backend persistence from local Postgres to Supabase**

### Why this split

For the PoC, the fastest client-access path is:

```text
Operator mobile app
  -> OpenAI extraction
  -> Supabase
  -> approval

Client browser
  -> static web app
  -> Supabase approved view only
```

That gives the client a browser-based experience immediately, without waiting for the full backend-owned architecture.

For the next architecture step, backend ownership is still the correct long-term direction:

The current direct-to-OpenAI / direct-to-Supabase mobile path works for a side experiment, but it is not the right ownership boundary for a central repository:

- mobile app should not own the system of record
- mobile app should not own persistence rules
- client access should not depend on a mobile-only flow
- migrating local storage to hosted storage later is much easier if the **backend** already owns the write path

So the right long-term architecture is:

```text
Mobile app / Web app
  -> Backend API
    -> local Postgres now
    -> Supabase Postgres + Storage later
```

### PoC choice for client access

For the current PoC, choose **Option 2**:

- a **static web portal**
- hosted anywhere public (`Vercel`, `Netlify`, `Supabase hosting`, or similar)
- reading from **Supabase**
- showing **approved records only**
- protected by **Supabase Auth** and **RLS**

This is the recommended client-facing path for the demo.

---

## Current State

### Repo / branch

- **Repo**: `/home/msi/Downloads/ocr_poc`
- **Current latest branch**: `origin/frontendCodeBase`
- **Current working branch for this PoC**: `supabasePocNoFieldReviews`

### Current effective app flow

Today the latest Flutter branch mostly uses this path:

```text
CaptureScreen
  -> ExtractingScreen
    -> AppState.extractFields()
      -> OpenAiService.extractFields()   // direct OpenAI call from app
      -> LocalStore.saveExtraction()
      -> SupabaseService.saveExtraction()
```

Relevant files:

- `/home/msi/Downloads/ocr_poc/frontend/lib/screens/capture_screen.dart`
- `/home/msi/Downloads/ocr_poc/frontend/lib/screens/extracting_screen.dart`
- `/home/msi/Downloads/ocr_poc/frontend/lib/services/app_state.dart`
- `/home/msi/Downloads/ocr_poc/frontend/lib/services/openai_service.dart`
- `/home/msi/Downloads/ocr_poc/frontend/lib/services/supabase_service.dart`

### Existing backend

The backend exists, but is not currently the main path for the app:

- `/home/msi/Downloads/ocr_poc/backend/main.py`
- `/home/msi/Downloads/ocr_poc/frontend/lib/services/api_service.dart`

Current backend storage is still:

- local Excel / JSON
- Google Sheets sync
- local filesystem image storage

That needs to be replaced.

---

## Target Architecture

## Architecture Overview

### Phase 1: local-first central repository

```text
Internal mobile app
  -> Backend API (FastAPI)
    -> local image storage
    -> local Postgres
    -> OpenAI extraction call
    -> staging + approval tables

Client web UI
  -> Backend API
    -> approved records only
```

### Phase 2: hosted central repository

```text
Internal mobile app
  -> Backend API
    -> Supabase Storage
    -> Supabase Postgres
    -> same extraction / approval logic

Client web UI
  -> Backend API or Supabase-approved views
    -> approved records only
```

### Key design principle

Keep the **backend API contract stable** and swap only the persistence layer:

- local Postgres + local file storage first
- Supabase Postgres + Supabase Storage later

---

## Data Model

The same logical tables are used in both local Postgres and Supabase:

1. `records`
2. `record_images`
3. `extraction_runs`
4. `record_current`
5. `record_approved`

No `field_reviews` table in this PoC.

### Table purpose

#### `records`

One row per logical item.

Examples:
- one motor plate
- one paint-label group made from 1-3 images

Suggested columns:

- `id uuid pk`
- `record_type text`
- `schema_name text`
- `schema_version text`
- `source text`
- `source_ref text`
- `user_email text`
- `client_id text null`
- `status text`
- `created_at timestamptz`
- `updated_at timestamptz`

#### `record_images`

One row per image for the same record.

- `id uuid pk`
- `record_id uuid fk`
- `image_order int`
- `panel_hint text default 'unknown'`
- `storage_path text`
- `original_filename text`
- `mime_type text`
- `created_at timestamptz`

#### `extraction_runs`

Every model run is preserved.

- `id uuid pk`
- `record_id uuid fk`
- `provider text`
- `model text`
- `method text`
- `schema_name text`
- `input_image_count int`
- `raw_output_text text`
- `parsed_output jsonb`
- `image_match boolean`
- `detected_type text`
- `latency_ms int`
- `created_at timestamptz`

#### `record_current`

Current machine or staged reviewed result.

- `record_id uuid pk`
- `extraction_run_id uuid fk`
- `fields jsonb`
- `extra_fields jsonb`
- `review_flags jsonb`
- `filled_field_count int`
- `review_required boolean`
- `updated_at timestamptz`

#### `record_approved`

Approved result for external use.

- `record_id uuid pk`
- `approved_fields jsonb`
- `approved_extra_fields jsonb`
- `approved_by text`
- `approved_at timestamptz`

### Bronze / Silver / Gold model

- **Bronze**: raw images + raw model output
- **Silver**: `record_current`
- **Gold**: `record_approved`

Only **Gold** should be shown to clients.

---

## UI Strategy

## 1. Internal Review UI

Use the current Flutter app as the operator UI.

### Existing screens to keep

- capture / upload
- extracting progress
- results review
- history / detail

### Internal UI requirements

The operator UI should show:

- uploaded image(s)
- extracted fields
- review / edit actions
- approve / reject status
- mismatch warning if image type does not match selected schema

### Internal UI target flow

```text
Capture
  -> Extract
  -> Review extracted fields
  -> Edit if needed
  -> Approve
  -> Record moves to approved layer
```

### Internal UI status model

- `uploaded`
- `extracted`
- `review_required`
- `approved`
- `rejected`

## 2. Client UI

Client should **not** use the operator app.

### Recommended option

Build a small **static web dashboard** first.

Why:
- fastest to ship
- easiest to secure
- easier for read-only access
- works well for search / filter / export
- accessible anywhere with a browser

### PoC implementation choice

For the PoC, the client portal should read from **Supabase directly**, not through a new backend layer.

Use:

- Supabase Auth for login
- `approved_records_view` for approved data
- `record_images` signed URLs or a joined approved-records-with-image view
- RLS so each client sees only their own approved records

This is the **current implementation target** for the client UI.

### Client UI should show

- approved records only
- record ID
- record type
- upload / approval date
- approved extracted fields
- associated image(s), if allowed
- search / filter
- export

### Client UI must not show

- raw extraction runs
- staging / `record_current`
- internal review flags
- rejected records
- unapproved records

### Recommended hosting for PoC

Host the static client portal on:

- `Vercel`
- `Netlify`
- or any static hosting provider

Then the client can access it from:

- laptop
- phone
- tablet

from anywhere with internet access.

---

## API Design

The app and client should talk to the backend, not directly to Postgres.

## Internal API

### Existing endpoints to keep

- `GET /schemas`
- `POST /extract`
- `GET /extractions`
- `GET /extractions/{id}`
- `POST /review/correct`
- `GET /images/{filename}`

### Changes needed

Replace current Excel / Sheets storage inside these endpoints with database-backed storage.

### New internal endpoints to add

- `POST /review/approve`
- `POST /review/reject`
- `GET /review/queue`
- `GET /records/{record_id}`

Suggested request / response shape:

#### `POST /review/approve`

Request:

```json
{
  "record_id": "uuid",
  "approved_fields": {
    "manufacturer": "PPG",
    "product_name": "SIGMACOVER 280"
  },
  "approved_by": "operator@example.com"
}
```

Response:

```json
{
  "status": "approved",
  "record_id": "uuid"
}
```

#### `POST /review/reject`

Request:

```json
{
  "record_id": "uuid",
  "reason": "wrong schema / bad image"
}
```

#### `GET /review/queue`

Returns records where:

- `status in ('extracted', 'review_required')`

## Client API

Expose approved results only.

### PoC note

For the current PoC static portal, you do not need to build these endpoints first if the portal reads directly from Supabase with proper RLS.

These endpoints remain useful for the backend-owned architecture phase.

### New client-facing endpoints

- `GET /approved-records`
- `GET /approved-records/{record_id}`
- `GET /approved-records/export`

Optional:

- `GET /approved-records?record_type=paint_label`
- `GET /approved-records?from=...&to=...`
- `GET /approved-records?search=...`

### Client API data rule

Client API reads from:

- `record_approved`
- or a view built on top of `records + record_approved`

Client API must not read from:

- `extraction_runs`
- `record_current`
- internal review flags

---

## Local Postgres First Plan

## Why local Postgres first

This lets us validate:

- backend-owned persistence
- review / approval workflow
- client-facing read API
- central repository semantics

before introducing hosted auth / storage / RLS / secrets management.

## Phase 1 storage decisions

- images: local filesystem
- database: local Postgres
- backend: FastAPI
- mobile app: call backend through `ApiService`
- client UI: web dashboard calling backend

## Required backend changes

### Replace storage layer

Current backend:

- `/home/msi/Downloads/ocr_poc/backend/excel_store.py`
- `/home/msi/Downloads/ocr_poc/backend/google_sheets.py`

These should be replaced with:

- `postgres_store.py`

### Backend responsibilities after change

1. save uploaded images
2. call extraction
3. persist rows in Postgres
4. serve history / review queue / approved records
5. update approved state

### Backend contract stays stable

Keep the mobile-facing endpoints stable while changing internals.

---

## Rewire App to Backend Mode

## Current issue

The current app calls:

- `OpenAiService`
- `LocalStore`
- `SupabaseService`

directly from the frontend.

## Target app service layer

App should switch back to:

- `ApiService`

So the flow becomes:

```text
App
  -> ApiService
    -> FastAPI backend
      -> OpenAI + Postgres + local image store
```

## Files to change in `ocr_poc`

### Frontend

- `/home/msi/Downloads/ocr_poc/frontend/lib/services/app_state.dart`
- `/home/msi/Downloads/ocr_poc/frontend/lib/services/api_service.dart`
- `/home/msi/Downloads/ocr_poc/frontend/lib/screens/history_detail_screen.dart`
- `/home/msi/Downloads/ocr_poc/frontend/lib/screens/home_screen.dart`

### Backend

- `/home/msi/Downloads/ocr_poc/backend/main.py`
- new: `/home/msi/Downloads/ocr_poc/backend/postgres_store.py`
- maybe new: `/home/msi/Downloads/ocr_poc/backend/db.py`

## Frontend rewire tasks

1. `AppState.loadSchemas()` -> call `ApiService.getSchemas()`
2. `AppState.extractFields()` -> call `ApiService.extractFields()`
3. `AppState.loadExtractions()` -> call `ApiService.getExtractions()`
4. `AppState.submitCorrections()` -> call backend review endpoint
5. remove direct `SupabaseService` and direct `OpenAiService` from primary app path

Local storage can remain as optional cache, not source of truth.

---

## Supabase Migration Plan

Once local Postgres version is working, move the backend persistence layer to Supabase.

## What changes during migration

### Replace only these parts

- local Postgres connection -> Supabase Postgres
- local image storage -> Supabase Storage

### What should not change

- mobile app contract
- client web UI contract
- backend endpoint shapes
- data model

## Supabase target

Use the same logical schema:

- `records`
- `record_images`
- `extraction_runs`
- `record_current`
- `record_approved`

### Supabase-specific additions

- Storage bucket: `scans`
- RLS or backend-enforced auth
- approved views for client access

### Approved view requirement for client portal

For the static client portal, one of these must exist:

1. `approved_records_view` plus separate `record_images` access for signed URLs
2. or a joined view such as `approved_records_with_images_view`

The second option is cleaner for the client portal because it avoids a second query for preview images.

---

## Screen Proposal

## Internal app screens

### 1. Capture screen

Already exists.

Responsibilities:

- select schema / equipment type
- capture 1-3 images

### 2. Extracting screen

Already exists.

Responsibilities:

- show extraction progress
- wait for backend response

### 3. Results review screen

Already exists.

Responsibilities:

- show extracted fields
- edit values
- submit approval

Add:

- explicit `Approve`
- explicit `Reject`
- image mismatch banner
- extraction source / schema info

### 4. Review queue / history

Already partly exists as history.

Responsibilities:

- list records
- show status
- filter `pending / approved / rejected`

## Client portal screens

### 1. Login

- email / password or magic link

### 2. Approved records list

- search
- filter by type / date
- status fixed to approved

### 3. Record detail

- approved fields
- image preview
- export / copy / API link if needed

---

## Phased Delivery Plan

## Phase 0: design freeze

Deliverables:

- this plan approved
- data model approved
- internal vs client UI scope approved

## Phase 1: backend-owned local PoC

Deliverables:

- app rewired to backend mode
- backend saves to local Postgres
- backend serves history and images
- internal review path works
- approval writes to `record_approved`

Success criteria:

- capture -> extract -> review -> approve works end to end
- no Sheets dependency
- no Excel dependency

## Phase 2: client read-only UI

Deliverables:

- simple static web dashboard
- approved records list
- approved record detail
- search / filter

Success criteria:

- client can log in
- client sees approved records only

## Phase 3: migrate backend storage to Supabase

Deliverables:

- Supabase Postgres / Storage
- same backend API
- hosted central repository

Success criteria:

- local and hosted outputs match
- client UI works unchanged

---

## What Not To Do

- do not let the mobile app write directly to local Postgres
- do not expose raw extraction data to the client
- do not make the client depend on the operator mobile app
- do not add `field_reviews` in this PoC
- do not migrate both UI and persistence and auth all at once without phases

---

## Immediate Implementation Tasks

### First concrete implementation step

#### For the PoC now

1. keep the current operator mobile flow
2. add the static client portal
3. point the client portal to Supabase approved reads only
4. validate auth + RLS + signed image URLs

#### Next after PoC validation

1. rewire `ocr_poc` frontend to backend mode
2. implement `postgres_store.py`
3. remove Excel / Sheets writes from backend
4. add review / approve endpoints
5. make history read from backend

### Files to change first

#### Backend

- `/home/msi/Downloads/ocr_poc/backend/main.py`
- new `/home/msi/Downloads/ocr_poc/backend/postgres_store.py`
- optional `/home/msi/Downloads/ocr_poc/backend/db.py`

#### Frontend

- `/home/msi/Downloads/ocr_poc/frontend/lib/services/app_state.dart`
- `/home/msi/Downloads/ocr_poc/frontend/lib/services/api_service.dart`
- `/home/msi/Downloads/ocr_poc/frontend/lib/screens/home_screen.dart`
- `/home/msi/Downloads/ocr_poc/frontend/lib/screens/history_detail_screen.dart`

---

## Testing Plan

## Local backend test

Run backend locally:

```bash
cd /home/msi/Downloads/ocr_poc/backend
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Note:
- current `api_service.dart` still points to port `8002`
- align frontend and backend to the same port before testing

## End-to-end test checklist

1. open app
2. capture 1-3 images
3. select equipment type
4. submit extraction
5. confirm backend stores:
   - `records`
   - `record_images`
   - `extraction_runs`
   - `record_current`
6. review fields in app
7. approve correction
8. confirm backend stores:
   - `record_approved`
   - `records.status = approved`
9. open client UI
10. verify approved record is visible there

---

## Review Summary

### Decision

For the next implementation step, use:

- **backend mode**
- **local Postgres first**
- **operator app for internal review**
- **simple web dashboard for client approved results**

### After validation

Move the backend persistence layer to:

- **Supabase Postgres**
- **Supabase Storage**

without changing the app or client contract.
