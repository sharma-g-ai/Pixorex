---
last_mapped_commit: 64405acfa13ec78cf102cb081212fd931bb8a4e4
last_mapped_at: 2026-10-11
---
# Technology Stack

**Analysis Date:** 2026-10-11

## Languages

**Primary:**
- Dart 3.11.0+ - Flutter application frontend (`frontend/lib/`)
- Python 3.9+ - Backend API services (`backend/`)
- TypeScript - Supabase Edge Functions (`supabase/functions/`)

**Secondary:**
- Java 17 - Android build toolchain
- Kotlin - Android build system integration

## Runtime

**Environment:**
- Flutter SDK (with Dart runtime) - Cross-platform mobile and desktop
- Python 3 - Backend API runtime
- Deno - Supabase Edge Functions runtime
- Java Runtime Environment (JDK 17) - Android APK builds

**Package Manager:**
- Pub - Dart/Flutter dependencies
  - Lockfile: `frontend/pubspec.lock`
- pip - Python dependencies
  - Lockfile: `backend/requirements.txt`

## Frameworks

**Core:**
- Flutter 3.11.0+ - Cross-platform UI framework
  - Targets: Android, iOS, macOS, Windows, Linux, Web
- FastAPI - Python async web framework for backend API (`backend/main.py`)
- Supabase - Backend-as-a-Service platform

**State Management:**
- Provider 6.1.5+ - State management and dependency injection (`frontend/lib/services/`)

**Camera & Image:**
- camera 0.11.0+2 - Native camera integration (`frontend/pubspec.yaml`)
- image_picker 1.2.1 - Image selection from device
- Pillow - Python image processing (`backend/`)

**Storage & Persistence:**
- sqflite 2.4.2 - SQLite database for Flutter local storage
- shared_preferences 2.5.5 - Key-value persistent storage on mobile
- path_provider 2.1.5 - Platform-specific application directories

**HTTP & Networking:**
- http 1.6.0 - Flutter HTTP client
- supabase_flutter 2.8.0 - Supabase client library
- gspread 5.x+ - Google Sheets API Python client
- openai - OpenAI Python SDK (`backend/extraction.py`)

**Utilities:**
- uuid 4.5.1 - UUID generation
- url_launcher 6.3.2 - URL launching
- share_plus 12.0.2 - Platform share dialogs
- python-dotenv - Environment variable loading
- python-multipart - Multipart form data handling
- openpyxl - Excel file generation and manipulation
- gspread-formatting - Google Sheets styling

## Key Dependencies

**Critical:**
- supabase_flutter 2.8.0 - Backend database, auth, storage, and edge functions
- openai - GPT-4/Vision API for OCR extraction and schema generation
- gspread 5.x+ - Real-time extraction result sync to Google Sheets

**Infrastructure:**
- FastAPI - Modern async REST API framework for Python backend
- Pillow - Image processing for validation and resizing
- python-multipart - File upload handling
- openpyxl - Extraction history persistence to Excel

## Configuration

**Environment:**
- Variables loaded via `.env` (note: `.env` file present, contents not disclosed)
- Environment variables required:
  - `OPENAI_API_KEY` - OpenAI API authentication
  - `LABEL_READER_BACKEND_TOKEN` - Backend API authentication token
  - `LABEL_READER_ALLOWED_ORIGINS` - CORS allow-list (default: localhost:3000)
  - `GOOGLE_APPLICATION_CREDENTIALS` - Path to Google service account JSON
  - `GOOGLE_SHEET_ID` - Target Google Sheet ID for synced extractions

**Build:**
- Flutter build config: `frontend/pubspec.yaml` with multi-platform settings
- Flutter icon generation: `flutter_launcher_icons` plugin
- Flutter linting: `analysis_options.yaml` with `flutter_lints`
- Android build: Gradle + Android Gradle Plugin (Kotlin, JDK 17 required)
- Backend: Python FastAPI app with Uvicorn ASGI server

## Platform Requirements

**Development:**
- Flutter SDK 3.11.0+ with Dart SDK
- Java Development Kit (JDK 17) for Android builds
- Python 3.9+ with pip
- Git

**Production:**
- Android 12+ for mobile deployment
- iOS 11+ (if iOS target deployed)
- Supabase project (backend storage and functions)
- OpenAI API account with quota
- Google service account (for Google Sheets sync)
- FastAPI backend server with Uvicorn

**Deployment Targets:**
- Android APK (`frontend/build/app/outputs/flutter-apk/app-*.apk`)
- iOS IPA (via Xcode, not built in this review)
- macOS, Windows, Linux desktop apps
- Web via Flutter web
- Python FastAPI backend (runs on HTTP, typically port 8002 for local development)

---

*Stack analysis: 2026-10-11*
