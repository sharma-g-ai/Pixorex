---
last_mapped_commit: 64405acfa13ec78cf102cb081212fd931bb8a4e4
last_mapped_at: 2026-10-11
---
# Codebase Concerns

**Analysis Date:** 2026-10-11

## Tech Debt

**Oversized controller with mixed responsibilities:**
- Issue: `ppg_session_controller.dart` is 1,742 lines managing session lifecycle, page capture, OCR orchestration, database operations, state validation, and UI coordination in a single class
- Files: `frontend/lib/features/ppg_delivery_note/services/ppg_session_controller.dart`
- Impact: Difficult to test, high cognitive load, fragile to changes, concurrency bugs hard to isolate, state transitions opaque
- Fix approach: Extract into multiple focused services — separate session persistence, OCR pipeline, page management, and validation concerns into distinct classes. Use composition instead of monolithic controller. Add integration tests for interaction between services.

**Database migration chain without rollback protection:**
- Issue: 9 sequential database upgrade paths (`_upgradeToV1` through `_upgradeToV9`), each must succeed atomically or migration fails partially
- Files: `frontend/lib/features/ppg_delivery_note/persistence/ppg_repository.dart` (lines 19-50)
- Impact: Failed upgrade leaves DB in inconsistent state; no migration rollback; data corruption on version mismatch; field renames/removals could lose data
- Fix approach: Add pre-migration validation, wrap each upgrade in transaction with rollback on failure, add migration verification step, keep schema versioning documentation

**Large screen widgets with mixed UI/logic:**
- Issue: `ppg_page_review_screen.dart` (1,019 lines), `ppg_can_scanner_screen.dart` (860 lines), `ppg_capture_screen.dart` (717 lines) — each bundles complex layout, state management, and business logic
- Files: `frontend/lib/features/ppg_delivery_note/screens/*.dart` (multiple files >500 lines)
- Impact: State bugs in UI, difficult to refactor layout, testing requires full widget tree, navigation logic entangled with rendering
- Fix approach: Extract state management to controllers, separate layout builders into reusable components, move business logic to domain/services layer

**Parser with fragile regex patterns:**
- Issue: `ppg_template_parser.dart` (760 lines) uses multiple overlapping regexes for document structure detection (page numbers, delivery note IDs, piece counts, article patterns). Patterns assume specific text layouts and font characteristics
- Files: `frontend/lib/features/ppg_delivery_note/parser/ppg_template_parser.dart` (lines 11-25)
- Impact: Parsing silently fails or returns null values if document format varies; no error reporting; hard to debug which pattern failed; variations in OCR output break assumptions
- Fix approach: Add structured pattern matching with diagnostics, test against expected failure cases, add fallback patterns for common OCR errors, return explicit failure reasons

## Known Bugs

**OCR adapter returns null without context:**
- Symptoms: If Android bridge returns `null` in `recognize()` or `recognizeCrop()`, throws generic `StateError` without caller knowing what failed
- Files: `frontend/lib/features/ppg_delivery_note/ocr/ppg_ocr_adapter.dart` (lines 35-36, 83)
- Trigger: ML Kit MethodChannel fails, timeout, or bridge crashes; happens on real devices not emulator
- Workaround: Restart app or switch to developer fixture mode

**Image persistence race condition with tmp files:**
- Symptoms: Orphaned `.jpg.tmp` or `.png.tmp` files accumulate in `ppg_evidence/` directory; occasionally image load fails with "file not found" even though capture succeeded
- Files: `frontend/lib/features/ppg_delivery_note/persistence/ppg_repository.dart` (lines 244-266)
- Trigger: App crash or kill during `tmp.rename()` after file write succeeds; concurrent page captures to same session; file system full
- Workaround: Manual cleanup of `ppg_evidence/{sessionId}/*.tmp` files, then retry capture; ensure device has >100MB free

**Database read during V9 migration can include stale records:**
- Symptoms: After upgrade to build 36, some sessions show counts as "notChecked" when they were previously entered; data not lost but requires re-entry
- Files: `frontend/lib/features/ppg_delivery_note/persistence/ppg_repository.dart` (lines 209-228)
- Trigger: Upgrade from build 35→36 with active sessions in counting state
- Workaround: Confirm all physical counts before closing app before upgrade to latest build

## Security Considerations

**Image files stored unencrypted on device:**
- Risk: Captured delivery note pages (with article/quantity data) stored as plaintext JPEG/PNG in app's documents directory without encryption
- Files: `ppg_evidence/{sessionId}/*.jpg` and `ppg_evidence/{sessionId}/*.png`
- Current mitigation: Android app sandboxing provides file-level access control via OS; files only accessible to app
- Recommendations: Add optional encryption for sensitive captures; implement cache clearing on logout; document retention policy for operators

**Temporary image files could be recovered after deletion:**
- Risk: Failed captures or interrupted uploads leave `.tmp` files on device; secure deletion not guaranteed on all file systems
- Files: `frontend/lib/features/ppg_delivery_note/persistence/ppg_repository.dart` (line 264 rename operation)
- Current mitigation: Tmp files stored in app-private directory; overwritten by subsequent captures
- Recommendations: Add explicit secure file wipe for sensitive images; implement retention period for tmp files; log all image persistence operations

**Backend API authentication token in environment variable:**
- Risk: `LABEL_READER_BACKEND_TOKEN` stored in `.env` or environment; not consumed by PPG but present in backend setup
- Files: `backend/README.md`, `backend/.env` (not readable - secrets forbidden)
- Current mitigation: PPG explicitly isolated — no network egress from feature paths (per `IMPLEMENTATION_STATUS.md`)
- Recommendations: Ensure token rotated regularly; never commit to version control; use secrets manager for deployment

**No input validation on OCR confidence thresholds:**
- Risk: Parser accepts OCR elements with any confidence value; low-confidence reads treated same as high-confidence
- Files: `frontend/lib/features/ppg_delivery_note/ocr/ppg_ocr_adapter.dart` (line 110 accepts optional confidence without filtering)
- Current mitigation: Manual review required before physical count; submitted forms marked read-only
- Recommendations: Add confidence filtering, flag low-confidence reads in UI, require explicit confirmation for reads below threshold

## Performance Bottlenecks

**OCR runs on full page on every capture:**
- Problem: Parser runs `PpgTemplateParser.parse()` on entire OCR observation for every captured page, even if only one field needs reading
- Files: `frontend/lib/features/ppg_delivery_note/services/ppg_session_controller.dart` (lines 187-207)
- Cause: No caching or incremental parsing; full document layout analysis on every page load during session resume
- Improvement path: Cache parsed results per capture ID, implement field-specific OCR crops, lazy-load parsing for pending pages, parallelize across multiple pages

**Can scanner consensus waits for 3 frames before accepting:**
- Problem: Scanner blocks UI until 3 fresh agreeing OCR frames captured; on low-light/moving devices can take 30+ seconds
- Files: `frontend/lib/features/ppg_delivery_note/screens/ppg_can_scanner_screen.dart` (domain logic in `CanArticleConsensus`)
- Cause: Conservative approach for accuracy; no adaptive threshold for high/low confidence reads
- Improvement path: Reduce threshold to 2 frames for high-confidence reads, implement timeout with "low confidence but accept anyway" option, parallelize frame processing

**Image file writes are synchronous with UI:**
- Problem: Large image persistence operations (crop, rectify, persist) block main thread; perceptible UI lag on slower devices
- Files: `frontend/lib/features/ppg_delivery_note/services/ppg_session_controller.dart` (line 265 `readAsBytes()`, line 289 `readAsBytes()`, line 297 `updatePageCapture()`)
- Cause: No async batching or worker thread; file I/O on main isolate
- Improvement path: Move image I/O to compute isolate, implement background queue for image persistence, add progress indicator for multi-page imports

## Fragile Areas

**Perspective warp with hardcoded scale assumptions:**
- Files: `frontend/lib/features/ppg_delivery_note/parser/ppg_template_parser.dart` (lines 37-38)
- Why fragile: Parser assumes baseline image resolution 1224×1584 and clamps scale to [1.0, 4.0]; captures at unusual resolutions (ultra-wide, portrait rotated) or from different cameras could produce unscaled elements
- Safe modification: Add device/resolution detection tests; parameterize baseline; validate scale assumptions with fixture images from multiple devices
- Test coverage: Only `image_preprocessing_test.dart` covers scaling; no tests for edge resolutions

**Page number extraction from image header region:**
- Files: `frontend/lib/features/ppg_delivery_note/parser/ppg_template_parser.dart` (lines 65-77)
- Why fragile: Assumes page "X / Y" always appears in top 25% of image and right >65% width; fails if header moved, image cropped, or pages printed at bottom
- Safe modification: Add header detection validation, allow operator to manually specify page count, test with real PDFs printed at different scales
- Test coverage: Parser test uses single fixture PDF; no tests with varying page layouts

**Picking list vs delivery note detection via label recognition:**
- Files: `frontend/lib/features/ppg_delivery_note/parser/ppg_template_parser.dart` (lines 60-64)
- Why fragile: Detects document type by presence of "Delivery" + "Note" text or "Picking" label; OCR errors or missing labels cause silent misclassification
- Safe modification: Add explicit document type confirmation step, provide fallback manual selection, add confidence score for auto-detection
- Test coverage: Only golden fixture tested; edge case of ambiguous layouts not covered

**Physical count state transitions assume single path:**
- Files: `frontend/lib/features/ppg_delivery_note/persistence/ppg_repository.dart` (lines 217-224 V9 migration)
- Why fragile: Migration assigns state based on `physical_quantity_confirmed` and `physical_origin` flags; adds intermediate states (`counting`, `recheck`) but no guard against concurrent state mutations
- Safe modification: Add state machine validation, prevent invalid transitions, add audit log for state changes
- Test coverage: Receiving workflow test exists but doesn't cover all state transition paths

**Database query aggregations could return wrong results if records deleted concurrently:**
- Files: `frontend/lib/features/ppg_delivery_note/persistence/ppg_repository.dart` (lines 293-304)
- Why fragile: `listSessionProgress()` uses COUNT/SUM aggregations without row-level locking; if lines/adjustments deleted mid-query, progress counts mismatch actual data
- Safe modification: Add query-level transaction isolation, use explicit locks for progress queries, validate counts after loading
- Test coverage: No concurrent access tests

## Scaling Limits

**Single SQLite database file for all sessions:**
- Current capacity: Tests pass with 71 cases; no load testing for 100+ sessions with 1000+ line items
- Limit: SQLite not optimized for >100K rows in single file; query performance degrades; concurrent writes serialize on file lock
- Scaling path: Migrate to local SQLite for current session only + archive older sessions; add query indexing on `session_id`, `article_number`, `capture_revision`; implement read replicas for reporting

**Image storage in app documents directory:**
- Current capacity: ~1MB per page capture (source + rectified); 100 pages = ~200MB
- Limit: Device storage limit (typical phone 32-128GB free); no automatic cleanup; images never deleted unless session deleted
- Scaling path: Implement image retention policy, compress source images, archive old sessions to external storage, add storage quota warning

**Mobile app memory for large sessions:**
- Current capacity: Controller loads all pages + lines + contexts into memory; typically <50MB for 50-page session
- Limit: Low-end Android devices (1-2GB RAM) could run out of memory for sessions >100 pages or when other apps active
- Scaling path: Implement lazy loading for page list, paginate document lines in UI, release image data after OCR complete

## Dependencies at Risk

**ML Kit bundled only — no cloud fallback:**
- Risk: If ML Kit fails (device too old, insufficient permissions, corrupted binary), OCR completely blocked; no fallback to cloud vision
- Impact: Session cannot proceed past page capture on affected devices
- Migration plan: Add OpenAI Vision as fallback (would require network connection), implement graceful degradation with manual field entry

**SQLite schema versioning without version pinning:**
- Risk: Future migrations could corrupt data if migration logic has bugs; no rollback capability once migration runs
- Impact: Data loss, unrecoverable sessions
- Migration plan: Pin schema versions, add pre-migration validation, implement blue-green migration testing

**Regexes for document parsing not version-controlled:**
- Risk: If PDF format changes (new section headers, different article field positions), parsing breaks silently with no indication
- Impact: Silent data loss (articles/quantities become null, undetected)
- Migration plan: Version parsing rules, add document version detection, make patterns configurable per document variant

## Missing Critical Features

**No retry mechanism for failed OCR:**
- Problem: If OCR fails, user must manually re-capture; no automatic retry with backoff or fallback to lower resolution
- Blocks: User forced to retry multiple times on poor lighting; no way to skip and enter manually
- Workaround: Switch to developer import mode, enter values manually

**No audit trail for physical count changes:**
- Problem: History of who changed what count and when not recorded; only final values stored
- Blocks: Cannot verify data integrity for audit purposes; cannot trace origin of variance
- Workaround: Session operator email recorded but not tied to individual changes

**No export format beyond local submission:**
- Problem: No standard export (CSV, JSON, PDF) for completed sessions; only internal SQLite format
- Blocks: Data cannot be easily integrated with external systems without direct database access
- Workaround: Manually copy values from UI

**No offline queue for submissions with network fallback:**
- Problem: Submission only works while offline (stored locally as `SUBMITTED_LOCAL`); no cloud sync when network available
- Blocks: Cannot persist to external system; submitted forms not accessible across devices
- Workaround: Manual export from device storage

## Test Coverage Gaps

**No tests for major UI screens:**
- Untested area: `PpgPageReviewScreen` (1,019 lines), `PpgCanScannerScreen` (860 lines), `PpgCaptureScreen` (717 lines)
- Files: `frontend/lib/features/ppg_delivery_note/screens/ppg_page_review_screen.dart`, `ppg_can_scanner_screen.dart`, `ppg_capture_screen.dart`
- Risk: Navigation flows, button interactions, form validation, state persistence across screen transitions could break unnoticed
- Priority: High — these are user-facing screens; bugs here directly impact usability

**No tests for OCR error handling:**
- Untested area: OCR adapter exception paths, MethodChannel failures, null returns from ML Kit bridge
- Files: `frontend/lib/features/ppg_delivery_note/ocr/ppg_ocr_adapter.dart` (all exception paths)
- Risk: Unhandled exceptions crash app; generic error messages confuse users; device-specific failures only found in production
- Priority: High — affects all page captures

**No tests for camera lifecycle and permission handling:**
- Untested area: Camera initialization, permission denial, lifecycle resume/pause during scan, device rotation
- Files: `frontend/lib/features/ppg_delivery_note/screens/ppg_can_scanner_screen.dart` (lines 70-100, 64-68)
- Risk: Camera resource leaks, black screen on permission denial, crash on device rotation mid-scan
- Priority: Medium — can be worked around by restarting app

**No tests for database concurrent access:**
- Untested area: Simultaneous page capture saves, physical count updates, session queries during writes
- Files: `frontend/lib/features/ppg_delivery_note/persistence/ppg_repository.dart` (all DB methods)
- Risk: Race conditions, lost updates, corrupt session state on concurrent operations
- Priority: Medium — visible only under load or with fast user interactions

**No tests for image persistence failure modes:**
- Untested area: Disk full, permission denied, tmp rename failure, file already exists race condition
- Files: `frontend/lib/features/ppg_delivery_note/persistence/ppg_repository.dart` (lines 244-266)
- Risk: Orphaned tmp files, silent image loss, user-facing errors on capture
- Priority: Medium — affects document integrity

**No tests for parser with OCR output variations:**
- Untested area: Parser assumes good OCR quality; no tests for merged lines, duplicated text, rotated/skewed pages
- Files: `frontend/lib/features/ppg_delivery_note/parser/ppg_template_parser.dart` (entire parse logic)
- Risk: Parser returns null fields silently; user doesn't realize article/quantity not captured
- Priority: High — affects core data accuracy

---

*Concerns audit: 2026-10-11*
