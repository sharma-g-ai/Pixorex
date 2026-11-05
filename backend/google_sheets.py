import os
import json
from datetime import datetime

import gspread
from gspread_formatting import (
    format_cell_range,
    CellFormat,
    Color,
    TextFormat,
    set_frozen,
)
from google.oauth2.service_account import Credentials
from dotenv import load_dotenv

load_dotenv()

CREDENTIALS_PATH = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
SHEET_ID = os.getenv("GOOGLE_SHEET_ID")

SCOPES = [
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/drive",
]


def _get_client() -> gspread.Client:
    if not CREDENTIALS_PATH:
        raise RuntimeError("Set GOOGLE_APPLICATION_CREDENTIALS to a private service-account JSON file")
    creds = Credentials.from_service_account_file(CREDENTIALS_PATH, scopes=SCOPES)
    return gspread.authorize(creds)


def _get_or_create_worksheet(spreadsheet: gspread.Spreadsheet, equipment_type: str) -> gspread.Worksheet:
    """Get existing worksheet for equipment type, or create one."""
    title = equipment_type.replace("_", " ").title()
    try:
        return spreadsheet.worksheet(title)
    except gspread.WorksheetNotFound:
        ws = spreadsheet.add_worksheet(title=title, rows=1000, cols=50)
        return ws


def _format_header(ws: gspread.Worksheet, num_cols: int):
    """Apply formatting to worksheet header row: bold, background color, freeze, auto-resize."""
    try:
        col_letter = chr(ord("A") + min(num_cols - 1, 25)) if num_cols <= 26 else "AZ"
        if num_cols > 26:
            first = chr(ord("A") + (num_cols - 1) // 26 - 1)
            second = chr(ord("A") + (num_cols - 1) % 26)
            col_letter = f"{first}{second}"

        # Bold white text on dark indigo background
        header_fmt = CellFormat(
            backgroundColor=Color(0.247, 0.318, 0.71),  # indigo
            textFormat=TextFormat(bold=True, foregroundColor=Color(1, 1, 1), fontSize=10),
            horizontalAlignment="CENTER",
        )
        format_cell_range(ws, f"A1:{col_letter}1", header_fmt)

        # Freeze header row
        set_frozen(ws, rows=1)

        # Auto-resize columns via Sheets API
        body = {
            "requests": [
                {
                    "autoResizeDimensions": {
                        "dimensions": {
                            "sheetId": ws.id,
                            "dimension": "COLUMNS",
                            "startIndex": 0,
                            "endIndex": num_cols,
                        }
                    }
                }
            ]
        }
        ws.spreadsheet.batch_update(body)

    except Exception as e:
        print(f"Header formatting failed: {e}")


def sync_extraction_to_sheet(
    extraction_id: str,
    equipment_type: str,
    image_filename: str,
    fields: dict,
    review_flags: dict,
    status: str = "pending",
    user_email: str = "",
):
    """Sync a single extraction to Google Sheets. Each equipment type gets its own tab."""
    if not SHEET_ID:
        print("GOOGLE_SHEET_ID not set, skipping Google Sheets sync")
        return

    try:
        client = _get_client()
        spreadsheet = client.open_by_key(SHEET_ID)
        ws = _get_or_create_worksheet(spreadsheet, equipment_type)

        # Check if header exists
        existing = ws.get_all_values()
        if not existing:
            # Build header: fixed columns + all field names
            header = ["user_email", "uuid", "timestamp", "equipment_type", "image_filename", "status"]
            field_names = sorted(fields.keys())
            header.extend(field_names)
            header.append("review_flags")
            ws.append_row(header)
            _format_header(ws, len(header))
        else:
            # Use existing header to maintain column order
            header = existing[0]
            # Ensure user_email column exists
            if "user_email" not in header:
                header.insert(0, "user_email")
                ws.update(range_name="1:1", values=[header])
            # Add any new fields not in header
            field_names = sorted(fields.keys())
            new_fields = [f for f in field_names if f not in header]
            if new_fields:
                header.extend(new_fields)
                ws.update(range_name="1:1", values=[header])

        # Build row matching header order
        row = []
        for col in header:
            if col == "uuid":
                row.append(extraction_id)
            elif col == "timestamp":
                row.append(datetime.now().isoformat())
            elif col == "equipment_type":
                row.append(equipment_type)
            elif col == "image_filename":
                row.append(image_filename)
            elif col == "status":
                row.append(status)
            elif col == "user_email":
                row.append(user_email)
            elif col == "review_flags":
                row.append(json.dumps(review_flags))
            else:
                row.append(str(fields.get(col, "")) if fields.get(col) is not None else "")

        ws.append_row(row, value_input_option="USER_ENTERED")
        print(f"Synced extraction {extraction_id} to Google Sheets [{equipment_type}]")

    except Exception as e:
        print(f"Google Sheets sync failed: {e}")


def update_extraction_in_sheet(extraction_id: str, corrected_fields: dict, user_email: str = ""):
    """Update an existing extraction row in Google Sheets after review."""
    if not SHEET_ID:
        return

    try:
        client = _get_client()
        spreadsheet = client.open_by_key(SHEET_ID)

        # Search all worksheets for the extraction_id
        for ws in spreadsheet.worksheets():
            try:
                cell = ws.find(extraction_id)
                if cell:
                    header = ws.row_values(1)
                    row_values = ws.row_values(cell.row)
                    # Pad row if needed
                    while len(row_values) < len(header):
                        row_values.append("")

                    # Update fields
                    for col_name, value in corrected_fields.items():
                        if col_name in header:
                            idx = header.index(col_name)
                            row_values[idx] = str(value) if value is not None else ""

                    # Update status
                    if "status" in header:
                        row_values[header.index("status")] = "reviewed"

                    # Update reviewer email
                    if "reviewed_by" not in header:
                        header.append("reviewed_by")
                        ws.update(range_name="1:1", values=[header])
                        while len(row_values) < len(header):
                            row_values.append("")
                    row_values[header.index("reviewed_by")] = user_email

                    ws.update(range_name=f"A{cell.row}", values=[row_values])
                    print(f"Updated extraction {extraction_id} in Google Sheets")
                    return
            except gspread.exceptions.CellNotFound:
                continue

    except Exception as e:
        print(f"Google Sheets update failed: {e}")
