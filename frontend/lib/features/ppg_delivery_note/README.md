# PPG Delivery Note feature (Flutter)

Isolated offline module inside Pixorex. Entry: Home → truck icon.

## Run

```bash
cd frontend
flutter pub get
flutter run   # Android device/emulator
```

Developer path without camera OCR (debug builds only): Hub overflow menu → **Load reference fixture**.

## Receiving workflow

The revised **DN-scoped can-counting screen specification** is in
[PPG Sea Stock receiving workflow](../../../../documents/PPG_SEASTOCK_RECEIVING_WORKFLOW.md).
Its clickable landing, document summary, can scanner, count list, and final
summary are in [receiving wireframes](../../../../output/seastock-receiving-wireframes.html).
The preview simulates camera observations. It requires DN finalisation, an
exact match to a quantity-bearing article in the current DN, and deliberate
one-can acceptance; it also covers repeated rows and unexpected articles.
Build 36 adds live can scanning to the Android app. On **Receiving list**, tap
the scanner icon or **Scan can article number**; each row also offers
**Scan this article**. Complete the DN source checks first. Three fresh OCR
frames must agree on the printed Article field. Leading zeros are preserved,
and only an exact article match in this DN counts the can. Since 14 Oct 2026
a confirmed read adds one can automatically (as on the Seastock check-out and
audit scanners); the camera then waits for **Scan next can**, a − / number / +
counter fixes the row's count, and **Wrong can? Undo** takes the one back.
Repeated article rows require explicit allocation: choosing the DN line counts
the can. A row-specific scan must
match that selected row. Unknown, conflicting, clipped, and low-confidence
reads do not enable counting.

The camera uses bundled ML Kit on NV21 stream frames, with bounded analysis,
sensor/device rotation compensation, later-frame orientation retries, coarse
motion/exposure rejection, and camera lifecycle cleanup. No cloud OCR is used.
One accepted can is saved with its audit event in the existing SQLite
transaction. Event IDs prevent a successful retry from adding twice. Move the
can aside and tap **Scan next can** to re-arm. Existing manual tools below are
still available. Scanned quantities do not automatically finish a receiving row.

This build uses the existing completed-source-review gate; separate document
finalisation records and the wireframe's unexpected-article review ledger are
future extensions. The live camera path needs real-can/device validation;
automated parser, count, and UI checks do not establish physical OCR accuracy.

Scan all DN pages in any order, then use the page checklist to verify delivery
identity, printed article/quantity values, and full-page coverage. Page review
confirms the paper only; it does not confirm physical stock.

Open the receiving list after the source checks are complete. Search an article
and choose **Matches DN** after physically checking it, **Start count** to count
from zero, or **Set counted total** to enter a known total. During counting,
use +1/−1, **Add batch**, or tap/long press the number to set the total.
Each change is saved locally. **Finish count** verifies the item and asks for a
reason when its count differs from the DN. **Reopen count** retains the total
when another batch arrives. Repeated article occurrences remain separate.

DN corrections preserve entered physical totals and require rechecking. An
article correction also requires explicitly reconciling the existing count.
Once a page has physical counts, use these DN corrections; replacing or
re-running OCR on that page is blocked to prevent losing the counts.
The final review lists variances and reasons; submission requires every source
page and physical count to be verified. Submitted forms are read-only.

Database version 9 migrates confirmed legacy counts to Verified, entered drafts
to Counting, and untouched DN defaults to To check. Submitted snapshots are
left unchanged. Count changes, their audit actions, and review invalidation
are committed in one SQLite transaction.

## Tests

```bash
cd frontend
flutter test test/ppg_delivery_note/
```

```bash
python3 ../ppg_handoff/tools/validate_handoff.py
```

## Scope reminder

Submit creates `SUBMITTED_LOCAL` only. No OpenAI, Supabase, or Sheets calls from this feature.
