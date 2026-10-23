# Codex implementation instruction — PPG delivery-note mobile scanner

Implement the feature described below in the current repository. Do not stop after producing a plan. Work through the implementation phases, run available checks, and return the implementation and evidence. Do not claim a camera/OCR/device test passed unless you actually ran it.

## Locate and read the handoff

The handoff directory is named `PPG_Delivery_Note_Codex_Handoff_v1`. Find it within the current workspace or at the path I supply. If it is not present, ask for that path; do not invent a source file or substitute another delivery note.

Read, in order:

1. The repository's applicable `AGENTS.md` files and existing mobile architecture/build instructions.
2. `README.md` and `PPG_DELIVERY_NOTE_HANDOFF.md` in the handoff.
3. `fixtures/dn_5319364114.expected.json`.
4. `contracts/local_submission.schema.json` and `examples/local_submission_with_variance.json`.
5. `review_templates/IMPLEMENTATION_REPORT_TEMPLATE.md`.
6. The original `source/DN 5319364114.pdf` and all four rendered reference pages, especially the set headers on page 2 and batch quantities on page 3.

Verify the provided source hash and run `tools/validate_handoff.py`. These are reference/package checks, not proof that your implementation works. Do not mutate the original evidence or expected fixture merely to make your parser tests pass.

## Product objective and fixed scope

A user scans a physical PPG delivery note using a mobile camera, **one page at a time inside one delivery-note session**. Processing is entirely on-device. All captured pages are consolidated into one review form. The form contains the article number, the document's printed total quantity, and an editable physical quantity. The user reviews, corrects genuine OCR mistakes separately, and submits a final form locally.

The agreed article-number field is exemplified by `445386`, not the material/alternate code `618805ID1500`, an EAN, or the item sequence number. The document total for article `445386` is `8 PC`; batch values `5 PC` and `3 PC` are not additional receipt lines.

The scope stops at `SUBMITTED_LOCAL`: a durable, immutable local snapshot and a local confirmation screen. Do not add an API, backend, queue, outbox, WorkManager sync, connectivity watcher, RabbitMQ/Kafka client, inventory ledger, stock-label scanning, or cloud/local VLM. There is no downstream transport in this implementation.

## Mandatory source-specific rules

The sample's seven quantity-bearing rows are:

- Page 2: `445235 → 15 PC`, `445182 → 15 PC`.
- Page 3: `475212 → 7 PC`, `475210 → 7 PC`, `445377 → 2 PC`, `445386 → 8 PC`.
- Page 4: `445374 → 8 PC`.

Set headers `179061` and `446789` have no printed quantity on their own rows. Preserve them as non-quantity context, with null quantity. Do not assign 15 or 7 to them. The second set continues from page 2 to page 3. Seven rows and 62 pieces are sample expectations, not production constants.

Use text geometry and product-block association, not an entire-page number regex. Product components do not necessarily have a new Item sequence number. Total Qty and Qty per Batch occupy the same horizontal area; vertical/product-block role matters. Nearby colour digits must not turn `8 PC` into `68 PC` or `18 PC`.

## Repository and technology guardrails

Inspect first and record your findings in `IMPLEMENTATION_STATUS.md`. Preserve the repository's existing framework and approved architecture. In an existing Flutter product, keep the feature in Flutter and use native Android adapters where needed. In an existing Kotlin/Android application, retain its native UI and persistence conventions. Do not replace an existing mobile app.

For an empty workspace without an authoritative mobile decision, create an isolated Android-first Flutter implementation with Kotlin CameraX capture/rectification and bundled ML Kit Latin text recognition. Use the project's existing SQLite persistence; otherwise use a suitable SQLite-backed repository, with `sqflite` for Flutter or Room for a native app. Do not duplicate databases across Dart and Kotlin.

The OCR model must be packaged for offline availability. Do not accidentally use the unbundled, download-on-first-use variant. Do not make Google Play's dynamically downloaded document-scanner flow a dependency of first-use offline capture. Keep four-corner manual adjustment and rotation available; automatic edge detection is assistance, not a prerequisite for successful capture.

Existing Pixorex/Sea Stock plans are context, not permission to expand this slice. Reuse an existing capability when it meets these requirements, without modifying approved unrelated workflows.

## Data and correctness requirements

Preserve three separate facts: raw OCR observations, the corrected/verified printed document values, and physically received quantities. Keep a local correction/adjustment history. Initialize physical quantity from the verified document quantity; never record an unobserved OCR confidence such as 0.98. If document quantity changes after a physical count was manually entered, retain that count and require re-review.

Use occurrence-level row IDs and page capture revisions. Rescanning a page replaces that page's derived results, not appends them. Reject stale OCR completions. Do not silently aggregate repeated article numbers from distinct printed rows. Preserve cross-page context and source-image references.

Show missing, duplicate, wrong-document, unreadable, and ambiguous pages explicitly. Allow any capture order but consolidate by verified printed page order. Require all declared pages and resolved blocking issues before final submission. Do not fabricate missing rows, identities, page numbers, or quantities to enable Submit.

Make local submission transactional and idempotent per scan session. A repeated tap or process restart must not create a second local submission. Persist drafts so capture and edits survive process death. Do not describe the result as sent or synchronized.

## Execution and return contract

Follow Phases 0–6 in the handoff. Add genuine parser/domain/persistence/UI tests, not only JSON-fixture comparisons. Keep developer fixture import visibly separate from camera capture. Document actual dependency versions, build commands, results, and limitations.

When hardware is unavailable, implement and run the tests that are possible, provide device-test steps, and mark physical camera/OCR checks `NOT_RUN_DEVICE_REQUIRED`. Do not substitute fixture/manual entry for tested real OCR. No silent network fallback is allowed.

Return the changed files, build/run instructions, test report, sample-extraction report, local-submission example produced by the implementation when available, and an implementation review bundle. Include an APK only when you actually built it. Never include credentials, dependency caches, or unrelated repository content.

Start by inspecting the repository and reading the handoff. Then implement.
