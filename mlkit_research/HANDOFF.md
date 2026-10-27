# MLKit research spike – handoff

Status as of 26 Oct 2026. Everything below is on disk in this folder or in the Pixel X frontend;
nothing depends on a Claude account.

## Task
Research spike from the sprint meeting: find how far MLKit can be tuned for delivery-note
scanning (latency and accuracy). Owner: Divya Amrutha Yalla. Reviewer: Geetashish Sharma.
Not in scope: comparing with PaddleOCR (Iswarya's spike).

## Done
| Step | Result | Where |
|---|---|---|
| 1. Test set | 10 real page photos (2 PPG delivery notes) + 40 simulated (shadow, glare, crumpled, low light) | `test_images/`, `test_set_manifest.csv`, `tools/make_variants.py` |
| Answer key | 27 item rows + 2 header pages, verified on zoomed photos, all EAN-13 check digits valid | `ground_truth_line_items.csv`, `ground_truth_headers.csv` |
| 2. Baseline | 39/50 pages fully correct, 83.3% fields, 740 ms/page | `results/baseline/FINDINGS.md` |
| 3. What MLKit lets us control | Script, bundled vs unbundled model, input image, doc-scanner modes; no thresholds/ROI/custom models. Licence = ML Kit Terms of Service, **not** Apache 2.0 | in the findings doc |
| 4–5. Experiments | 8 settings tested; 2× resolution + no symbols + text fixes best | `results/experiments/FINDINGS.md`, `comparison.csv` |
| 6. Final run | 46/50 pages fully correct, 91.7% fields, 724 ms/page | `results/final/` |
| 7. Write-up | Findings doc for Geetashish | `MLKit_Research_Spike_PPG_Delivery_Note_Scanning.docx` / `.pdf` |

Online doc (Amrutha's account, amruth.yalla@amzur.com):
https://claude.ai/artifact/WHrauXycPQe9L5XxWRn9EU
Earlier copy in Vishnu's account: https://claude.ai/artifact/ErErQXmgXM4aDauV9mr3XD

## Code changes (not committed):
- `Pixorex/frontend/android/app/src/main/kotlin/com/amzur/equiptrack/ppg/PpgOcrPlugin.kt`
  - result now includes `decodeMs`, `ocrMs`, `packMs`
  - new optional argument `includeSymbols` (default `true`, so app behaviour is unchanged)
- `Pixorex/frontend/tool/mlkit_benchmark.dart` – new benchmark entry point
  (`flutter build apk --debug -t tool/mlkit_benchmark.dart`); not part of the normal app.

## Phone
Realme RMX3710 (`adb` id `9PEMYXEUS4LBFEEY`). Pixorex v1.0.5 was uninstalled; the debug
benchmark build is installed instead. Reinstall the v1.0.5 APK to get the real app back.

## Still open
- [x] Full-resolution speed test and document-scanner test – see `results/FOLLOWUP_FINDINGS.md`.
- [ ] Capture a whole 6-page note in one scanner pass (every scan so far returned one page).
  Test screen: `flutter build apk --debug -t tool/doc_scanner_benchmark.dart`.
- [ ] `MainActivity.kt` has a new `scanDocumentPages` method (mode + page limit, returns all
  pages); the existing `scanDocument` is unchanged.
- [ ] Confirm MLKit's terms suit PPG's commercial use.
- [ ] Share the findings with Geetashish.

## Recreating the findings doc in another Claude account
After signing in to the new account, start Claude Code in `D:\users\AmruthaY\projects\pixorex` and paste:

> Read mlkit_research/HANDOFF.md. Then create a Claude doc titled
> "MLKit Research Spike – PPG Delivery Note Scanning" from
> mlkit_research/MLKit_Research_Spike_PPG_Delivery_Note_Scanning.docx, keeping every section,
> table and the results chart (rebuild the chart from results/final/per_image.csv and
> results/baseline/per_image.csv: pages fully correct per condition, today vs recommended),
> with me as the author.
