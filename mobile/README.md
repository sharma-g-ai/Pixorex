# Pixorex mobile app (technicians)

Flutter app for field technicians (Android 10+, iOS 16+). Screens follow the canvas `Mobile-*` artboards; API rules are in [docs/mobile-api.md](../docs/mobile-api.md).

**Built so far:** launch, Sign in (phone or email), Activate from invite, Invite expired / used / cancelled, and a temporary signed-in screen. The code entry, resend and 30-minute lock pages are Keycloak's own pages in the system browser (`keycloak/themes/pixorex`).

## Run on an Android phone (USB)

1. Start the backend from the repo root: [docs/local-setup.md](../docs/local-setup.md).
2. Phone: Developer options, USB debugging on, plugged in, "Allow" tapped. `adb devices` lists it as `device`.
3. Let the phone reach the laptop's `localhost` over the cable (redo after replugging):
   ```bash
   adb reverse tcp:8000 tcp:8000
   adb reverse tcp:8080 tcp:8080
   ```
4. Run:
   ```bash
   flutter run --dart-define=API_BASE_URL=http://localhost:8000/api/v1 --dart-define=KEYCLOAK_ISSUER=http://localhost:8080/realms/pixorex
   ```
5. Sign in as `dual@demo.local` or `tech1@demo.local` (phone numbers in docs/mobile-api.md §1). Codes, including SMS, arrive in Mailpit on the laptop: http://localhost:8025. Keycloak allows 5 codes per user per 15 minutes.

Without `--dart-define` the app uses `10.0.2.2` (the host as seen from the Android emulator).

**Invite link (provisional):** the link format is not decided (handover §2). Debug builds also open the local email's `http://localhost:5173/activate#token=…` link (add `adb reverse tcp:5173 tcp:5173`). Android shows an "Open with" chooser the first time: pick **More → Pixorex**, tick **Don't ask again**. In Gmail, turn off "Open web links in Gmail". The app also opens `pixorex://activate#token=…`:
```bash
adb shell "am start -a android.intent.action.VIEW -d 'pixorex://activate#token=<token>' com.pixorex.mobile"
```

## Tests

```bash
flutter analyze
flutter test
```

## Notes

- Tokens live only in the Keychain / Keystore (`flutter_secure_storage`). Token handling is A0: architect sign-off needed (CONSTITUTION §5).
- `MainActivity` must not have `android:taskAffinity=""` (the Flutter template default): it sends Keycloak's redirect to a separate task and sign-in never completes.
- `MainActivity` is `singleTask`: an invite link opened from another app must reuse the running app, or Keycloak's redirect lands in the other copy and sign-in never completes.
- Some phones (seen on Realme) kill the app while the sign-in browser is open. The app notes the pending sign-in (no tokens) and, if it restarts within 10 minutes, resumes it; Keycloak's session cookie finishes it without a new code.
- Plain `http` is allowed in debug builds only (`android/app/src/debug/AndroidManifest.xml`).
- App icon: `dart run flutter_launcher_icons` regenerates it from `assets/pixorex_icon.png`.
- IBM Plex Sans (SIL Open Font License) is bundled under `assets/fonts`.
