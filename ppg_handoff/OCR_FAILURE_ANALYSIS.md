# OCR and identity failure analysis

## Evidence path inspected

| Stage | Current behavior | Evidence retained |
|---|---|---|
| Camera | Flutter camera still at `ResolutionPreset.high`; auto framing uses low-resolution preview samples | Original still copied into app-private evidence storage |
| Crop/transform | Operator can rotate and adjust four corners; perspective warp writes a rectified PNG | Original and rectified paths plus rotation are stored on the page capture |
| OCR input | Controller sends rectified image (or source image when no rectified file exists) to Android method channel | OCR run, capture revision, engine name/version, image width/height, elapsed time, word text and boxes are persisted |
| OCR engine | Bundled Android ML Kit Latin recognizer, dependency `16.0.1`; Kotlin decodes bitmap and calls `InputImage.fromBitmap(bitmap, 0)` | Word/line/symbol boxes are returned by Kotlin; Dart currently persists the word-level elements used by the parser |
| Parse/association | Deterministic PPG layout parser chooses Article and main Total Qty; batch values and contextual headings have separate rules | Raw OCR observation and parsed occurrence IDs, roles, source page, and unresolved issues |
| Review/final value | Operator can verify identity, correct printed fields, add an occurrence, and edit actual count | Corrections, physical adjustments, page/capture revision, and local final snapshot |

The rectified image dimensions are returned by the native OCR adapter and stored in the observation. The current code does not create an independently retained field crop or a full parser-candidate trace for every rejected token. The Kotlin adapter returns symbols, but the Dart observation currently stores word elements only.

## Reported mismatch

The user reported `expected 5319074922, got 5319364114` and stated that `5319364114` is the delivery on the paper. On page 1 of the supplied four-page PDF, `5319074922` is explicitly printed as the **Order** number; `5319364114` is explicitly printed as the **Delivery Note** number (PDF SHA-256 `7c4e1acec8441193375ca36c8f77f935630913adbebd31f78dea3e82d886780c`).

**Classification:** the old parser's first-number rule could confuse the printed Order with the Delivery Note if OCR reading order put Order first. A draft could then retain the wrong expected identity and repeat the mismatch. The live OCR text/boxes and session ID were not supplied, so this is a demonstrated parser defect and plausible explanation, not a verified replay of the user's capture.

## Code-path defect corrected

Previously, the first non-null OCR delivery number filled `session.deliveryNoteNumber`. Any later different number marked its page failed and inactive before the operator could inspect the saved source. Reopening the old draft could repeat the same expected/observed comparison.

Now a page with a differing OCR identity remains available to inspect. It is excluded from consolidation until the operator confirms the printed delivery identity and page number. If the operator confirms that it belongs to another delivery while other active pages exist, the controller requires a separate session. The OCR-observed number remains stored separately from the verified number. The UI exposes “Start separate delivery scan” from the session warning.

The parser now associates a `53` number with the **Delivery Note** label before using any bare-number fallback; a number beside **Order** is excluded from that fallback. Source-backed regression tests exercise both separated and joined OCR header lines. Product parsing begins below the printed table header, excluding `1400 COLOMBO` and `0000 COLOMBO` from article candidates. Description extraction starts in the Description column and stops at the printed material code, leaving colour and Item values out of product context.

This prevents the app from silently combining two documents. It does not correct a bad OCR model output automatically; an operator must compare the printed identity with the saved source.

## Failure stages that remain unclassified

For four-page note page 3, the paper shows article `445386`, Total Qty `8 PC`, and batch values `5 PC` and `3 PC`. A colour-code `6` immediately precedes the printed total. If OCR returns `68 PC` across the colour/Total Qty boundary, the parser deliberately marks it ambiguous. If OCR returns separate `8 PC` word geometry, a source-shaped regression shows the parser extracts 8. The operator reported `UNRESOLVED_MISSING_TOTAL_QTY` on their capture, which means no usable total candidate survived the parser checks; the saved OCR observation is needed to tell an OCR miss from a geometry rejection. The page-review correction dialog also overflowed when the keyboard opened, preventing entry of the printed 8. That layout defect has been fixed by making the dialog scrollable.

The operator subsequently reported `AMBIGUOUS_COLOUR_QTY_BOUNDARY` recurring. The source-level ambiguity is expected if OCR fuses the colour digit and total. A separate controller defect caused recurrence after correction: `loadSession` rebuilt blocking issues from the raw parsed page without applying the saved source correction. It now reapplies saved Total Qty corrections before rebuilding blockers; the reopen regression covers that path. The raw OCR remains preserved for audit.

- Blur, glare, skew, resolution loss, or crop damage on a live camera image.
- Native OCR recognition of the delivery number, article, or quantity.
- Geometry-based association between a row and its Total Qty on a live OCR capture.
- Whether the repeated expected value was seeded by the parser's old Order/DN confusion or by another stale draft/session path.
- OCR latency, confidence distribution, retry rate, and correction burden on intended devices.

Capture an authorized local diagnostic trace containing source and rectified dimensions, the OCR input path, OCR text/boxes, page/capture revision, parser candidates/issues, displayed field, and source-corrected value before assigning any of those causes. Do not send document content or images to telemetry.
