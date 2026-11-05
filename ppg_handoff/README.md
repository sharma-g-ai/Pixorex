# PPG Delivery Note Codex Handoff (local package)

Self-contained reference package for the offline PPG delivery-note scanner feature.

Current implementation and validation status are documented in `IMPLEMENTATION_REPORT.md`. The field-first proposal is only partially implemented; do not treat parser fixtures as OCR accuracy evidence.

## Contents

- `PPG_DELIVERY_NOTE_HANDOFF.md` — requirements and design
- `CODEX_START_PROMPT.md` — implementation instruction
- `source/DN_5319364114.pdf` — reference delivery note
- `renders/page-1.png` … `page-4.png` — rendered pages
- `fixtures/dn_5319364114.expected.json` — golden article/quantity oracle
- `contracts/local_submission.schema.json` — local submit contract
- `examples/local_submission_with_variance.json` — illustrative only
- `OCR_FAILURE_ANALYSIS.md` — inspected OCR/image path and reported DN mismatch
- `PAGE_PROFILE_CONTRACTS.md` — confirmed PPG profile and pending Picking List mapping
- `TEST_RESULTS.md` — focused test output and FC-01–FC-40 status
- `ACCURACY_REPORT.md` — separates parser tests from unmeasured live OCR
- `CAPTURE_AND_FIELD_TRACE.json` — successful synthetic path and reported mismatch trace
- `BUILD_INSTRUCTIONS.md` — reproducible checks and device-test steps
- `REVIEW_BUNDLE_MANIFEST.sha256` — hashes for the packaged review files

## Validate package

```bash
python3 tools/validate_handoff.py
```

This checks package integrity only. It does **not** prove OCR or camera success.
