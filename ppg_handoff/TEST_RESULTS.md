# Test results

**Environment:** Flutter SDK at `/home/suchithgoud/flutter`; JDK 17 used for Android build. The environment reports Linux desktop and Chrome; it has no Android device/emulator and no `adb` executable.

## Commands

| Command | Result | What it establishes |
|---|---|---|
| `cd frontend && /home/suchithgoud/flutter/bin/flutter analyze lib/features/ppg_delivery_note test/ppg_delivery_note` | PASS — no issues | Static analysis of the scanner feature and focused tests. |
| `cd frontend && /home/suchithgoud/flutter/bin/flutter test test/ppg_delivery_note/` | PASS — 36 tests | Deterministic parser fixtures, domain validation, and local-submit gates. Regressions distinguish Order from Delivery Note, reject address postcodes as articles, and remove Item/material/colour values from descriptions. Page 3 tests distinguish a separate `8 PC` total from a fused `68 PC` colour/quantity read, verify source correction without borrowing batch 5/3, and confirm the correction remains applied after reopening the session. Other tests cover exact-occurrence correction and black-and-white image cleanup. OCR boxes in fixtures are preconstructed from manual transcription. |
| `python3 ppg_handoff/tools/validate_handoff.py` | PASS | S1/S2 PDF hashes, manually transcribed reference counts/arithmetic, schema guards, example confirmation state, and render presence. Not an OCR test. |
| `cd frontend && JAVA_HOME=<JDK-17> PATH=<JDK-17>/bin:$PATH /home/suchithgoud/flutter/bin/flutter build apk --debug` | PASS | Android app compiles. Existing Gradle 8.14.0, AGP 8.11.1, and Kotlin 2.2.20 compatibility warnings were emitted. |
| `cd frontend && JAVA_HOME=<JDK-17> PATH=<JDK-17>/bin:$PATH /home/suchithgoud/flutter/bin/flutter build apk --release` | PASS | Optimized installable APK builds. The project currently signs its release variant with the debug key; this is a review build, not a store-signing artifact. |
| `flutter devices` | Linux and Chrome only | No Android target available for capture/OCR testing. |
| `adb devices -l` | NOT AVAILABLE — `adb` command missing | No attached Android hardware could be checked. |

The feature suite covers S1 and S2 reference parser behavior, quantity-less headings, batch exclusion, repeated occurrences, unresolved missing quantities, capture-order-independent consolidation, printed-page gates, article/physical variance semantics, optional Piece summary behavior, and local submission confirmation flags. The suite does not exercise Android ML Kit.

## Proposal acceptance matrix

`PASS` below means the listed evidence was exercised by the named synthetic/domain test layer. `PARTIAL` means code exists but the acceptance behavior was not fully exercised. `NOT RUN` means a device/physical-paper or unavailable input is required. `NOT IMPLEMENTED` means the proposal behavior is still absent.

| ID | Result | Evidence / gap |
|---|---|---|
| FC-01 | PASS — fixture parser | S1 page 1 is summary-only; no receiving rows are invented. |
| FC-02 | PASS — fixture parser | S1 page 2 exact 4 occurrence sequence, both receiving quantities are 15, and both set headings retain null quantities and expected descriptions. |
| FC-03 | PASS — fixture parser | S1 page 3 main quantity pairs; batch quantities excluded. |
| FC-04 | PASS — fixture parser | S1 short final page accepted. |
| FC-05 | PASS — fixture parser | S2 preserves 14 source occurrences, total 100 PC. |
| FC-06 | PASS — fixture parser | Repeated `475210` rows remain separate occurrences. |
| FC-07 | PASS — fixture parser | S2 main totals are used; batch values are not emitted as extra rows. |
| FC-08 | NOT IMPLEMENTED | S3 Picking List source parser/fixture not present. |
| FC-09 | NOT IMPLEMENTED | S3 Picking List source parser/fixture not present. |
| FC-10 | NOT IMPLEMENTED | Separate S3 deliveries are not supported by a Picking List profile. |
| FC-11 | NOT IMPLEMENTED | Pending mapping remains blocked, but source-review/draft display for Picking Lists is absent. |
| FC-12 | PASS — parser test only | Consolidation order is independent of input order; controller identity flow lacks integration coverage. |
| FC-13 | PASS — domain test | Out-of-range page and conflicting page total block final local submission. |
| FC-14 | NOT IMPLEMENTED | Field-level blur repair/crop retry is absent. |
| FC-15 | NOT RUN | No physical image set isolates irrelevant blur/stamps. |
| FC-16 | NOT RUN | No live image-dimension/downscaling comparison was captured. |
| FC-17 | NOT IMPLEMENTED | Tap-to-fill coordinate mapping is absent. |
| FC-18 | NOT IMPLEMENTED | Operator-selected OCR token path is absent. |
| FC-19 | NOT IMPLEMENTED | Explicit batch-vs-main selection warning is absent. |
| FC-20 | NOT IMPLEMENTED | Supplementary close-up capture is absent. |
| FC-21 | NOT IMPLEMENTED | Linked article/quantity close-up confirmation is absent. |
| FC-22 | PASS — parser/correction tests | Missing required quantity remains unresolved rather than becoming zero; a source-entered correction resolves only its exact occurrence and preserves the raw OCR miss. |
| FC-23 | PARTIAL | Source correction UI, raw OCR, and audit records exist; controller UI flow was not integration-tested. |
| FC-24 | PASS — domain test | Document quantity 8 and physical quantity 6 stay separate; variance is −2. No stock was counted. |
| FC-25 | PARTIAL | Code preserves physical value after document correction; no controller persistence integration test. |
| FC-26 | PARTIAL | Active capture/revision guard exists; delayed OCR race was not executed. |
| FC-27 | PARTIAL | “Add missing item” and re-review are implemented; no UI/controller integration test. |
| FC-28 | PASS — fixture parser | Quantity-less headings are context; unreadable required quantities stay unresolved. |
| FC-29 | PASS — domain test | Optional unreadable Piece does not block; mismatch requires review acknowledgment and does not modify lines. |
| FC-30 | NOT RUN | Wrong-row substitution with same aggregate has no explicit regression fixture. |
| FC-31 | PARTIAL | Identifiers are strings; no dedicated leading-zero/eight-digit boundary test. |
| FC-32 | PASS — domain test | Local finalization blocks unconfirmed physical counts. |
| FC-33 | NOT RUN | Process-death/page-review recovery test was not executed. |
| FC-34 | NOT RUN | Fresh install and cold offline startup require Android hardware. |
| FC-35 | PARTIAL | Local snapshot uses a unique session submission and repository transaction; failure/repeated-tap integration test absent. |
| FC-36 | PARTIAL | Mismatched page is held for explicit identity review; no controller integration test. |
| FC-37 | PASS — fixture parser | Distinct S2 occurrences are retained, including repeated article number. |
| FC-38 | NOT RUN | No Android recognizer was run; fixture/parser tests are not reported as OCR success. |
| FC-39 | PASS — domain test | Verified identity can be manually supplied when OCR identity is null; raw observed value remains null. |
| FC-40 | NOT RUN | The focused change contains no upload path, but host telemetry/egress was not audited end-to-end. |

## Screenshots and device evidence

No app UI screenshots are included. Only Linux and Chrome were available, and neither can validate this Android camera/OCR feature. Existing `renders/page-*.png` are PDF reference renders, not application screenshots. Do not treat them as device evidence.

The optional Google Play services document-scanner flow compiled into the APK but was not run on a device. Its scanner UI and processing components are downloaded dynamically and may need connectivity on first use; the app's local camera and enhancement path remains available as a fallback.
