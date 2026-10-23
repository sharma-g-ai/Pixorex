# Accuracy report

## Recognition metrics

**Automatic OCR accuracy: NOT MEASURED.** There were zero physical-page or PDF-render recognizer runs on Android in this environment. No numerator/denominator is available for automatic article recall, main-quantity recall, pair precision/recall, automatic coverage, association errors, or device-level correction burden. Do not interpret the Flutter build as an OCR run.

## What did run

| Evidence | Result | Interpretation |
|---|---|---|
| S1, four-page PPG note | Parser tests preserve 7 manually transcribed article/quantity occurrences and 62 PC | Synthetic OCR elements start from the correct source tokens. This tests parser semantics, not recognition. |
| S2, six-page PPG note | Parser tests preserve 14 manually transcribed occurrences, 13 distinct identifiers, and 100 PC | Repeated `475210` occurrences remain separate. This tests parser semantics, not recognition. |
| Piece summary | Missing optional value is accepted; readable mismatch requires an audited acknowledgment | Rows are not edited or balanced to match the summary. |
| Android debug build | Compiles | Does not exercise ML Kit or camera hardware. |

The supplied proposal's physical pilot targets (99% provisional pair precision and 98% pair recall) remain proposals, not achieved results. There is no held-out physical-paper evaluation and no Google Lens comparison.

## Missing pilot evidence

- Intended device models, Android versions, camera settings, lighting and paper conditions.
- Native OCR outputs from original and rectified images, including input dimensions and elapsed time.
- Additional unseen logical delivery notes split by document/profile rather than random crops.
- Independently checked article–main-quantity–unit occurrence ground truth.
- Automatic outputs before any human selection/correction, plus repair and recapture counts.
- Per-profile/per-device precision, recall, automatic coverage, association/missing/extra-row rates, and p50/p95 latency.
- Cold offline startup, first-use model availability, physical capture, and local submission evidence.

## Claim boundary

The validated claim is limited to deterministic parsing/domain behavior on supplied synthetic word boxes and successful APK compilation. No claim is made about recognition accuracy, camera reliability, field usability, or physical-stock correctness.
