# PPG delivery-note mobile scanner
## Implementation plan and self-contained Codex handoff — v1

**Prepared:** 24 September 2026  
**Reference document:** `source/DN 5319364114.pdf`  
**Feature boundary:** physical page capture through a final, locally submitted consolidated form.  
**Implementation status at handoff:** not implemented here; repository and device have not been inspected/tested in this chat.

> This is the original v1 design handoff. The repository has since been inspected and partially updated. Use `IMPLEMENTATION_REPORT.md` and the field-first proposal review artifacts in this package for current implementation and validation status.

This document separates **user-agreed requirements**, **observations from the supplied PDF**, and **proposed implementation defaults**. The supplied PDF is authoritative for the sample's printed content. It is not evidence of how an ERP counts sets, which mobile framework the repository currently uses, or achievable OCR accuracy on camera images. Technical defaults below are implementation recommendations, not additional business requirements silently attributed to the sample.

---

# 1. Objective, agreed context, and non-goals

## 1.1 The operational task

An operator has a physical delivery note and physically delivered stock. The operator captures the paper with a mobile camera. The application reads the delivery note's article numbers and printed total quantities, consolidates the pages, and shows one editable receiving form. The operator compares physical stock with the note, adjusts physical quantities when needed, and submits the final form.

The input is a **stable PPG delivery-note format**, but page count, row count, text lengths, positions after photographing, and product content may vary. A fixed document family does not mean fixed pixel coordinates or a fixed list of seven articles.

## 1.2 User-agreed requirements

| ID | Requirement |
|---|---|
| R01 | Capture one physical page at a time within one delivery-note scanning session. Do not photograph all sheets together. |
| R02 | Perform capture processing and extraction on the device; no runtime cloud inference. |
| R03 | Use on-device OCR plus deterministic layout/product-block parsing as the primary extraction approach. No VLM is required in this slice. |
| R04 | `article_number` refers to the short numeric identifier exemplified by `445386`. It is not the adjacent product/material code, EAN, batch ID, or Item sequence number. |
| R05 | Extract the product's printed **Total Qty**. Do not treat **Qty per Batch** values as additional article quantities. |
| R06 | Consolidate pages into one document-level form, preserving each printed quantity-bearing occurrence. |
| R07 | Display document quantity and editable physical quantity separately. |
| R08 | Distinguish an OCR correction from a physical stock variance; preserve the original observation. |
| R09 | Stop implementation at final-form submission. The local finalization behavior is specified in section 7. |

## 1.3 Explicitly outside this implementation

Do not implement backend APIs, authentication infrastructure, downstream transport, connectivity monitoring, an outbox, retries to a server, WorkManager synchronization, RabbitMQ/Kafka integration, inventory posting, consumption/transfer workflows, physical container/label scanning, ERP reconciliation, cloud OCR, VLM inference, general invoice extraction, signature/stamp recognition, handwriting recognition, or a general PDF editor.

The user edits the **form**, not the original PDF or scanned image. The original evidence remains unchanged. The feature does not establish that goods have been posted to inventory.

Use existing application identity/context where available, but do not introduce a new login or tenant model. Do not alter the approved Pixorex product baseline or expand a candidate Sea Stock module merely because those products are related. This is a bounded receiving-document capture slice.

---

# 2. Source audit and corrected sample expectations

## 2.1 Evidence identity and inspection

The package includes the exact uploaded PDF and four rendered page images. Its SHA-256 is recorded in `fixtures/dn_5319364114.expected.json` and the package manifest. The PDF has four pages. Programmatic inspection found no native text on any page; each page contains one raster image. The PDF page containers are 612 × 792 points. The supplied renders are 1224 × 1584 pixels.

The article/quantity ground truth was **visually transcribed from the rendered pages**. No OCR engine or mobile application was executed to produce it. A render of a supplied PDF is not a photograph of a physical printout, and testing that render does not prove camera robustness.

Source locator notation in this handoff: **S1 p1** means page 1 of `source/DN 5319364114.pdf`; likewise p2–p4. These locators are usable without access to the originating chat.

## 2.2 Page roles

| Printed page | Observed role | Extraction consequence |
|---|---|---|
| 1 / 4 | Delivery header, note number `5319364114`, barcode, summary/receiver information. | Capture identity and page metadata. No product receipt rows should be emitted from its packaging/weight summary. |
| 2 / 4 | First product table; first set and its components; second set heading appears near the bottom. | Extract two quantity-bearing rows and preserve two set headings as context. |
| 3 / 4 | Continuation of the second set, followed by two standalone product rows and batch details. | Extract four quantity-bearing rows. Do not count batch details again. |
| 4 / 4 | Final product row in a shorter table body. | Extract one quantity-bearing row. Do not require the table to fill the page. |

The delivery-note number and printed page indicators are repeated on the sample's pages. All declared pages are required by the proposed completeness gate. Barcode decoding is optional; do not add it as a prerequisite when printed identity is readable. **[Source: S1 p1–p4.]**

## 2.3 Seven directly printed article–quantity pairs

| Order | Article number | Printed total | Unit | Source page | Product context for human verification |
|---|---|---:|---|---:|---|
| 1 | `445235` | 15 | PC | 2 | S COVER 456 BAS GREY |
| 2 | `445182` | 15 | PC | 2 | S COVER 256/435/456/522 HRD |
| 3 | `475212` | 7 | PC | 3 | S PRIME 200 BAS YEL/GREEN |
| 4 | `475210` | 7 | PC | 3 | S PRIME 200 HRD |
| 5 | `445377` | 2 | PC | 3 | S RINE 48 GREEN |
| 6 | `445386` | 8 | PC | 3 | S RINE 48 RED |
| 7 | `445374` | 8 | PC | 4 | S RINE 48 BLUE |

Descriptions are context, not required business output fields. Article/quantity pairs are the normative reference values for this POC. **[Source: S1 p2–p4.]**

## 2.4 Two set headings without their own printed totals

| Article number | Heading | Printed total on its own row | Proposed handling |
|---|---|---|---|
| `179061` | S'COVER 456 SET GREY | Not printed | Preserve as non-quantity set context with `null`. Do not create a receiving quantity from its children. |
| `446789` | S PRIME 200 SET YEL/GREEN | Not printed | Preserve as non-quantity set context with `null`; its component section continues onto page 3. |

The visual arrangement supports treating the corresponding component sections as grouped context. It does **not** establish a commercial set-to-component conversion or authorize inventory accounting at set level. Parent/child display association is a layout interpretation; direct article/total extraction must not depend on inventing a set quantity. **[Source: S1 p2–p3.]**

**Correction to previous illustrative messages:** a preceding conversational form incorrectly assigned quantities to `179061` and `446789`, omitted `445182`, and described eight quantity-bearing rows. That form is superseded by this audit and the included expected fixture. Do not implement it as a test oracle.

For the sample only, `15 + 15 + 7 + 7 + 2 + 8 + 8 = 62 PC`. Page 1 also displays `Piece:62`. This is a useful reference cross-check, not permission to force results to 62 or assume that every future packaging summary has identical semantics. **[Calculation from the table above; source of header check: S1 p1.]**

## 2.5 Difficult structures already present in this sample

**Batch repetition:** article `445386` has total `8 PC`, with batch quantities `5 PC` and `3 PC`. Extract one article occurrence with total 8. The batch sum may corroborate a total, but must not replace a missing or unreadable total automatically. **[S1 p3.]**

**Nearby colour digits:** the red and blue product rows have colour text ending near the quantity column. OCR may combine colour digits with the adjacent `8 PC`. Do not accept `68 PC` or `18 PC` merely because a whole-row regex finds them. Use element/symbol geometry or a targeted quantity-region recognition pass; otherwise require correction. **[S1 p3–p4.]**

**Components without Item sequence numbers:** some quantity-bearing rows do not begin with a new number in the far-left `Item` column. A parser driven only by Item numbers will miss component rows. **[S1 p2–p3.]**

**Page continuation:** the second set heading is on page 2, while its quantity-bearing components are on page 3. Capture order must not determine the resulting associations. **[S1 p2–p3.]**

---

# 3. Repository-first implementation and offline technology baseline

## 3.1 Inspect before selecting a framework

Codex must inspect the actual repository and report the mobile framework, existing capture/OCR capabilities, local persistence, state management, dependency versions, build commands, and applicable repository instructions. The repository was not provided for inspection in this chat.

Preserve an existing Flutter application. Preserve an existing native Kotlin/Android application. Do not rewrite an application solely to match a previous conversational stack table.

**Proposed greenfield fallback:** an isolated Android-first Flutter feature using Kotlin adapters for native camera/OCR work. Keep the business parser, review form, and application state in the established application layer. Flutter supports integration with Kotlin through platform channels; use the repository's existing bridge convention or a typed bridge where practical. **[Technical basis: W1.]**

An Android-first POC does not establish iOS readiness. Shared interfaces may be designed sensibly, but do not implement or claim an iOS capture/OCR path unless specifically part of the actual target repository and verified separately.

## 3.2 Components and boundaries

| Capability | Proposed implementation | Boundary |
|---|---|---|
| Camera preview/still capture | Existing offline camera capability or Android CameraX | Capture high-resolution stills, not screenshots of the preview. CameraX supports saving captures to a file. [W2] |
| Page correction | Local four-corner crop/rotation/perspective correction; automatic corner suggestion where feasible | Retain a manual adjustment path. OpenCV provides perspective transforms, but preserve an existing suitable implementation. [W3] |
| OCR | Bundled ML Kit Latin text-recognition model | Native adapter returns raw text, geometry, model metadata, and available confidence; it does not decide receiving semantics. [W4, W5] |
| Extraction | Deterministic, testable template/product-block parser | Independently testable without camera hardware or an OCR SDK. |
| Drafts and submission | One SQLite-backed repository | Reuse existing persistence; Flutter can use `sqflite`; a native app can use Room. Do not create parallel Dart and Kotlin databases. [W6, W7] |
| Evidence images | App-private persistent storage | Preserve source/rectified versions and references; do not depend on temporary cache files for submitted evidence. [W8] |

The technical sources establish library capabilities, not performance or extraction accuracy on these documents. Chosen versions and platform requirements must be verified in the implementation environment and recorded in its dependency lockfiles/report.

## 3.3 Important first-use offline trap

ML Kit offers bundled and unbundled text-recognition installation choices. The bundled variant packages the model with the application; the unbundled variant requires a download. Use the bundled Latin recognizer for this requirement. The dependency family is `com.google.mlkit:text-recognition`, not the download-on-demand Play-services equivalent. Resolve and pin an actually compatible version rather than copying an arbitrary latest version. **[W4.]**

The separate Google ML Kit **Document Scanner** API dynamically downloads its models/scanning UI through Google Play services. Therefore it must not be the required capture path for an application expected to work on first launch without connectivity. A previously warmed scanner is not evidence of fresh-install offline capability. Use packaged local capture/rectification instead. **[W9.]**

Build-time dependency downloads are different from runtime downloads. The development machine may need connectivity to assemble the APK; the operator must not need a network to capture, recognize, review, edit, or submit locally.

An offline-capable model does not itself prove that every host-app dependency is free of telemetry. Inspect the feature's egress paths and the host analytics/backup configuration. Do not upload note content, images, raw OCR, or form values. In an existing network-enabled product, isolate this feature rather than deleting unrelated network permissions globally.

---

# 4. User experience and page lifecycle

## 4.1 Screens in the bounded feature

**Start/resume:** show a new scan action and unfinished locally saved sessions. A submitted form can be reopened read-only from its local confirmation/history route. No server connection is required.

**Capture page:** camera preview, framing guide, capture, rotate, adjust four corners, retake, and accept page. Provide focus/lighting guidance and do not silently accept an obviously incomplete sheet. Preserve the original image before any correction.

**Session pages:** thumbnails, verified delivery-note identity, expected page count, captured/missing page numbers, and per-page OCR status. The operator can capture another page, replace a page, or inspect evidence. OCR can run after each accepted page while further capture continues.

**Consolidated review:** one document-level form, ordered by printed page and source row. Show article, printed document quantity, editable physical quantity, and a visible variance when they differ. Set headings may appear as non-editable grouping context. Each row has a source-page/crop action and a separate `Correct scan result` action.

**Local confirmation:** show the local submission ID, document identity, time, and a read-only snapshot. Use wording such as `Final form saved on this device — not sent to any server`. Do not use `Synced`, `Uploaded`, `Queued`, or `Inventory updated`.

## 4.2 Normal path

```text
Start or resume one delivery-note session
→ Capture a page
→ Confirm crop/rotation and save source evidence
→ Read identity/page metadata and recognize the table on-device
→ Capture remaining pages, with processing status visible
→ Finish scanning / Review items
→ Resolve scan issues and check completeness
→ Confirm article/document values; edit physical quantities as necessary
→ Review variances
→ Submit final form locally
→ Show immutable local confirmation
```

`Finish scanning` may open review with visible blocking issues. It is not equivalent to submission. No final snapshot may be created while required pages, row ambiguities, or field validations remain unresolved.

## 4.3 Page identity and ordering rules

Store delivery-note identity as an identifier string, not a numeric value. Read the printed page number and total page count. Do not hard-code four pages; that is only the reference example.

The first valid captured page establishes tentative session identity and declared page count. It need not be page 1. Each later capture must be compared against that identity. The operator can correct genuinely misrecognized header metadata using its visible source crop and a recorded correction.

| Situation | Required behavior |
|---|---|
| Pages captured in order 3, 1, 4, 2 | Accept verified identity; display/consolidate in printed order 1, 2, 3, 4. |
| Declared page missing | Permit draft/review but block final submission; list the missing page. |
| Same note/page captured again | Offer replacement/retake management, not a second logical page. |
| Different note number | Hold/reject it from this session; do not merge notes silently. |
| Conflicting total page count | Require source inspection/correction; never silently take the larger/smaller value. |
| Unreadable identity/page indicator | Require recapture or source-backed manual correction. No guessing from capture order. |
| Last page has much less content | Accept the page after normal metadata/quality checks. |

There is no missing-page override in this first implementation. A future exception/authorization process is not part of this POC. A manual correction of readable metadata is different from pretending a missing page exists.

## 4.4 Capture revisions and asynchronous work

Each accepted capture has an immutable `page_capture_id`, a logical printed page number, and a monotonically increasing capture revision within its logical page. OCR/parse work references the capture ID and revision it processed.

On replacement, retire the old active revision and rederive affected rows. Never append both versions. A late OCR callback for an inactive capture must not replace the active result. Replacing a source page after manual edits must flag affected rows for re-review; preserve the audit rather than silently applying old edits to unrelated new rows.

Start with one high-resolution OCR job running at a time to bound device memory. This is local processing scheduling, not a downstream business queue. Persist pending/failed processing state so the app can resume from saved images after process death. Do not rely on an in-memory list as the only record of accepted pages.

---

# 5. Extraction contract and algorithm

## 5.1 Capture and image preparation

Retain original colour images. Apply orientation correctly, let the user confirm the page corners, and perform a perspective correction. Keep the transformation/coordinate metadata needed to relate OCR results to source evidence. Avoid stretching every page into an assumed A4 ratio; determine the page geometry from the captured quadrilateral or an explicit, verified template configuration.

Do not introduce blanket grayscale/binarization as an untested default. A targeted preprocessing retry may be evaluated against actual photos, but its result must retain provenance and must not conceal uncertainty. Higher rendered resolution cannot recover missing detail from a low-resolution source image.

Quality indicators may use focus/blur, glare, framing, and anchor detection as signals. They are not calibrated probabilities of correct extraction. Give the user actionable recapture guidance and always permit inspection of the scan.

## 5.2 OCR adapter output

Keep recognition separate from business parsing. An adapter output should include:

```text
page_capture_id and capture_revision
ocr_run_id, engine name/version, processing timestamp and elapsed time
image width/height, applied rotation, coordinate-space identity
text blocks/lines/elements, their raw strings and bounding boxes/corner points
symbol-level geometry when available and required for ambiguous boundaries
engine confidence when actually available, otherwise null
recognition errors, cancellation status, and quality observations
```

ML Kit represents text hierarchically and exposes element geometry and confidence. Availability varies with the selected API/bridge; do not fabricate values when they are absent. Engine confidence is a signal, not a measured probability that an article/quantity pair is correct. **[W4, W5.]**

All template coordinates must be interpreted in a known rectified-image space. Crop-origin offsets, rotation, image rescaling, and perspective mapping must be explicit. A bounding box from a quantity crop cannot be treated as a full-page coordinate without translating it.

## 5.3 Anchor-first, product-block parsing

Use this sequence:

1. Locate/read header identity and the printed page indicator.
2. Classify header-only versus product-table page using the document-family anchors and layout.
3. Locate the table boundary and repeated column/header anchors, including `Total Qty` and product/article fields.
4. Establish column bands relative to those observed anchors, not absolute camera pixels.
5. Build product-block candidates from description rows, article-field position beneath the product text, optional Item sequence numbers, and surrounding layout.
6. Classify candidate regions as a quantity-bearing product block, a set heading without its own total, a batch/detail region, or unresolved content.
7. For each quantity-bearing block, associate the article beneath its description with the **Total Qty on that block's main product baseline**.
8. Use a targeted quantity crop/symbol geometry where neighbouring colour text crosses the OCR token boundary. Preserve conflicting outputs as uncertainty rather than choosing by guesswork.
9. Exclude batch/detail quantities, EANs, material/alternate codes, item sequence numbers, volumes, and weights from article/quantity output.
10. Reconcile blocks across verified page order, retaining set/continuation context without manufacturing parent totals.
11. Emit quantity-bearing line occurrences, preserved context records, blocking/nonblocking issues, and source references for review.

Do not rely on OCR's global text-reading order. Do not pair an article with the nearest `PC` token anywhere on the page. In this template, the article may be on the next line below the product description; the correct total is usually on the main description baseline. The exact association must be tested against observed geometry.

## 5.4 Identifier and quantity validation

Treat article numbers as strings. Preserve leading zeros. For this PPG template, the observed article field is numeric; the sample's identifiers happen to have six digits, but one example does not authorize a global six-digit business constraint. The provided contract permits digit strings of 1–32 characters as a technical bound. A different identifier family requires explicit template/business validation rather than dropping characters.

Do not automatically change `O` to `0`, `I` to `1`, or `G` to `6`. A candidate with an invalid character requires a source-backed correction. Material codes can legitimately contain letters, which is another reason to select the right field geometrically.

For this slice, support nonnegative integer quantities in `PC`. Zero is a valid physical quantity for not-received stock, but must be an explicit value rather than the fallback for an empty input. Reject negative numbers, fractions, overflow, malformed strings, and unsupported units. Do not silently round or convert litres to pieces. Unknown units or illegible totals become review issues.

## 5.5 Context and missing values

A set heading with no printed total is retained as `SET_HEADER_NO_PRINTED_QUANTITY`, not emitted as a quantity-bearing receipt line. The layout must support that classification; an arbitrary product with a missing quantity cannot be hidden by calling it a set.

An ordinary product block with an unreadable/missing total stays `UNRESOLVED`. The user must recapture or correct it from source evidence. Do not derive a total from batch sums or neighbouring product quantities. Do not default its quantity to zero.

Every recognised article-field candidate must be accounted for as a quantity-bearing occurrence, a preserved context row, or an unresolved issue. This guards against silent omission. It does not prove that OCR detected every printed row; the whole-page visual review and independent camera evaluation are still required.

If OCR entirely misses a printed row, a `Correct scan result` workflow may add that **source-backed printed row**, requiring the user to select its source page/region and record a reason. This is not permission to add extra physical stock absent from the note. General not-on-note receiving is out of scope.

## 5.6 Consolidation does not mean blind aggregation

Keep each printed occurrence as a distinct line identified by source/page/block lineage. If the same article appears in two distinct document blocks, retain both occurrences. Do not deduplicate on article number alone, and do not sum them silently. Removing a duplicate capture is a page-identity operation, not article deduplication.

A future business requirement may permit article-level aggregation, but it would need occurrence-level provenance and an explicit rule. It is not needed to produce one consolidated form now.

## 5.7 Pseudocode boundary

```text
recognition = recognize(active_capture)
assert recognition.capture_revision is still active
parsed_page = parse_ppg_template(recognition, template_configuration)
persist_page_result_and_issues(parsed_page)

ordered_pages = active_pages_sorted_by_verified_printed_number(session)
draft = consolidate_occurrences_and_context(ordered_pages)
assert no quantities were invented for missing totals or set headers
show_review(draft)
```

OCR SDK calls belong in the adapter. Geometry/business interpretation belongs in the parser. User corrections and physical counts belong in review/application logic. None of these layers sends a message to a downstream system.

---

# 6. Domain data, form behavior, and audit

## 6.1 Core local records

| Record | Responsibility |
|---|---|
| `ScanSession` | Session identity, tentative/verified note identity, expected page count, lifecycle, form revision. |
| `PageCapture` | Immutable capture identity, printed-page assignment, revision, source/rectified image references, metadata corrections, active/retired state. |
| `OcrObservation` | Immutable recognizer output and geometry for a specific capture revision; no physical receiving values. |
| `ParsedOccurrence` | Article/total candidate, source association, parsing issues, and row role. |
| `DocumentLine` | Corrected/verified printed article, document quantity/unit, source lineage, physical quantity, review status. |
| `DocumentContext` | Set headings/continuation context with no invented quantity. |
| `CorrectionRecord` | Before/after values and reason for correcting recognised document/header content. |
| `PhysicalAdjustment` | Before/after physical count, variance reason, operator context when available, sequence and device time. |
| `SubmittedForm` | Immutable, validated local snapshot, unique for the submitted scan session. |

Use one existing persistence abstraction. Do not turn these conceptual records into unnecessary services or repositories if the application's established architecture has a simpler, coherent representation.

## 6.2 Three facts that must never be conflated

| Layer | Example | Editing rule |
|---|---|---|
| Raw OCR observation | OCR read `445386` and `8 PC` | Immutable observation. A new recognition attempt is a new observation. |
| Verified document values | Article `445386`, document quantity 8 | Only changed through `Correct scan result`, with source inspection and correction history. |
| Physical receiving values | Physically counted quantity 6 | Editable through the normal receiving form; record variance -2 and reason. |

An OCR error is not evidence that stock is short. A stock shortage is not a correction to the paper. This separation is required even when the first OCR result happens to be correct.

## 6.3 Quantity initialization and re-review

Initially set `physical_quantity` to the current verified `document_quantity`, with `physical_quantity_origin = DEFAULTED_FROM_DOCUMENT`. This is a convenience default, not evidence that a person has counted the stock. Require an explicit final review confirmation.

When a user enters the physical field, record `USER_ENTERED`, including when they enter the same number. If document quantity is later corrected and the physical field remains untouched/defaulted, update that default and invalidate review. If the user already entered a physical count, preserve it and invalidate review instead of overwriting it. Recompute the variance and require a reason where it is nonzero.

**Proposed variance rule:** require a short reason for a nonzero variance. Preset choices such as shortage, excess, not received, and other with optional/additional text are sufficient; do not build an approval workflow. Before final submission, show all changed quantities prominently.

On any material change to source identity, article, document quantity, physical quantity, or a participating page revision, invalidate the relevant review confirmation and the final form's ready state.

## 6.4 Correct scan result

This action displays the source crop and raw OCR next to editable verified values. Support article correction, printed-quantity correction, and source-backed recovery of a missed row. Require a reason and preserve the before/after observation/value. Page/header correction follows the same pattern.

Do not expose the trusted document quantity as an ordinary physical-count field. Do not silently overwrite the raw observation when correction is saved. User-entered field validation is the same as parsed-field validation.

A local audit records what this app did; without additional security infrastructure it must not be marketed as a tamper-proof or independently authenticated record. Use existing operator identity where available. Otherwise represent identity as absent/local context rather than inventing a logged-in person's identity. Device timestamps may be inaccurate; retain event sequence/revision information as well.

---

# 7. Final-form contract and local submission semantics

## 7.1 Meaning of Submit in this scope

Submitting creates one durable `SUBMITTED_LOCAL` snapshot for the session. It does not enqueue it for later transmission. Do not implement a disguised outbox under a different table name.

A representative business line is:

```json
{
  "article_number": "445386",
  "document_quantity": 8,
  "physical_quantity": 6,
  "unit": "PC",
  "variance": -2,
  "variance_reason": "Two pieces not physically received"
}
```

This snippet is illustrative. The machine-readable full contract is `contracts/local_submission.schema.json`; the separate example is marked `ILLUSTRATIVE_FIXTURE`, not claimed as an actual OCR run or operator submission.

## 7.2 Required validation before the transaction

The session must have a verified note identity and a consistent declared page count. All declared pages must have exactly one active, accepted capture. OCR/parsing/corrections must have completed for the active revisions. No blocking identity, completeness, row-association, quantity, unit, or source-line ambiguity may remain.

All submitted lines must have valid article/document/physical values, source evidence, and confirmed review. Nonzero variances need reasons. No ordinary line may have a null document quantity. Preserved set contexts may have null printed quantities because they are not quantity-bearing lines.

The submitted form revision must equal the revision the operator just reviewed. A late processing result or simultaneous edit invalidates readiness; do not submit a stale screen state.

## 7.3 Transaction and idempotency

Generate a local submission ID once, serialize an immutable snapshot, and insert it together with the session transition in one local database transaction. Enforce uniqueness by scan session for this slice.

A second tap, retry after a local error, or process restart must return the already-created local submission when it exists, not create another one. Disable repeated UI taps for usability, but do not rely only on the button state for correctness.

Store source images durably before accepting them into a ready form. Database transactions do not atomically protect independent image file writes, so use a staged-file/final-file protocol with recoverable database references. On a save or storage error, remain in a recoverable draft/review state and display the error; do not show success.

After submission, the snapshot is read-only. Post-submission amendment/versioning is a separate future feature. No refresh, re-OCR, or draft mutation may alter the saved snapshot.

## 7.4 Contract versus runtime invariants

JSON Schema validates field shapes, enums, and simple ranges. Runtime/domain checks must additionally enforce:

- page identity/number uniqueness and completeness;
- capture/source-reference existence and active revision matching;
- stable unique line occurrences and valid context references;
- `variance = physical_quantity - document_quantity`;
- reasons for nonzero variances;
- no fabricated set quantities or unsupported unit conversion;
- no fixture/manual test data masquerading as real camera/OCR evidence;
- reviewed form revision and one local submission per session.

The schema deliberately allows `ILLUSTRATIVE_FIXTURE` for the supplied example and developer validation. The production camera submit path must reject that mode and any fixture-transcribed line value. Developer image-import runs must be visibly labelled and must never count as physical-camera validation.

---

# 8. Implementation phases and parallel work

Use these as functional milestones, not invented day estimates. Record completed work, actual commands/results, and remaining blockers after each phase. Do not require a new chat approval between every phase unless repository governance already requires it.

## Phase 0 — Repository and source audit

Inspect applicable instructions, mobile structure, storage, camera/OCR dependencies, toolchain, and current test status. Verify the source hash and read the four page images. Record framework choice and any conflicts with the default plan. Protect unrelated work; do not reset or overwrite user changes.

**Exit:** `IMPLEMENTATION_STATUS.md` records the actual repository, decisions, source identity, dependency plan, baseline checks, and target device-test availability. Source semantics use the corrected fixture.

## Phase 1 — Contracts, domain model, and tests first

Implement the document/line/context/correction/submission types; define capture and OCR adapter interfaces; implement pure validation, consolidation, review invalidation, and idempotent submission semantics. Bring the golden fixture into tests without making runtime code depend on its specific values.

**Exit:** tests demonstrate seven reference quantity rows, two null-quantity context headings, correct variance behavior, and no article-only deduplication. These are domain/fixture tests, not yet OCR success.

## Phase 2 — On-device capture and durable page sessions

Implement camera still capture, rotation, manual four-corner correction, optional automatic corner suggestion, source-image retention, page thumbnails, replacement, and draft recovery. Capture/page metadata can initially be confirmed manually while the native OCR adapter is integrated, but this temporary state cannot be reported as finished extraction.

**Exit:** accepted pages and edits survive process restart; page replacement is revision-safe; manual correction enables a valid capture without a remote scanner service.

## Phase 3 — Bundled OCR and template parsing

Integrate real bundled OCR, collect actual text/geometry from the sample page images, implement anchors/product blocks/quantity association, preserve parent context, and handle continuation/batch/detail regions. Add targeted crop recognition only where justified by failure evidence. Include debug geometry overlays, kept separate from business output.

**Exit:** actual recognizer output has been passed through the parser for the reference fixtures on a supported runtime, or that device/runtime dependency is explicitly reported pending. Synthetic token tests alone do not meet this exit condition.

## Phase 4 — Consolidated review and corrections

Build the one-document review form, evidence preview, physical quantity editing, source-backed scan corrections, issue resolution, row review, and final variance summary. Keep set contexts read-only/non-quantity. Handle pending OCR, recapture, and invalidated review safely.

**Exit:** a user can distinguish and complete an OCR correction and a physical shortage; late changes cannot silently overwrite confirmed input.

## Phase 5 — Transactional local final submission

Implement snapshot validation/save/read-only confirmation, per-session uniqueness, storage-failure handling, and process-death recovery. Ensure no transport/sync module is invoked by this feature.

**Exit:** repeated Submit creates one snapshot; a failed local save never displays success; reopening preserves the exact submitted values and evidence references.

## Phase 6 — Device validation and review handoff

Build the app, run available unit/widget/instrumentation tests, and execute the camera/offline acceptance procedure on target hardware when available. Record engine-only errors separately from manually corrected success. Prepare the implementation report and review bundle.

**Exit:** the implementation is either supported by actual device evidence or clearly marked `DEVICE_VALIDATION_PENDING`; it is never labelled production-ready solely from reference JSON tests.

## Two-developer split when useful

After shared interfaces/fixtures in Phase 1, one developer can own capture, image preparation, and the native OCR adapter; the other can own parsing, local domain/persistence, and the review UI. Agree the OCR DTO/coordinate contract first. Integrate on real recognised page data before polishing the interface. An architect/lead reviews source semantics and the submit boundary; a backend or DevOps deployment is not required for this slice.

---

# 9. Acceptance tests and evidence requirements

Each test result must be recorded as `PASS`, `FAIL`, `NOT_RUN`, or `BLOCKED`, with its actual execution method. Fixture tests, real OCR tests, camera tests, and manually corrected workflows must be separated in reports.

## 9.1 Reference, parser, and semantic tests

| ID | Test | Expected result |
|---|---|---|
| T01 | Parse the complete sample's product evidence. | Seven directly printed quantity pairs match the golden fixture; no invented or omitted pair. |
| T02 | Parse page 2 specifically. | Includes `445235/15` and `445182/15`; set headings do not gain quantities. |
| T03 | Parse article `445386` with total 8 and batches 5/3. | One quantity-bearing occurrence with total 8, not 5, 3, or 16. |
| T04 | Parse the sample's red/blue colour-plus-quantity boundary. | Quantities remain 8, not 68 or 18. Indivisible ambiguous tokens become review issues. |
| T05 | Process page-2/page-3 continuation. | Preserve the second set context and retain `475212/7`, `475210/7` as distinct components. |
| T06 | Process the header page alone. | No product rows from Piece, volume, net weight, gross weight, dates, or note IDs. |
| T07 | Alter sample article/quantity tokens in synthetic geometry fixtures. | Output follows changed evidence; runtime has no hard-coded expected articles or 62-piece total. |
| T08 | Put an EAN/material code/Item number near a candidate. | Only the agreed article field is selected. |
| T09 | Same article on two genuine printed blocks. | Two source occurrences retained; no automatic article-level collapse. |
| T10 | Ordinary row missing its total. | Explicit unresolved issue; no zero, parent/child copying, or batch-sum inference. |
| T11 | Leading-zero article; invalid OCR character; unsupported unit. | Preserve zero; require correction for invalid character/unit; no silent coercion. |
| T12 | Multi-page quantity-bearing block cannot be associated unambiguously. | Preserve evidence and require resolution; do not guess. |

## 9.2 Capture, page management, and offline tests

| ID | Test | Expected result |
|---|---|---|
| T13 | Capture pages 3, 1, 4, 2. | One correct document in printed order, independent of camera order. |
| T14 | Omit page 2 or capture a different note's page. | Missing/wrong-document issue; final submission blocked. |
| T15 | Retake the same logical page using a different photo. | One active page revision; no duplicate rows. Image hash alone is not the page identity test. |
| T16 | OCR completion arrives after that page was replaced. | Stale result rejected. |
| T17 | Blur, glare, cropped edge, rotation, perspective, partial table. | Recapture/review guidance or correct extraction; no falsely complete document from an obviously partial capture. |
| T18 | Page 4 with its shorter table. | Final row retained; no fictitious lower-page rows or fixed-height assumption. |
| T19 | Fresh install/build with bundled assets, radios disabled before first feature launch. | Capture, OCR, review, correction, and local submit complete without runtime model download. |
| T20 | Feature operation and return to host application with network observable. | No document/image/form content egress caused by this feature; no queued downstream transport. |
| T21 | Kill the process during/after page acceptance or pending OCR. | Draft resumes with durable evidence and recoverable processing state. |

## 9.3 Form, correction, and submission tests

| ID | Test | Expected result |
|---|---|---|
| T22 | Physical count for `445386` changed from 8 to 6. | Document stays 8; physical becomes 6; variance -2; reason and adjustment history retained. |
| T23 | OCR quantity corrected before physical field is touched. | Raw OCR retained; document/default physical updated; review invalidated. |
| T24 | OCR quantity corrected after a manual physical count. | Manual physical count preserved; variance recomputed; re-review required. |
| T25 | Blank, negative, decimal, overflowing, and zero physical input. | Invalid input rejected; zero accepted explicitly with appropriate variance reason. |
| T26 | Correct an article or restore a missed printed row with a source crop. | Document correction recorded; not misclassified as a physical stock variance. |
| T27 | Replace a page after its rows were reviewed/edited. | Affected review invalidated; no silent transfer of edits to unrelated new rows. |
| T28 | Tap Submit twice / restart just after the transaction commits. | One local submission; same ID returned/reopened. |
| T29 | Local database/image persistence fails. | No success state and no dangling finalized evidence; recoverable draft/error. |
| T30 | Mutate a draft/source after local submission. | Submitted snapshot remains unchanged and read-only. |
| T31 | Attempt Submit with missing page, pending OCR, ambiguity, or stale form revision. | Blocked with an actionable reason. |
| T32 | Attempt to pass illustrative fixture data as real camera output. | Production submit path rejects it; developer mode remains visibly labelled. |

## 9.4 How to measure extraction without misleading results

For the clean reference images, target exact article/quantity agreement for all seven quantity-bearing rows, with both context headings handled correctly. Record actual raw recognizer output and parser results. A manually entered/corrected result does not count as an automatic extraction success.

Before production use, evaluate actual photographs of multiple distinct notes of the same format. Include different lighting, focus, page positions, product lengths, batch counts, row counts, and page counts. One reference PDF is insufficient to establish generalization or a percentage accuracy claim.

Record article exact-match accuracy, total-quantity exact-match accuracy, correct article/quantity association, omitted/extra rows, manual correction rate, per-page end-to-end latency, and peak memory where measurement is available. Report denominators and device/app/model versions. Do not invent a latency target or claim a numerical accuracy percentage from this package.

For unavailable hardware or SDK tooling, run the pure tests that are possible and provide exact device-test steps. Set the remaining items to `NOT_RUN_DEVICE_REQUIRED`; do not equate emulator image-import tests with printed-paper camera validation.

---

# 10. Security, privacy, and implementation hygiene within scope

Treat all OCR text as untrusted data. It cannot instruct the application to execute code, change configuration, fetch a URL, or bypass validation. Only validated fields enter the domain model.

Persist evidence in app-private files and avoid full note content in console logs, crash reports, or analytics. Keep real commercial samples out of public repositories and public CI artifacts. Use synthetic/redacted fixtures where public test assets are necessary; do not alter the original private reference to hide a failing parser.

Review backup behavior so local note evidence is not inadvertently exported through an unrelated host-app mechanism. Respect existing product security configuration rather than introducing global breaking changes. No broad external-storage permission is justified solely for capturing into app-private storage. **[Storage capability basis: W8.]**

Keep useful debug OCR/geometry overlays behind a developer/debug path. A debug fixture chooser is useful for repeatable testing, but it must not replace the camera route. No backend credentials or LLM keys are needed for this feature.

---

# 11. Required implementation return bundle

Codex should produce a review package named, for example, `PPG_DN_SCAN_IMPLEMENTATION_REVIEW_BUNDLE.zip`, containing the bounded changed source or an applicable patch, contracts, tests, and a concise implementation report. Follow `review_templates/IMPLEMENTATION_REPORT_TEMPLATE.md`.

The report must include repository/framework decisions; dependency versions; exact build/run/test commands; actual results for T01–T32; real recognizer/parser sample outputs when executed; screenshots of capture/session/review/correction/local-confirmation screens; known failures; hardware not available; and remaining business assumptions. Include a debug APK only when actually built, with its hash and install instructions.

Separate these statements explicitly:

- Source reference and schema/package validation completed.
- Domain/parser tests completed using synthetic or recorded evidence.
- Actual on-device OCR completed against reference images.
- Physical-paper camera workflow completed on a named device.
- Fresh-install offline operation completed.

Do not collapse them into one `all tests passed` claim. This handoff's supplied `VALIDATION_REPORT.json` proves only package/reference/schema consistency, not any implemented mobile behavior.

Exclude credentials, signing keys, dependency caches, unrelated repository files, and silently fabricated execution logs. Do not include customer evidence in a public review destination. Preserve the original sample and golden expectation as immutable review inputs; propose corrections with evidence if a real inconsistency is found.

---

# 12. Remaining assumptions and bounded defaults

The Android-first target and repository-first framework rule are implementation defaults; the actual repository is authoritative about an existing framework. The POC assumes integer `PC` quantities. Other units or business identifier families require explicit extension rather than silent conversion.

The source supports seven printed quantity pairs and two quantity-less set headings. It does not settle set-level ERP receipt semantics. This implementation preserves that information without asserting such semantics. Adding set-level physical receiving later is a separate business change.

Manual entry is restricted to correcting or recovering values printed on the scanned note. Additional stock not present on the note, batch-level receiving, and post-submission amendments are not included. No network transport or server acceptance is implied by Submit.

The first release should not be called production-ready until the target device/camera/offline tests and an independent set of physical notes have been evaluated. No such evaluation has been performed while preparing this package.

---

# 13. Official technical references

These references were checked on 24 September 2026. They support the specific library capabilities cited above; the source PDF, user agreement, and proposed design rules remain separate authorities. Codex must verify dependencies against the actual build environment and pin resolved versions.

- **W1 — Flutter platform channels (Kotlin/native integration):** https://docs.flutter.dev/platform-integration/platform-channels
- **W2 — Android CameraX still capture:** https://developer.android.com/media/camera/camerax/take-photo
- **W3 — OpenCV geometric/perspective transformations:** https://docs.opencv.org/4.13.0/da/d54/group__imgproc__transform.html
- **W4 — ML Kit text recognition on Android, bundled/unbundled options and recognizer use:** https://developers.google.com/ml-kit/vision/text-recognition/v2/android
- **W5 — ML Kit Text.Element geometry and confidence:** https://developers.google.com/android/reference/com/google/mlkit/vision/text/Text.Element
- **W6 — Flutter SQLite persistence recipe:** https://docs.flutter.dev/cookbook/persistence/sqlite
- **W7 — Android Room:** https://developer.android.com/training/data-storage/room
- **W8 — Android app-specific storage:** https://developer.android.com/training/data-storage/app-specific
- **W9 — ML Kit Document Scanner download behavior:** https://developers.google.com/ml-kit/vision/doc-scanner/android
