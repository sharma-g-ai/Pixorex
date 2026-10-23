import os
import json
import base64
from pathlib import Path
from openai import AsyncOpenAI
from dotenv import load_dotenv

load_dotenv()

client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))

SCHEMAS_DIR = Path(__file__).parent / "schemas"
KNOWN_SCHEMA_NAMES = [
    "motor",
    "generator",
    "transformer",
    "chiller",
    "equipment_label",
    "paint_label",
    "other",
]
SCHEMA_CONFIDENCE_VALUES = ["high", "medium", "low"]

MISMATCH_HANDLING_RULES = """
Mismatch handling:
If _image_match is false, the image belongs to a different category than the selected schema.

- Do not force values into selected-schema fields just because this prompt asks for that schema.
- Fill a selected-schema field only when the value is directly visible and genuinely matches the same semantic concept as the field name.
- Cross-schema fields such as manufacturer, made_in, serial_no, volts, hz, barcode, or UPC may be filled when they are clearly visible and semantically correct.
- Schema-specific fields must stay null unless they are clearly present for this image. For example, if a user selected Motor but the image is a transformer plate, do not invent rpm, hp, frame_no, nema_des, or motor-only fields.
- Always return _image_match, _detected_type, _suggested_schema, and _schema_confidence so the app can route the record correctly.
"""

FIELD_CONFIDENCE_RULES = """
Field confidence:
- Return _field_confidence as a JSON object for populated fields only.
- Prefer this shape: {"field_name": {"level": "high|medium|low", "score": 0.0-1.0}}.
- Use high / 0.85-1.0 only when the value is clearly visible and directly read from the image.
- Use medium / 0.70-0.84 when the value is mostly clear but has minor ambiguity.
- Use low / below 0.70 when the value is partially occluded, blurry, inferred from context, conflicting across images, or contains ? placeholders.
- Return _field_review_notes as a JSON object containing only low-confidence fields, with a short reason for each.
- Do not mark null/missing fields as low confidence. Review is only for extracted values that may be wrong.
"""


def load_schema(equipment_type: str) -> dict:
    schema_path = SCHEMAS_DIR / f"{equipment_type}.json"
    if not schema_path.exists():
        raise ValueError(f"Unknown equipment type: {equipment_type}")
    with open(schema_path) as f:
        return json.load(f)


def build_prompt(schema: dict) -> str:
    fields = schema["fields"]
    field_list = "\n".join(f"- {f}" for f in fields)

    return f"""You are an expert at reading industrial nameplates, data plates, serial plates, rating plates, and equipment labels.

Step 1: Identify what kind of document this is (nameplate, data plate, serial plate, rating plate, or equipment label) and what equipment it belongs to (motor, generator, transformer, chiller, pump, loader, vehicle, marine engine, etc.).

Step 2: Read the entire plate systematically — top to bottom, left to right. For tabular plates, read row by row including column headers.

Step 3: For ambiguous characters, apply these rules:
  - 0 vs O: In numeric fields (volts, amps, rpm), prefer 0. In model/serial numbers, preserve what you see exactly as printed.
  - 1 vs I vs l: In numeric fields, prefer 1. In text fields, prefer I or l based on context.
  - T vs F: Look for crossbar presence.
  - 5 vs S, 8 vs B: Use surrounding context.
  - Bearing designations typically end with C3 (e.g., 6310C3, 6210C3).
  - Frame numbers are typically 3 digits + letter (e.g., 284T, 326T).
  - If a character is partially legible, use ? as a placeholder (e.g., "95?00718"). This is better than guessing.

Step 4: Extract every visible field into the JSON schema below.

IMPORTANT RULES:
- Use the FIXED COLUMNS first. Only use extra_fields for data that truly does not fit any fixed column.
  - hazardous_locations: ANY hazardous area classification, ATEX, Ex markings, Class/Division/Group ratings → goes here, NOT extra_fields.
  - description: Equipment type description text (e.g., "THREE PHASE INDUCTION MOTOR") → goes here, NOT extra_fields.
  - notes: Patents, standards, certifications, warnings, any other notable text → goes here, NOT extra_fields.
  - made_in: Country of manufacture → goes here. Do NOT include city/address.
  - connection_info: Winding connection diagrams, terminal markings → goes here, NOT extra_fields.
- Return values exactly as printed on the plate — numbers only, no added units or symbols unless they are printed.
  Example: if plate says "1760" next to RPM, return rpm: "1760" not rpm: "1760 RPM".
  Example: if plate says "89.5" next to EFF%, return efficiency: "89.5" not efficiency: "89.5%".
  Example: if plate says "230/460" next to VOLTS, return volts: "230/460" not volts: "230/460 V".
- For manufacturer, return only the company name, not the address or location.
  Example: return manufacturer: "Siemens Ltd." not manufacturer: "Siemens Ltd., China".
- Use null for fields not present on this plate. Do not guess or fabricate values.
- If a plate shows dual ratings (e.g., 50Hz and 60Hz lines), extract ONLY the first/primary rating into fixed columns. Put secondary ratings in extra_fields.
- For volts, amps, kw, hp: extract ONLY the electrical value. Do not combine with Hz or phase.
  Example: if plate says "460/60/3", return volts: "460", hz: "60", phase: "3" — NOT volts: "460/60/3".
- For Other labels, use label_type for the user-facing category, primary_identifier for the most important visible code/barcode/serial, secondary_identifier for a supporting code, barcode for any visible barcode/UPC/EAN, and visible_text for compact readable text that does not fit fixed fields.

Step 5: For extra_fields, capture any remaining visible labels and values not covered by the fixed fields. Return as a JSON object of {{"label": "value"}} pairs.

Return strict JSON with these keys exactly:

Equipment type: {schema['display_name']}

Fields to extract:
{field_list}

Also include these VALIDATION fields:
- _image_match: true if the image matches the expected equipment type "{schema['display_name']}", false if it does not (e.g., user selected Motor but image shows a Transformer)
- _detected_type: a short description of what you actually see in the image (e.g., "Motor Nameplate", "Transformer Rating Plate", "Paint Label", "Not a label/nameplate")
- _suggested_schema: one of {", ".join(KNOWN_SCHEMA_NAMES)}. Use this decision rule:
  * If the image shows a paint, chemical, sealant, adhesive, coating, primer, hardener, or similar product container label, return "paint_label".
  * If it shows an industrial equipment nameplate (motor, generator, transformer, chiller, or similar data plate), return the matching equipment schema name ("motor", "generator", "transformer", or "chiller").
  * If it shows a general equipment serial/asset/part label that does not belong to a specific equipment nameplate category, return "equipment_label".
  * For any other product or label that does not fit the above (apparel tags, retail packaging, signs, documents), return "other".
- _schema_confidence: one of {", ".join(SCHEMA_CONFIDENCE_VALUES)}. Confidence that _suggested_schema is the right schema for the image(s).

{MISMATCH_HANDLING_RULES}
{FIELD_CONFIDENCE_RULES}
Return ONLY a JSON object with the schema field names plus the validation fields above. Schema values must be strings, null, or an object for extra_fields. _image_match must be boolean. _field_confidence and _field_review_notes must be JSON objects. Do not include any explanation, markdown, or extra text — just the JSON object."""


def normalize_suggested_schema(value) -> str | None:
    if value is None:
        return None
    normalized = "".join(ch if ch.isalnum() else "_" for ch in str(value).strip().lower())
    while "__" in normalized:
        normalized = normalized.replace("__", "_")
    normalized = normalized.strip("_")
    # Alias map for GPT's free-form _suggested_schema output. Keys are the
    # raw (normalized) values we have observed or expect from GPT; values
    # are one of KNOWN_SCHEMA_NAMES.
    #
    # Deliberate omission: bare "nameplate" / "data_plate" / "rating_plate"
    # are NOT aliased. Those are ambiguous — they might be a motor, a
    # generator, a chiller, or a generic asset plate. Letting them fall
    # through to None keeps the user's manually-selected schema in charge
    # rather than silently downgrading a motor scan into equipment_label.
    #
    # Keep this map byte-synchronized with _normalizeSuggestedSchema in
    # frontend/lib/services/openai_service.dart.
    aliases = {
        # Industrial equipment nameplates → specific schema
        "motor_nameplate": "motor",
        "induction_motor_nameplate": "motor",
        "ac_generator_nameplate": "generator",
        "generator_nameplate": "generator",
        "current_transformer_nameplate": "transformer",
        "transformer_nameplate": "transformer",
        "hvac_chiller_nameplate": "chiller",
        "chiller_nameplate": "chiller",

        # General equipment data/asset/serial plates → equipment_label
        "equipment_nameplate": "equipment_label",
        "equipment_data_plate": "equipment_label",
        "equipment_serial_plate": "equipment_label",
        "asset_tag": "equipment_label",
        "serial_plate": "equipment_label",

        # Paint / chemical / coating product containers → paint_label
        "paint_chemical_label": "paint_label",
        "paint_can_label": "paint_label",
        "chemical_label": "paint_label",
        "sealant_tube": "paint_label",
        "sealant_label": "paint_label",
        "adhesive_label": "paint_label",
        "adhesive_tube": "paint_label",
        "coating_label": "paint_label",
        "primer_label": "paint_label",
        "hardener_label": "paint_label",
        "threadlocker_label": "paint_label",

        # Ambiguous retail / product / apparel labels → quarantine in other
        "label": "other",
        "generic_label": "other",
        "product_label": "other",
        "product_tag": "other",
        "retail_label": "other",
        "retail_tag": "other",
        "apparel_label": "other",
        "apparel_tag": "other",
        "clothing_tag": "other",
        "garment_tag": "other",
        "sku_label": "other",
        "packaging_label": "other",
        "box_label": "other",

        # Explicit non-matches → quarantine rather than drop
        "not_a_label": "other",
        "not_a_nameplate": "other",
        "not_a_product": "other",
        "random_object": "other",
        "no_label": "other",
        "no_text": "other",
        "blank": "other",
        "empty": "other",
        "illegible": "other",
        "unreadable": "other",
        "unknown": "other",
        "none": "other",
    }
    candidate = aliases.get(normalized, normalized)
    return candidate if candidate in KNOWN_SCHEMA_NAMES else None


def normalize_schema_confidence(value) -> str | None:
    if value is None:
        return None
    confidence = str(value).strip().lower()
    return confidence if confidence in SCHEMA_CONFIDENCE_VALUES else None


def encode_image_to_base64(image_path: str) -> str:
    with open(image_path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


def normalize_field_confidence(value, known_fields) -> dict:
    if not isinstance(value, dict):
        return {}
    allowed = set(known_fields)
    out = {}
    for field, raw in value.items():
        field = str(field)
        if field not in allowed:
            continue

        level = None
        score = None
        if isinstance(raw, dict):
            raw_level = str(raw.get("level", "")).strip().lower()
            if raw_level in SCHEMA_CONFIDENCE_VALUES:
                level = raw_level
            raw_score = raw.get("score")
            if isinstance(raw_score, (int, float)):
                score = max(0.0, min(1.0, float(raw_score)))
            elif isinstance(raw_score, str):
                try:
                    score = max(0.0, min(1.0, float(raw_score.strip())))
                except ValueError:
                    pass
        elif isinstance(raw, (int, float)):
            score = max(0.0, min(1.0, float(raw)))
        else:
            raw_level = str(raw).strip().lower()
            if raw_level in SCHEMA_CONFIDENCE_VALUES:
                level = raw_level

        if level is None and score is not None:
            level = "low" if score < 0.70 else "medium" if score < 0.85 else "high"
        if score is None and level is not None:
            score = 0.60 if level == "low" else 0.78 if level == "medium" else 0.92
        if level is not None or score is not None:
            out[field] = {
                **({"level": level} if level is not None else {}),
                **({"score": score} if score is not None else {}),
            }
    return out


def normalize_field_review_notes(value, known_fields) -> dict:
    if not isinstance(value, dict):
        return {}
    allowed = set(known_fields)
    out = {}
    for field, note in value.items():
        field = str(field)
        note = str(note).strip()
        if field in allowed and note:
            out[field] = note
    return out


def get_review_flags(extracted_fields: dict, field_confidence: dict, field_review_notes: dict) -> dict:
    flags = {}
    for field, info in field_confidence.items():
        value = extracted_fields.get(field)
        level = info.get("level") if isinstance(info, dict) else None
        score = info.get("score") if isinstance(info, dict) else None
        should_review = level == "low" or (isinstance(score, (int, float)) and score < 0.70)
        if should_review and value is not None and str(value).strip():
            flags[field] = {
                "confidence": level or "low",
                **({"score": score} if isinstance(score, (int, float)) else {}),
                **({"reason": field_review_notes[field]} if field_review_notes.get(field) else {}),
            }
    return flags


async def extract_fields(image_paths: list[str], equipment_type: str) -> dict:
    """Extract fields from one or more images of the same label."""
    schema = load_schema(equipment_type)
    prompt = build_prompt(schema)

    if len(image_paths) > 1:
        prompt += f"\n\nYou are given {len(image_paths)} images of the same label/nameplate (different angles, closeups, front/back). Combine information from ALL images into a single extraction. If the same field is visible in multiple images, use the clearest/most legible one."

    mime_map = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp", ".gif": "image/gif"}

    # Build content array: text prompt + all images
    content = [{"type": "text", "text": prompt}]
    for image_path in image_paths:
        image_b64 = encode_image_to_base64(image_path)
        ext = Path(image_path).suffix.lower()
        mime_type = mime_map.get(ext, "image/jpeg")
        content.append({
            "type": "image_url",
            "image_url": {
                "url": f"data:{mime_type};base64,{image_b64}"
            },
        })

    response = await client.chat.completions.create(
        model="gpt-5.4",
        messages=[
            {
                "role": "user",
                "content": content,
            }
        ],
        max_completion_tokens=4096,
        temperature=0,
    )

    raw_text = response.choices[0].message.content.strip()

    # Strip markdown code fences if present
    if raw_text.startswith("```"):
        lines = raw_text.split("\n")
        lines = [l for l in lines if not l.startswith("```")]
        raw_text = "\n".join(lines)

    extracted_fields = json.loads(raw_text)

    # Extract validation fields
    image_match_raw = extracted_fields.pop("_image_match", True)
    detected_type = extracted_fields.pop("_detected_type", None)
    suggested_schema = normalize_suggested_schema(
        extracted_fields.pop("_suggested_schema", None)
    )
    schema_confidence = normalize_schema_confidence(
        extracted_fields.pop("_schema_confidence", None)
    )
    field_confidence = normalize_field_confidence(
        extracted_fields.pop("_field_confidence", None),
        extracted_fields.keys(),
    )
    field_review_notes = normalize_field_review_notes(
        extracted_fields.pop("_field_review_notes", None),
        extracted_fields.keys(),
    )

    # GPT may return bool or string — normalize
    if isinstance(image_match_raw, str):
        image_match = image_match_raw.lower() in ("true", "yes", "1")
    else:
        image_match = bool(image_match_raw)

    review_flags = get_review_flags(extracted_fields, field_confidence, field_review_notes)

    result = {
        "fields": extracted_fields,
        "review_flags": review_flags,
        "equipment_type": equipment_type,
        "schema_fields": schema["fields"],
    }

    if suggested_schema is not None:
        result["suggested_schema"] = suggested_schema
    if schema_confidence is not None:
        result["schema_confidence"] = schema_confidence
    if field_confidence:
        result["field_confidence"] = field_confidence
    if field_review_notes:
        result["field_review_notes"] = field_review_notes

    # Add mismatch warning if image doesn't match selected type
    if not image_match:
        suggestion = (
            ""
            if suggested_schema is None
            else f" Suggested schema: {suggested_schema}"
            + ("" if schema_confidence is None else f" ({schema_confidence} confidence)")
            + "."
        )
        result["mismatch_warning"] = f"Image appears to be: {detected_type or 'unknown'}. You selected: {schema['display_name']}.{suggestion}"
        result["detected_type"] = detected_type

    return result
