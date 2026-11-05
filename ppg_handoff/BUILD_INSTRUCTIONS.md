# Build and run instructions

## Local checks

From the repository's `frontend/` directory:

```bash
flutter pub get
flutter analyze lib/features/ppg_delivery_note test/ppg_delivery_note
flutter test test/ppg_delivery_note/
```

Validate the handoff/reference files from the repository root:

```bash
python3 ppg_handoff/tools/validate_handoff.py
```

Build a debug Android APK with a JDK supported by this repository's Gradle setup:

```bash
JAVA_HOME=/path/to/jdk-17 PATH=/path/to/jdk-17/bin:$PATH flutter build apk --debug
```

The output is `frontend/build/app/outputs/flutter-apk/app-debug.apk`. The verified build used JDK 17. Flutter reported future compatibility warnings for the currently pinned Gradle, Android Gradle Plugin, and Kotlin versions.

For the smaller review APK, run the same command with `--release`. Its output is `frontend/build/app/outputs/flutter-apk/app-release.apk`. The repository currently signs this variant with the debug key, so it is installable for review but is not a production signing artifact.

## Physical-device review

The Android capture screen offers Google's full document scanner for automatic page detection, capture, crop/rotation, and cleanup, plus the local camera fallback. Google Play services downloads the scanner UI and processing components dynamically; first use may require connectivity. The fallback and app-side enhancement modes run locally. Test both paths on target devices, including first use without a network and first use with a network.

1. Install the review APK on each intended Android model and record OS/build/device details.
2. Before launching after a fresh install, enable airplane mode to test bundled-model/offline startup. Record whether every required asset and local workflow is available without network access.
3. Start a new camera-mode session, capture one physical delivery-note page at a time, inspect crop/rotation, and save the source and rectified page.
4. Verify printed delivery number, page, and total against the saved source. Try a second note in the same physical stack; confirm it stays separate.
5. Complete page-first review, test one missing item and one document correction, edit at least one physical count, and submit locally. Reopen the session and verify its persisted snapshot and audit values.
6. Record OCR input dimensions, page/capture revision, engine, elapsed time, raw OCR text/boxes, parser choices, source-correct value, recapture/correction counts, and device conditions. Keep all document material in the authorized local review bundle; do not send it to telemetry.
7. Repeat with held-out logical documents from each approved profile. Separate automatic extraction results from operator-selected or manually entered values.

No Android device or `adb` was present during this review, so steps 1–7 remain unexecuted. The Linux/Chrome Flutter devices are not substitutes for Android camera or cold offline tests. Existing `renders/page-*.png` are PDF reference renders, not app screenshots.
