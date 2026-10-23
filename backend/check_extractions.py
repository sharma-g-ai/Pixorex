from excel_store import get_all_extractions
import json

extractions = get_all_extractions()
print(f"Total extractions: {len(extractions)}\n")

for e in extractions:
    eid = e["extraction_id"][:8]
    etype = e["equipment_type"]
    status = e["status"]
    fields = e["fields"]
    flags = e.get("review_flags", {})

    print(f"--- ID: {eid}... | Type: {etype} | Status: {status}")
    print(f"    Fields extracted: {len(fields)}")
    for k, v in fields.items():
        flag = " << REVIEW" if k in flags else ""
        print(f"    {k}: {v}{flag}")
    print()
