# Follow-up tests – full-resolution photos and the document scanner

Run 26 Oct 2026 on the Realme RMX3710 (Helio G85, Android 14), MLKit Text Recognition v2 16.0.1.
Scoring as in the earlier tests (`tools/score.py --fix`): a page is fully correct when its DN
number, every article and every quantity are read exactly.

## 1. Full-resolution phone photos (10 pages, 16 MP originals from the phone's SD card)

| Pipeline | Pages fully correct | Fields | Median time per page |
|---|---|---|---|
| App today: full 16 MP, symbols on | 9/10 | 97.7% | 1,269 ms (decode 248, OCR 765, pack 223) |
| Full 16 MP, symbols off | 9/10 | 97.7% | 1,005 ms |
| Upright (EXIF applied), full size, symbols off | 8/10 | 97.3% | 847 ms |
| **Recommended: upright, 2400 px, symbols off** | 8/10 | **98.5%** | **678 ms** |

- Real camera photos are slower than the compressed test copies suggested: 1.27 s per page in
  today's app. The recommended pipeline cuts that by 47% with the same accuracy.
- The 2× upscale in the earlier experiments was a fair stand-in: full-resolution accuracy matches it.
- DN1 page 1 is stored sideways (EXIF orientation 6) and the app ignores the flag, but MLKit
  detected the rotated text and read it (90% either way). Applying the orientation still saves
  decode time.
- Remaining failures are the known ones: DN number cut at the box border, and `68 PC`.

## 2. MLKit document scanner (both notes, all three modes, 30 pages)

| Mode | Pages fully correct | Fields | Articles | Quantities | Median scan time per page | DN1 (6 pages) total | DN2 (4 pages) total |
|---|---|---|---|---|---|---|---|
| BASE | 9/10 | 97.3% | 100% | 95.2% | 9.6 s | 59 s | 52 s |
| BASE_WITH_FILTER | 8/10 | 95.8% | 100% | 100% | 6.8 s | 44 s | 57 s |
| FULL (app today) | 9/10 | 96.9% | 100% | 100% | 8.1 s | 54 s | 66 s |

Totals include the person's handling time and the OCR of every page.

- **A whole note fits the 1–2 minute target in every mode:** 44–66 s for 4–6 pages.
- **Scanned pages read as well as photos** (96–97% of fields vs 98.5%), and every article number
  was read correctly in every mode. The scanner returns pages at about 2,100 × 2,800 px, already in
  the recommended range, so no resizing is needed.
- **No mode is clearly better** on 10 pages; the differences are within one or two pages. Keep FULL,
  which the app already uses.
- **Failures:** DN number with its last `0` read as `O` or `D` at the box border (3 pages) and the
  `68 PC` trap (1 page) – both caught by the planned cross-checks.
- **Auto-crop can take two pages at once:** in an earlier run, scanning page 4 on top of the stack
  returned page 4 with page 2's header above it, showing both "Page : 2 / 4" and "Page : 4 / 4".
  Pages should be scanned laid flat on their own, and page identity should not rely on the
  printed page number alone.
- **Not yet answered:** whether 6 pages can be captured in one pass. Every scan returned one page;
  the page limit above 1 works (one earlier scan returned 2 pages), but a full one-pass note was
  not captured.

## Files
- `fullres_originals/` – the 10 phone originals; `fullres_sets/` – the four pipelines
- `results/fullres/` – scores; `results/fullres_raw/` – raw MLKit output
- `results/scanner_<mode>/` – scores; `results/scanner_onepass_raw/` – scanned pages + raw output + scan timings
- `Pixorex/frontend/tool/doc_scanner_benchmark.dart` – the scanner test screen
