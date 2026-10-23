# Implementation report template — PPG DN scanner

## Repository / framework decisions

- Host app:
- Branch:
- PPG module path:
- OCR adapter:
- Persistence:

## Dependency versions

- Flutter:
- sqflite:
- ML Kit text-recognition:

## Build / run / test commands

```bash
cd frontend
flutter pub get
flutter test test/ppg_delivery_note/
flutter run
```

Handoff package check:

```bash
python3 ppg_handoff/tools/validate_handoff.py
```

## Acceptance results (T01–T32)

| ID | Result | Method | Notes |
|---|---|---|---|
| T01 | | | |
| … | | | |

Separate explicitly:

- [ ] Source reference / schema package validation
- [ ] Domain/parser tests (synthetic geometry)
- [ ] On-device OCR against reference images
- [ ] Physical-paper camera workflow on named device
- [ ] Fresh-install offline operation

## Known limitations

- DEVICE_VALIDATION_PENDING where hardware was unavailable.
