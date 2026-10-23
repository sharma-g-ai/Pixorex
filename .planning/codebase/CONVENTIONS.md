---
last_mapped_commit: 64405acfa13ec78cf102cb081212fd931bb8a4e4
last_mapped_at: 2026-10-11
---
# Coding Conventions

**Analysis Date:** 2026-10-11

## Language & Platform

This codebase spans:
- **Frontend:** Flutter/Dart (primary application)
- **Backend:** Python 3 with FastAPI (API and extraction)

Conventions below are language-specific where noted.

## Naming Patterns

### Dart

**Files:**
- Lowercase with underscores: `ppg_session_controller.dart`, `app_state.dart`
- No abbreviations unless universal (OCR, API, PPG are acceptable)
- Test files: `{module}_test.dart` (e.g., `ppg_parser_test.dart`)

**Classes & Types:**
- PascalCase: `PpgSessionController`, `OcrElement`, `ScanSession`, `PageCapture`
- Enums: PascalCase values: `enum ScanSessionStatus { draft, reviewing, submittedLocal }`
- Record types use camelCase fields: `({String label, PpgTone tone})`

**Functions & Methods:**
- camelCase: `parse()`, `parseAll()`, `recognizeFile()`, `validatePhysicalInput()`
- Async functions: Same naming, no suffix like `Async` (convention handled by Future return type)
- Getters for computed properties: `get userEmail => _userEmail`
- Helper functions can be prefixed with underscore if private to file: `_hasLabel()`, `_upgradeToV2()`

**Variables & Constants:**
- Local variables: camelCase: `final pages = []`, `int printedPage = 3`
- Private instance fields: underscore prefix: `_userEmail`, `_isLoading`, `_db`
- Static constants: SCREAMING_SNAKE_CASE or camelCase depending on visibility
  - `const _labelScannerHome = bool.fromEnvironment('LABEL_SCANNER')` (private, uses camelCase)
  - `static final _articleRe = RegExp(...)` (private static regex)
  - `static const String baseUrl = 'http://localhost:8002'` (public static constant, camelCase)

**Enum Values:**
- camelCase: `PhysicalCountState.notChecked`, `OccurrenceRole.quantityBearing`

### Python

**Files:**
- Lowercase with underscores: `main.py`, `extraction.py`, `excel_store.py`, `google_sheets.py`

**Classes:**
- PascalCase: `AsyncOpenAI`

**Functions & Variables:**
- snake_case: `load_schema()`, `build_prompt()`, `save_extraction()`, `equipment_type`

**Constants:**
- SCREAMING_SNAKE_CASE: `SCHEMAS_DIR`, `KNOWN_SCHEMA_NAMES`, `MISMATCH_HANDLING_RULES`

## Code Style

### Formatting

**Dart:**
- Indentation: 2 spaces (Flutter standard)
- Line breaks: Thoughtful wrapping around 80-100 characters, but readability over strict limits
- Spacing: Single space around binary operators, no space after function names
- Import grouping: dart: imports → package:flutter → package:other → relative imports
  ```dart
  import 'dart:convert';
  import 'dart:io';
  
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  
  import '../domain/models.dart';
  ```

**Python:**
- Indentation: 4 spaces (PEP 8 standard)
- Line length: Follows FastAPI/pydantic conventions, pragmatic wrapping
- Type hints used extensively: `async def extract(images: List[UploadFile] = File(...), equipment_type: str = Form(...))`
- `from dotenv import load_dotenv` pattern for environment configuration

### Linting & Analysis

**Dart:**
- Tool: `flutter_lints` (active in `analysis_options.yaml`)
- Enforced rules: Flutter default rule set
- Disabled rules: None explicitly disabled in analysis_options.yaml
- Analysis run via: `flutter analyze`

**Python:**
- No explicit linter configuration found
- Adheres to PEP 8 implicitly via code samples

### Constructs & Patterns

**Dart:**

1. **Null Safety:**
   - Nullable types marked with `?`: `String?`, `int?`
   - Null-coalescing: `value ?? defaultValue`
   - Null-aware access: `object?.property`
   - Non-null assertions rare, used only when type system cannot express certainty

2. **Getters & Setters:**
   ```dart
   String get userEmail => _userEmail;
   void setUserEmail(String email) {
     _userEmail = email;
     notifyListeners();
   }
   ```

3. **Const Constructors:**
   - Applied liberally for widget classes: `const PixorexApp({super.key})`
   - Improves performance via const propagation

4. **Factory Constructors & Named Constructors:**
   ```dart
   factory OcrElement.fromJson(Map<String, dynamic> json) => OcrElement(...)
   ```

5. **Switch Expressions (Dart 3.0+):**
   ```dart
   return switch (line.physicalCountState) {
     PhysicalCountState.notChecked => (label: 'To count', tone: PpgTone.neutral),
     PhysicalCountState.verified => ...,
   };
   ```

6. **Cascade Operator (..):**
   - Used minimally in favor of explicit variable assignment
   - Example: `list..add(item)..sort()` avoided; instead separate statements

7. **Extension Methods:**
   - Not heavily used in this codebase
   - Future expansion point

8. **Spread Operator (...):**
   - Used in Set/List literals for combining collections:
     ```dart
     return {
       ...blockingIssues,
       if (session?.deliveryNoteNumber == null) 'Verify identity',
     }.toList();
     ```

9. **Records:**
   - Used for returning multiple related values:
     ```dart
     ({String label, PpgTone tone}) ppgCountStatus(DocumentLine line)
     ```

**Python:**

1. **Type Hints:**
   - Function signatures fully typed: `async def extract_fields(saved_paths: List[str], equipment_type: str) -> dict`
   - Return types specified
   - Use of `|` for union types (Python 3.10+): `str | None`

2. **Error Handling:**
   - HTTPException for API errors: `raise HTTPException(status_code=400, detail="Unknown equipment type")`
   - Try-except with specific exception types
   - Graceful fallbacks: `except (_): return None`

3. **Path Handling:**
   - `pathlib.Path` for all file operations (not string paths)
   - `Path(__file__).parent` pattern for relative imports

4. **Async/Await:**
   - All I/O operations async: `async def`, `await`
   - Used in FastAPI handlers

## Import Organization

### Dart

Standard order (enforced by linter):
1. dart: library imports
2. package:flutter imports
3. Other package: imports (provider, supabase_flutter, etc.)
4. Relative imports (../, ./)

Example from `frontend/lib/main.dart`:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/app_state.dart';
import 'screens/home_screen.dart';
```

### Python

Standard order (implicit PEP 8):
1. Standard library (os, json, pathlib, etc.)
2. Third-party packages (fastapi, pydantic, openai, etc.)
3. Local imports (extraction, excel_store, google_sheets)

Example from `backend/main.py`:

```python
import os
import json
import re
import secrets
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, UploadFile, File, Form, HTTPException, Header, Depends
from pydantic import BaseModel
from extraction import extract_fields, load_schema, SCHEMAS_DIR
```

## Error Handling

### Dart

**Throwing Errors:**
- Use specific error types:
  - `StateError('message')` for invalid state
  - `UnsupportedError('message')` for platform/feature not supported
  - `Exception('message')` for general failures
  
  Example from `frontend/lib/features/ppg_delivery_note/ocr/ppg_ocr_adapter.dart`:
  ```dart
  if (!Platform.isAndroid) {
    throw UnsupportedError(
      'Bundled ML Kit OCR is Android-only in this POC. '
      'Use developer image import with synthetic geometry on other platforms.',
    );
  }
  if (result == null) {
    throw StateError('OCR returned null');
  }
  ```

**Validation Functions:**
- Return error messages as `String?` (null = valid, string = error message)
- Example from `frontend/lib/features/ppg_delivery_note/domain/validation.dart`:
  ```dart
  static String? validatePhysicalInput(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Quantity is required';
    if (trimmed.contains('.') || trimmed.contains(',')) {
      return 'Fractions are not supported';
    }
    final parsed = int.tryParse(trimmed);
    if (parsed == null) return 'Enter a whole number';
    if (parsed < 0) return 'Negative quantities are not allowed';
    return null;
  }
  ```

**Try-Catch:**
- Minimal use; exceptions are rare and significant
- Used mainly for network/IO operations
- No silent failures; errors logged or propagated

### Python

**HTTP Exceptions:**
- FastAPI pattern: `HTTPException(status_code=400, detail='Human-readable message')`
- Example from `backend/main.py`:
  ```python
  try:
      load_schema(equipment_type)
  except ValueError:
      raise HTTPException(status_code=400, detail=f"Unknown equipment type: {equipment_type}")
  ```

**Graceful Degradation:**
- Some features fail gracefully:
  ```python
  try:
      final response = await http.get(Uri.parse('$baseUrl/sheet-url'));
      if (response.statusCode == 200) {
        return json.decode(response.body)['url'];
      }
  } catch (_) {}
  return null;
  ```

## Comments

### Dart

**Documentation Comments (///):**
- Used for public APIs and classes
- Placed directly above class/method definition
- Explain purpose, parameters, return value

Example from `frontend/lib/features/ppg_delivery_note/parser/ppg_template_parser.dart`:

```dart
/// Deterministic PPG delivery-note template parser.
///
/// Accepts word-level ML Kit elements: rebuilds lines first, then parses.
/// Synthetic fixtures with whole-phrase elements still work.
class PpgTemplateParser {
```

Example from `frontend/lib/features/ppg_delivery_note/ocr/ppg_ocr_adapter.dart`:

```dart
/// Read a small field in its own OCR pass. Coordinates are source-image
/// pixels; the Android bridge scales the crop for small printed text.
Future<OcrObservation> recognizeCrop({
```

**Inline Comments (//):**
- Explain WHY, not WHAT
- Placed above or inline with non-obvious code
- Example from `frontend/lib/main.dart`:
  ```dart
  /// This build opens straight on PPG Delivery notes. Pass
  /// `--dart-define=LABEL_SCANNER=true` to open on the label scanner instead,
  /// with Delivery notes behind its truck icon.
  const _labelScannerHome = bool.fromEnvironment('LABEL_SCANNER');
  ```

**Library Documentation:**
- File starts with library-level docs if significant
  ```dart
  /// Core domain types for PPG delivery-note offline scanner.
  library;
  ```

### Python

**Docstrings:**
- Used sparingly; code is self-documenting
- Inline comments explain complex logic

Example from `backend/extraction.py`:

```python
MISMATCH_HANDLING_RULES = """
Mismatch handling:
If _image_match is false, the image belongs to a different category than the selected schema.

- Do not force values into selected-schema fields just because this prompt asks for that schema.

...
"""
```

## Function Design

### Size & Complexity

**Dart:**
- Functions kept short (30-50 lines typical)
- Complex parsing broken into smaller helpers
- Example: `PpgTemplateParser.parse()` calls `OcrLineBuilder.buildLines()`, `_hasLabel()`, etc.

**Python:**
- Async functions in FastAPI handlers kept simple (validate → call service → return)
- Business logic extracted to helper functions
- Example: `extract()` handler calls `load_schema()`, `extract_fields()`, `save_extraction()`

### Parameters

**Dart:**
- Named parameters for clarity:
  ```dart
  Future<OcrObservation> recognizeFile({
    required String imagePath,
    required String pageCaptureId,
    required int captureRevision,
  })
  ```
- Required parameters marked with `required` keyword
- Optional parameters come after required

**Python:**
- Type-annotated parameters:
  ```python
  async def extract(
      images: List[UploadFile] = File(...),
      equipment_type: str = Form(...),
      user_email: str = Form(""),
  )
  ```
- FastAPI `Form()`, `File()` markers used as defaults for dependency injection

### Return Values

**Dart:**
- Return types always explicit
- Future<T> for async operations
- Nullable types used when applicable
- Records for multiple related returns

**Python:**
- Return types always annotated
- dict for JSON responses
- Coroutines (async) always return Future-like results

## Module Design

### Exports

**Dart:**
- No barrel files (index.dart) heavily used
- Direct imports of specific classes/functions
- Library-level declarations minimal

**Python:**
- Functions imported directly: `from extraction import extract_fields, load_schema`
- No __init__.py patterns creating convenience exports

### Organization

**Dart Feature Structure:**
- Features organized by domain (ppg_delivery_note feature)
- Subdirectories: domain/, ocr/, parser/, persistence/, screens/, services/, ui/, widgets/
- Clear separation of concerns: models, business logic, UI, data access

**Python Module Structure:**
- Flat structure: main.py, extraction.py, excel_store.py, google_sheets.py
- Schemas stored in `schemas/` directory with `.json` files
- Data and images stored in `data/` directory

---

*Convention analysis: 2026-10-11*
