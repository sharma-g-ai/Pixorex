# PPG delivery-note scanner — implementation review

**Updated:** 24 September 2026
**Repository:** `Label_Reader`, branch `feature/ppg-delivery-note-scanner`
**Feature:** `frontend/lib/features/ppg_delivery_note/`

## Findings and changes

The app is Flutter/Dart with an Android Kotlin method-channel adapter. Camera stills use `ResolutionPreset.high`, are adjusted with the existing four-corner perspective warp, and the rectified file is passed to bundled ML Kit Latin text recognition (`com.google.mlkit:text-recognition:16.0.1`). The app persists the original image, rectified image, OCR word text/boxes, capture revision, and correction records locally.

The four-page source PDF prints `5319074922` beside **Order** and `5319364114` beside **Delivery Note**. The latter is the correct delivery identity. The old parser selected the first `53` number in its flattened OCR text, so OCR reading order could seed a draft with the Order number. A draft that retained that identity could repeatedly report the correct note as a mismatch. The actual camera OCR observation was unavailable, so the precise live failure path remains unconfirmed.

Changes made for the proposal:

- Added a per-page review screen after capture/import with source image zoom, detected rows and headings, identity correction, printed-field correction, physical-count editing, source-backed “Add missing item”, and explicit occurrence-coverage and physical-count confirmation.
- Delivery identity is now explicitly verified per page before its parsed rows enter consolidation. A different OCR identity remains reviewable; it cannot merge while unverified. Changing the session identity is allowed only when no other active page could belong to the previous delivery. Otherwise the operator starts a separate session.
- Final local submission requires each active page's verified identity and coverage review, and each receiving row's physical-count confirmation. Existing raw OCR values and operator corrections remain separate.
- An unreadable optional page-1 `Piece` summary no longer blocks a complete form. A readable summary mismatch remains visible and blocks submission until reviewed; acknowledging it is audited and does not alter item quantities.
- Added SQLite migrations for verified page identity, page-review/physical-count confirmation, and summary-mismatch review state. Updated the local-submission schema and example.
- An OCR-missed required `Total Qty` can now be entered against its exact unresolved source occurrence from page review, with the source image available for checking and a required reason recorded in the correction audit. The raw OCR quantity remains null. The row resolves only after this operator correction; other repeated rows remain unresolved until corrected individually.
- Reworked quantity-to-article association to anchor a Total Qty to the nearest product-description baseline before considering its distance from the article code. This prevents a nearby Batch Qty below an article from being borrowed when OCR misses the main quantity. Page 2 tests now assert all four occurrences, exact descriptions, two quantities of 15, two quantity-less set headings, and the missing-Total-Qty/batch-value case.
- Checked both Seastock Delivery Note PDFs page by page. The parser now takes the delivery identity from the **Delivery Note** label, excludes address postcodes above the table from article detection, and keeps Item, material, and colour columns out of the product description. The source-grounded fixtures cover the four-page note's 7 quantity rows (62 PC) and the six-page note's 14 quantity rows (100 PC), with set headings kept separate.
- On page 3 of the four-page note, article `445386` prints `8 PC` in Total Qty and `5 PC` plus `3 PC` in Qty per Batch. A printed colour-code `6` touches the total, so OCR can fuse it as `68 PC`; that remains unresolved until source verification. The review form now scrolls above the keyboard and allows both missing and ambiguous totals to be corrected against the saved page, preserving the correction audit and clearing only the corrected occurrence's blocker. A separate `8 PC` OCR token parses automatically in the new page-3 regression.
- Fixed session restore so it reapplies saved source-verified Total Qty corrections before rebuilding blocking issues. A reopen regression first reproduced the erroneous return of `Ambiguous quantity near colour text for 445386`, then passed after the fix. The review APK version is `1.0.1+2` so Android can distinguish it from the previous `1.0.0+1` build.
- Added an optional Android document-scanner flow with automatic capture, page detection, crop/rotation, cleanup, and a processed-image preview. The existing camera/manual-corner flow remains available. Local post-crop modes provide illumination/contrast correction, grayscale, black-and-white adaptive thresholding, and original color. The untouched input file is retained separately from the app-processed OCR image.

## Milestone status

| Milestone | Status | Evidence / remaining work |
|---|---|---|
| M0 — diagnose | Partial | Repository, image pipeline, OCR engine, dimensions, word boxes, and the DN mismatch code path were inspected. No live failing camera image/OCR trace was available. |
| M1 — page-first review | Partial | Per-page source review, identity confirmation, manual correction, and missing-item entry are implemented. Role-specific minimal forms and review of the unsupported Picking List are not implemented. |
| M2 — guided repair | Partial | Source view and manual correction are available. Tap-to-fill, selected-field crop retry, linked close-up pairing, and coordinate-mapping tests remain unimplemented. |
| M3 — profile/parser | Partial | S1/S2 Colombo synthetic-token fixtures pass. Picking List source-review support is not implemented; its business mapping remains pending and no receiving crosswalk is inferred. |
| M4 — coverage/finalization | Partial | Page coverage, missing-item entry, physical-count confirmation, and local submit gates are implemented. Process-death recovery and controller/UI integration tests remain unverified. |
| M5 — camera/offline verification | Not run | No Android device/emulator or `adb` is available. APK compilation is not camera/OCR evidence. |

## Validation performed

- `flutter analyze lib/features/ppg_delivery_note test/ppg_delivery_note` — PASS, no issues.
- `flutter test test/ppg_delivery_note/` — PASS, 36 tests. Regression coverage verifies label-grounded identity, postal-code exclusion, clean description columns, page 2 and page 3 quantity association, and that Batch Qty cannot fill an OCR-missed Total Qty; correction tests cover missing and colour-fused totals, including persistence across session reopening. A pixel test covers local black-and-white cleanup. Tests do not assess image quality on physical captures or exercise Android scanner integration.
- `python3 ppg_handoff/tools/validate_handoff.py` — PASS, source hashes, reference arithmetic, schema gates, and illustrative example.
- `flutter build apk --debug` — PASS with JDK 17. The build emitted existing Gradle, Android Gradle Plugin, and Kotlin future-compatibility warnings.
- `flutter build apk --release` — PASS with JDK 17. The smaller review APK is signed with the project's configured debug key; no production signing configuration exists.
- `flutter devices` found Linux desktop and Chrome only; `adb` was not installed. Physical-paper, fresh-install offline, ML Kit, latency, and camera tests were not run. No UI screenshots are included because no Android UI session was available.

## Limits and approvals

The tests construct OCR boxes from manually transcribed S1/S2 reference values. They do not measure OCR accuracy. No physical-camera sample, held-out note, target-device list, runtime performance data, or independent review of live OCR output was supplied. The proposed precision/recall targets are unmeasured. Picking List `Material #` → Article and `Order Qty` → Document Quantity remains an unapproved mapping; the current parser rejects that profile rather than treating it as a receiving note.

See [OCR_FAILURE_ANALYSIS.md](OCR_FAILURE_ANALYSIS.md), [PAGE_PROFILE_CONTRACTS.md](PAGE_PROFILE_CONTRACTS.md), [TEST_RESULTS.md](TEST_RESULTS.md), [ACCURACY_REPORT.md](ACCURACY_REPORT.md), [CAPTURE_AND_FIELD_TRACE.json](CAPTURE_AND_FIELD_TRACE.json), and [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md) for the detailed review evidence.
