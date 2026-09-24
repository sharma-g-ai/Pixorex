import os
import json
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from typing import List
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel

from extraction import extract_fields, load_schema, SCHEMAS_DIR
from excel_store import (
    save_extraction,
    get_all_extractions,
    get_extraction_by_id,
    update_extraction_fields,
    DATA_DIR,
)
from google_sheets import sync_extraction_to_sheet, update_extraction_in_sheet

app = FastAPI(title="LabelReader API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

IMAGES_DIR = DATA_DIR / "images"
IMAGES_DIR.mkdir(parents=True, exist_ok=True)


# --- Schemas ---

@app.get("/schemas")
def list_schemas():
    schemas = []
    for schema_file in sorted(SCHEMAS_DIR.glob("*.json")):
        with open(schema_file) as f:
            schema = json.load(f)
        schemas.append({
            "equipment_type": schema["equipment_type"],
            "display_name": schema["display_name"],
            "field_count": len(schema["fields"]),
        })
    return schemas


# --- Extract ---

@app.post("/extract")
async def extract(
    images: List[UploadFile] = File(...),
    equipment_type: str = Form(...),
    user_email: str = Form(""),
):
    # Validate equipment type
    try:
        load_schema(equipment_type)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Unknown equipment type: {equipment_type}")

    # Save all uploaded images
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    saved_paths = []
    saved_filenames = []
    for i, image in enumerate(images):
        suffix = f"_{i}" if len(images) > 1 else ""
        safe_filename = f"{timestamp}{suffix}_{image.filename}"
        image_path = IMAGES_DIR / safe_filename
        content = await image.read()
        with open(image_path, "wb") as f:
            f.write(content)
        saved_paths.append(str(image_path))
        saved_filenames.append(safe_filename)

    primary_filename = saved_filenames[0]

    # Extract fields via GPT (pass all images)
    try:
        result = await extract_fields(saved_paths, equipment_type)
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Extraction failed: {str(e)}")

    # Save to Excel
    extraction_id = save_extraction(
        equipment_type=equipment_type,
        image_filename=primary_filename,
        fields=result["fields"],
        review_flags=result["review_flags"],
        user_email=user_email,
    )

    # Sync to Google Sheets
    sync_extraction_to_sheet(
        extraction_id=extraction_id,
        equipment_type=equipment_type,
        image_filename=primary_filename,
        fields=result["fields"],
        review_flags=result["review_flags"],
        user_email=user_email,
    )

    response = {
        "extraction_id": extraction_id,
        "equipment_type": equipment_type,
        "image_filename": primary_filename,
        "fields": result["fields"],
        "review_flags": result["review_flags"],
    }

    if "mismatch_warning" in result:
        response["mismatch_warning"] = result["mismatch_warning"]
        response["detected_type"] = result.get("detected_type")

    return response


# --- Extractions ---

@app.get("/extractions")
def list_extractions():
    return get_all_extractions()


@app.get("/extractions/{extraction_id}")
def get_extraction(extraction_id: str):
    result = get_extraction_by_id(extraction_id)
    if not result:
        raise HTTPException(status_code=404, detail="Extraction not found")
    return result


# --- Review / Correct ---

class CorrectionRequest(BaseModel):
    extraction_id: str
    corrected_fields: dict
    user_email: str = ""


@app.post("/review/correct")
def correct_extraction(req: CorrectionRequest):
    success = update_extraction_fields(req.extraction_id, req.corrected_fields)
    if not success:
        raise HTTPException(status_code=404, detail="Extraction not found")

    # Sync correction to Google Sheets
    update_extraction_in_sheet(req.extraction_id, req.corrected_fields, req.user_email)

    return {"status": "updated", "extraction_id": req.extraction_id}


# --- Images ---

@app.get("/images/{filename}")
def serve_image(filename: str):
    image_path = IMAGES_DIR / filename
    if not image_path.exists():
        raise HTTPException(status_code=404, detail="Image not found")
    return FileResponse(str(image_path))


# --- Download Excel ---

@app.get("/download")
def download_excel():
    from excel_store import EXCEL_PATH
    if not EXCEL_PATH.exists():
        raise HTTPException(status_code=404, detail="No extractions yet")
    return FileResponse(
        str(EXCEL_PATH),
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        filename="extractions.xlsx",
    )


# --- Google Sheet URL ---

@app.get("/sheet-url")
def get_sheet_url():
    sheet_id = os.getenv("GOOGLE_SHEET_ID")
    if not sheet_id:
        raise HTTPException(status_code=404, detail="Google Sheet not configured")
    return {"url": f"https://docs.google.com/spreadsheets/d/{sheet_id}/edit"}
