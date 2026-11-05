#!/usr/bin/env python3
"""Validate PPG delivery-note handoff package integrity (not OCR success)."""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    errors: list[str] = []
    expected_path = ROOT / "fixtures" / "dn_5319364114.expected.json"
    pdf_path = ROOT / "source" / "DN_5319364114.pdf"
    schema_path = ROOT / "contracts" / "local_submission.schema.json"
    example_path = ROOT / "examples" / "local_submission_with_variance.json"

    for p in (expected_path, pdf_path, schema_path, example_path):
        if not p.exists():
            errors.append(f"missing: {p.relative_to(ROOT)}")

    if expected_path.exists() and pdf_path.exists():
        expected = json.loads(expected_path.read_text())
        actual = sha256_file(pdf_path)
        recorded = expected.get("source_sha256")
        if recorded and recorded != actual:
            errors.append(
                f"source hash mismatch: fixture={recorded} actual={actual}"
            )
        rows = expected.get("quantity_bearing_rows", [])
        if len(rows) != 7:
            errors.append(f"expected 7 quantity rows, got {len(rows)}")
        total = sum(int(r["document_quantity"]) for r in rows)
        if total != 62:
            errors.append(f"quantity sum expected 62, got {total}")
        headers = expected.get("set_headers_no_printed_quantity", [])
        if len(headers) != 2:
            errors.append(f"expected 2 set headers, got {len(headers)}")
        for h in headers:
            if h.get("document_quantity") is not None:
                errors.append(
                    f"set header {h.get('article_number')} must have null quantity"
                )

    six_page_fixture = ROOT / "fixtures" / "dn_5319358250.expected.json"
    six_page_pdf = ROOT / "source" / "DN_5319358250.pdf"
    for p in (six_page_fixture, six_page_pdf):
        if not p.exists():
            errors.append(f"missing: {p.relative_to(ROOT)}")
    if six_page_fixture.exists() and six_page_pdf.exists():
        six = json.loads(six_page_fixture.read_text())
        if sha256_file(six_page_pdf) != six.get("sha256"):
            errors.append("six-page source hash mismatch")
        rows = six.get("quantity_bearing_occurrences", [])
        headings = six.get("quantity_less_headings", [])
        if len(rows) != 14 or len({r["article_number"] for r in rows}) != 13:
            errors.append("six-page occurrence or distinct-identifier count mismatch")
        if sum(r["total_qty"] for r in rows) != six.get("page_1_piece_summary"):
            errors.append("six-page row sum differs from printed Piece summary")
        if len(headings) != 4:
            errors.append("six-page quantity-less heading count mismatch")
        repeated = [r for r in rows if r["article_number"] == "475210"]
        if [(r["page"], r["total_qty"]) for r in repeated] != [(3, 15), (4, 5)]:
            errors.append("repeat article occurrences were not preserved")

    if schema_path.exists():
        schema = json.loads(schema_path.read_text())
        line_schema = schema["properties"]["lines"]["items"]
        page_schema = schema["properties"]["page_captures"]["items"]
        if "physical_quantity_confirmed" not in line_schema["required"]:
            errors.append("local submission line must require physical confirmation")
        if line_schema["properties"].get("physical_quantity_confirmed", {}).get(
            "const"
        ) is not True:
            errors.append("physical confirmation must be true in a final snapshot")
        if "verified_delivery_note_number" not in page_schema["required"]:
            errors.append("local submission page must require verified delivery identity")
        if "page_review_confirmed" not in page_schema["required"]:
            errors.append("local submission page must require page review confirmation")
        if "piece_count_variance_reviewed" not in page_schema["required"]:
            errors.append("local submission page must retain summary mismatch review state")
    if example_path.exists():
        example = json.loads(example_path.read_text())
        if example.get("mode") != "ILLUSTRATIVE_FIXTURE":
            errors.append("example must be marked ILLUSTRATIVE_FIXTURE")
        note_number = example.get("delivery_note_number")
        for index, line in enumerate(example.get("lines", []), start=1):
            if line.get("physical_quantity_confirmed") is not True:
                errors.append(f"example line {index} lacks physical confirmation")
        for index, page in enumerate(example.get("page_captures", []), start=1):
            if page.get("verified_delivery_note_number") != note_number:
                errors.append(f"example page {index} has mismatched delivery identity")
            if page.get("page_review_confirmed") is not True:
                errors.append(f"example page {index} lacks page review confirmation")
            if not isinstance(page.get("piece_count_variance_reviewed"), bool):
                errors.append(f"example page {index} lacks summary review state")

    renders = sorted((ROOT / "renders").glob("page-*.png"))
    if len(renders) < 4:
        errors.append(f"expected >=4 rendered pages, found {len(renders)}")

    if errors:
        print("FAIL")
        for e in errors:
            print(f"  - {e}")
        return 1

    print("PASS")
    print(f"  pdf_sha256={sha256_file(pdf_path)}")
    print(f"  original_rows=7 six_page_rows=14 renders={len(renders)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
