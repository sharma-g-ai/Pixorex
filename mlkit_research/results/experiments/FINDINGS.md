# MLKit tuning experiments – findings (Sections 4–5)

**Setup:** same phone (Realme RMX3710, Helio G85, Android 14), same MLKit model and settings as the
baseline. Only the input image (or the post-OCR text) changes. 8 image sets × 50 images × 3 runs,
run 26 Oct 2026. The baseline set reproduced the Section 2 numbers exactly (39/50, 83.3%).
`+fix` = print-format text corrections applied after OCR (`tools/score.py --fix`).

## Results

| Set | Pages usable | Field recall | Article recall | Low light: usable / article | p50 latency |
|---|---|---|---|---|---|
| Baseline | 39/50 | 83.3% | 96.3% | 4/10 · 81.5% | 740 ms |
| Baseline + fix | 39/50 | 88.9% | 96.3% | 4/10 · 81.5% | 740 ms |
| Baseline, no symbols | 39/50 | 83.3% | 96.3% | 4/10 · 81.5% | **548 ms** |
| CLAHE contrast | 42/50 | 82.3% | 96.3% | 7/10 · 85.2% | 718 ms |
| Binarize | 26/50 | 58.5% | 72.6% | 2/10 · 7.4% | 730 ms |
| Denoise + CLAHE | 32/50 | 67.8% | 92.6% | 3/10 · 77.8% | 731 ms |
| Upscale 1.5× + fix | 42/50 | 91.1% | 97.0% | 4/10 · 85.2% | 850 ms |
| CLAHE + upscale 1.5× + fix | 41/50 | 88.3% | 97.0% | 5/10 · 85.2% | 873 ms |
| **Upscale 2× + fix** | **46/50** | **91.7%** | **98.5%** | **9/10 · 92.6%** | 923 ms |

Latency is with symbol geometry on (as the app runs today); turning it off saves ~190 ms in every set.

## What we learned

1. **Resolution is the biggest lever.** Feeding MLKit a 2400×3200 image instead of 1200×1600 took
   usable pages from 78% → 92% and low-light pages from 4 → 9 of 10, for +180 ms. The source photos
   are too small for this print size (MLKit wants ≥16 px per character). Real 12 MP camera output
   is already larger than 2400 px, so the rule is **never downscale below ~2400 px on the long side**
   before OCR, rather than "upscale".
2. **Skipping symbol geometry saves ~190 ms per page (−26%) with no accuracy change.** The plugin
   builds per-character boxes through Java reflection; nothing in the scan flow needs them per page.
3. **Print-format text fixes are free accuracy:** +5.6 points field recall. `1D`→`ID` in material
   numbers and `I`/`|`→`/` in page markers, both derived from the fixed PPG layout.
4. **Contrast boost (CLAHE) helps low light only** (4 → 7 usable) and slightly hurts everything else;
   combined with upscaling it is worse than upscaling alone. Not recommended as a default.
5. **Binarization and denoise+CLAHE hurt badly** – MLKit's own model does better on the natural
   image. Do not add them.

## What still fails (best set: upscale 2× + fix, 4 pages)

- **Wrong-but-valid values in low light:** article `475212` → `475211` (a *different real article on
  the same page*), `446789` → `448789`, quantity `5 PC` → `6 PC`.
- **`RED / SIGMA 6 8 PC` → `68 PC`** on one image.
- **DN number cut at the box border:** `5319364114` → `53193641` (2 images).

These cannot be tuned away inside MLKit. They need **validation after OCR**, which the PPG data supports well:

| Check | Catches |
|---|---|
| qty × volume/unit = total volume (e.g. 6 × 16 L ≠ 80 L) | wrong quantities, `68 PC` trap |
| Sum of line quantities = page-1 "Piece" total | any missed or wrong quantity |
| Batch quantities sum to the line quantity | wrong quantities |
| DN number is 10 digits and identical on every page | truncated DN |
| EAN-13 check digit + EAN ↔ article pairing from master list | wrong-but-valid article numbers |
| Read the DN **barcode** on page 1 (MLKit Barcode Scanning) | DN errors entirely |

## Recommended configuration

1. Keep MLKit Text Recognition v2, bundled Latin model (no change).
2. Do not downscale captures below ~2400 px long side before `recognize`.
3. Skip symbol geometry in `PpgOcrPlugin` for full-page OCR (`includeSymbols: false`).
4. Apply the print-format text fixes before parsing.
5. Add the cross-checks above; flag failing lines for user review instead of failing the note.
6. Warm up the recognizer at app start (cold start measured at 3.8 s).

Expected: ~92% of pages fully correct before validation, with the remaining errors caught by
cross-checks; ~730 ms OCR per page at 2400 px without symbols → ~4.5 s OCR for a 6-page note.

## Caveats

- 40 of 50 images are simulated conditions; preprocessing cost was measured on the PC, not the phone.
- "Upscale 2×" approximates a higher-resolution capture; confirm with phone-original 12 MP photos.
- Field recall is OCR-level; the app parser was not part of this test.

## Files

- `comparison.csv` – the table above with decode / OCR / pack timings
- `<set>/` and `<set>+fix/` – per-image results and misreads for every set
- `../experiments_raw/` – raw MLKit output; `../../tools/preprocess.py` builds the image sets
