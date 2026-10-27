"""Score MLKit benchmark output against the ground truth.

Usage:  py -I tools/score.py <results dir> <output dir> [--fix]

--fix applies the print-format corrections in FIXES before scoring.

Scoring is at OCR level (did MLKit read the printed text correctly?), not
parser level. Matching is strict: no O/0 or I/1 substitutions are forgiven,
because a single wrong character breaks an article lookup.
"""
import csv
import difflib
import json
import re
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONDITIONS = ["normal", "shadow", "glare", "crumpled", "low_light"]


def load_expected():
    """Expected (field, value) pairs per (dn, page)."""
    expected = defaultdict(list)
    with open(ROOT / "ground_truth_headers.csv", encoding="utf-8-sig") as f:
        for h in csv.DictReader(f):
            key = (h["dn_number"], h["page"])
            expected[key].append(("dn_number", h["dn_number"]))
            expected[key].append(("page_marker", f"{h['page']} / {h['page_total']}"))
            expected[key].append(("delivery_date", h["delivery_date"]))
            if h["pieces"]:
                expected[key] += [
                    ("order_no", h["order_no"]),
                    ("dispatch_date", h["dispatch_date"]),
                    ("vessel_id", h["vessel"].split("-")[0]),
                    ("your_ref", h["your_ref"]),
                    ("total_volume", f"{h['total_volume_l']} L"),
                    ("net_weight", f"{float(h['total_net_weight_kg']):,.3f} KG"),
                    ("gross_weight", f"{float(h['total_gross_weight_kg']):,.3f} KG"),
                ]
    with open(ROOT / "ground_truth_line_items.csv", encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            key = (r["dn_number"], r["page"])
            expected[key] += [
                ("material_number", r["material_number"]),
                ("article_alt_prod_no", r["alt_prod_no"]),
                ("ean", r["ean"].split(" /")[0]),
            ]
            if r["row_type"] != "line":
                continue
            expected[key] += [
                ("total_qty", f"{r['total_qty_pc']} PC"),
                ("total_volume", f"{r['total_volume_l']} L"),
                ("gross_weight", f"{r['gross_weight_kg']} KG"),
            ]
            for batch in r["batches"].split("; "):
                number, date, qty = batch.split("|")
                expected[key] += [
                    ("batch_number", number),
                    ("batch_date", date),
                    ("batch_qty", f"{qty} PC"),
                ]
    return expected


def pattern(value: str) -> re.Pattern:
    # Spaces in the printed value may be read as zero or more spaces; the
    # value must not be glued to other letters or digits on either side.
    body = r"\s*".join(re.escape(part) for part in value.split())
    body = body.replace(r"\ /\ ", r"\s*/\s*").replace(r"/", r"\s*/\s*")
    return re.compile(rf"(?<![A-Z0-9.,]){body}(?![A-Z0-9])")


def page_text(output) -> str:
    return "\n".join(" ".join(l["text"].upper().split()) for l in output.get("lines", []))


def closest(value, text):
    words = text.replace("\n", " ").split(" ")
    span = len(value.split())
    grams = {" ".join(words[i:i + span]) for i in range(len(words))}
    best = difflib.get_close_matches(value, grams, n=1, cutoff=0.5)
    return best[0] if best else ""


# Corrections based on the fixed PPG print format, not on individual misreads:
# material numbers are 6 characters + ID + 4 digits, page markers are "n / m".
FIXES = [
    (re.compile(r"\b(\d{6})(?:1D|D|lD|\|D)(\d{4})\b"), r"\1ID\2"),
    (re.compile(r"(PAGE\s*:?\s*\d+)\s*[I|L]\s*(\d+)"), r"\1 / \2"),
]


def apply_fixes(text: str) -> str:
    for rx, repl in FIXES:
        text = rx.sub(repl, text)
    return text


def meta_from_name(name: str) -> dict:
    # Images outside the 50-image manifest follow DN<n>_<dn>_p<page>_<condition>.jpg.
    m = re.fullmatch(r"DN\d_(\d{10})_p(\d+)_(.+)\.jpg", name)
    if not m:
        sys.exit(f"cannot tell DN/page from {name}")
    return {"dn_number": m.group(1), "page": m.group(2), "condition": m.group(3)}


def pct(n, d):
    return round(100 * n / d, 1) if d else 0.0


def main(results_dir: Path, out_dir: Path, fix: bool = False):
    out_dir.mkdir(parents=True, exist_ok=True)
    expected = load_expected()
    manifest = {r["image_file"]: r for r in csv.DictReader(open(ROOT / "test_set_manifest.csv", encoding="utf-8-sig"))}
    summary = json.loads((results_dir / "_summary.json").read_text(encoding="utf-8-sig"))

    image_rows, miss_rows = [], []
    field_stats = defaultdict(lambda: Counter())
    for path in sorted(results_dir.glob("DN*.json")):
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        meta = manifest.get(data["image"]) or meta_from_name(data["image"])
        text = page_text(data["output"])
        if fix:
            text = apply_fixes(text)
        want = Counter(expected[(meta["dn_number"], meta["page"])])
        found = Counter()
        for (field, value), count in want.items():
            hits = len(pattern(value.upper()).findall(text))
            found[(field, value)] = min(hits, count)
            field_stats[(meta["condition"], field)]["expected"] += count
            field_stats[(meta["condition"], field)]["found"] += min(hits, count)
            if hits < count:
                miss_rows.append({
                    "image": data["image"], "condition": meta["condition"], "field": field,
                    "expected": value, "closest_ocr_text": closest(value.upper(), text),
                })

        def recall(field):
            n = sum(c for (f, _), c in want.items() if f == field)
            return sum(c for (f, _), c in found.items() if f == field), n

        art_f, art_n = recall("article_alt_prod_no")
        qty_f, qty_n = recall("total_qty")
        dn_f, _ = recall("dn_number")
        total_f, total_n = sum(found.values()), sum(want.values())
        runs = data["runs"]
        image_rows.append({
            "image": data["image"], "condition": meta["condition"],
            "fields_found": total_f, "fields_expected": total_n,
            "field_recall_pct": pct(total_f, total_n),
            "articles_found": f"{art_f}/{art_n}", "qty_found": f"{qty_f}/{qty_n}",
            "dn_found": bool(dn_f),
            # A page is usable only if DN, every article and every quantity were read.
            "page_usable": bool(dn_f) and art_f == art_n and qty_f == qty_n,
            "median_round_trip_ms": statistics.median(r["roundTripMs"] for r in runs),
            "median_decode_ms": statistics.median(r["decodeMs"] for r in runs),
            "median_ocr_ms": statistics.median(r["ocrMs"] for r in runs),
            "ocr_lines": len(data["output"].get("lines", [])),
        })

    def write(name, rows):
        with open(out_dir / name, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)

    write("per_image.csv", image_rows)
    if miss_rows:
        write("misreads.csv", miss_rows)

    fields = sorted({f for _, f in field_stats})
    by_field = [{"field": f, **{c: pct(field_stats[(c, f)]["found"], field_stats[(c, f)]["expected"]) for c in CONDITIONS}}
                for f in fields]
    write("recall_by_field.csv", by_field)

    lines = ["# MLKit baseline results", "",
             f"- Device: {summary['device']}",
             f"- Cold start (first call, model load): {summary['coldStartMs']} ms",
             f"- Runs per image: {summary['runsPerImage']} (latency = median)", "",
             "| Condition | Images | Pages usable | Field recall | Article recall | Qty recall | p50 total ms | p90 total ms | p50 OCR ms |",
             "|---|---|---|---|---|---|---|---|---|"]
    for cond in CONDITIONS + ["ALL"]:
        rows = [r for r in image_rows if cond == "ALL" or r["condition"] == cond]
        if not rows:
            continue
        af = sum(int(r["articles_found"].split("/")[0]) for r in rows)
        an = sum(int(r["articles_found"].split("/")[1]) for r in rows)
        qf = sum(int(r["qty_found"].split("/")[0]) for r in rows)
        qn = sum(int(r["qty_found"].split("/")[1]) for r in rows)
        rt = sorted(r["median_round_trip_ms"] for r in rows)
        p90 = rt[min(len(rt) - 1, int(round(0.9 * (len(rt) - 1))))]
        lines.append(
            f"| {cond} | {len(rows)} | {sum(r['page_usable'] for r in rows)}/{len(rows)} "
            f"| {pct(sum(r['fields_found'] for r in rows), sum(r['fields_expected'] for r in rows))}% "
            f"| {pct(af, an)}% | {pct(qf, qn)}% | {statistics.median(rt):.0f} | {p90:.0f} "
            f"| {statistics.median(r['median_ocr_ms'] for r in rows):.0f} |")
    lines += ["", "Page usable = delivery note number, every article (alt prod no) and every total quantity read exactly.",
              "Pages with no item rows (both page 1s) count as usable when the DN number is read."]
    (out_dir / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]), fix="--fix" in sys.argv[3:])
