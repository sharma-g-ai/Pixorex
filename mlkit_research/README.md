# MLKit research – test set

## What's here
- `test_images/` – 50 images: 10 real pages × 5 conditions.
- `test_set_manifest.csv` – every image with its DN, page, condition and source.
- `ground_truth_headers.csv` – correct header values per page (join on DN + page).
- `ground_truth_line_items.csv` – correct values for every article row.
- `tools/make_variants.py` – regenerates the 40 simulated images from the 10 real ones.
- `tools/score.py` – scores MLKit output against the ground truth.
- `results/baseline/FINDINGS.md` – Section 2 results (MLKit out of the box).
- `tools/preprocess.py` – builds the experiment image sets (contrast, binarize, upscale…).
- `results/experiments/FINDINGS.md` – Sections 4–5 results and the recommended configuration.

## Running the benchmark on a phone
1. `cd Pixorex/frontend && flutter build apk --debug -t tool/mlkit_benchmark.dart`
2. `adb install -r build/app/outputs/flutter-apk/app-debug.apk`
3. `adb push mlkit_research/test_images/. /sdcard/Android/data/com.amzur.equiptrack/files/mlkit_bench/images/`
4. Open the app; wait for `MLKIT_BENCH_DONE` in `adb logcat -s flutter`.
5. `adb pull /sdcard/Android/data/com.amzur.equiptrack/files/mlkit_bench/results/. results/<name>_raw`
6. `py -I tools/score.py results/<name>_raw results/<name>`

## How the 50 images were made
- `*_normal.jpg` (10) are real phone photos of the printed notes.
- `*_shadow`, `*_glare`, `*_crumpled`, `*_low_light` (40) are made from those photos with code
  (`py -I tools/make_variants.py test_images`). Only lighting and geometry change – the printed
  text is untouched, so one answer key works for all 5 versions of a page.
- Each variant uses a fixed random seed, so rerunning the script gives identical images.

| Condition | Simulation |
|---|---|
| shadow | Soft hand/phone shaped shadow, 45–60% darker |
| glare | Bright hot spot over the item table plus a faint overhead sheen |
| crumpled | 4–6 soft folds with shading; text bends slightly along each fold |
| low_light | Darkened ~2×, warm tint, sensor noise, slight blur, JPEG q75 |

## Real photo traits (present in all 5 versions of the page)
- DN1 p1 – slight tilt, round stamp + signature over the T&C.
- DN2 p1 – photo is rotated 90° in the pixels (no EXIF flag) – tests rotation handling.
- DN2 p2 – perspective skew, mirrored bleed-through text at the bottom.

## Naming
`DN<n>_<delivery note no>_p<page>_<condition>.jpg`

## Answer-key notes
- `row_type=set` rows are set headers (no quantity); `line` rows carry the quantity to count.
- `batches` format: `batch|date of manufacture|qty`, separated by `; `.
- Cross-checks pass: DN1 line quantities sum to 100 PC / 900 L, DN2 to 62 PC / 560 L, matching page 1 totals.
- Vessel IDs are `LO0` + IMO number; DN1's `LO09632492` is confirmed by the "IMO NO. 9632492" ship stamp on page 1.
- Every value was re-verified on zoomed crops of the real photos, and all 27 EAN-13 check digits validate.

## OCR traps
- Colour code runs into quantity: `RED / SIGMA 6 8 PC`, `SIGMA BLUE 1 8 PC` (true qty is 8).
- `0000TRID2200` appears for two different thinners; `000000ID1400` appears on 3 pages.
- Items continue across page breaks (items 20, 30, 60).
- Faint print: item 91's weight `85.568 KG` shows the first `8` almost like `ε`.
- DN2 p2 has upside-down bleed-through from the next page under the table (`30.09.2026`, `Port of Colombo`).

## Limitations (state these in the findings)
- 40 of 50 images are simulated, not photographed. Results for those conditions are an estimate
  of real-world behaviour, not a measurement of it.
- Source photos are 1200×1600 with EXIF stripped (compressed in transfer). Latency numbers will be
  lower than on full-resolution camera output (typically 3000×4000).
- The AI-generated images in Downloads (`watermarked_img_*`) were **not used**: Gemini altered
  printed numbers (EANs, batches, dates, article codes), so they don't match the answer key.
