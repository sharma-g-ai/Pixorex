# Pixorex

Pixorex digitizes industrial asset labels and delivery notes. The delivery-note
module scans and checks DN pages, then verifies arriving stock in a consolidated
receiving list with live can-article scanning, saved counters, batch additions,
and quantity editing. In the receiving list, tap **Scan can article number**
or the scanner icon to identify the can against the current DN, then explicitly
add one can. Android build 36 introduces this camera flow.

## Branding

The app uses the supplied Pixorex primary full-color app icon and wordmarks.
Palette and asset paths are defined in `lib/branding/app_brand.dart`. Launcher
icons are generated with `dart run flutter_launcher_icons`; its configuration
is in `pubspec.yaml`. Android and iOS launch screens use the same navy branding.

Native app IDs and OCR method-channel names are retained for upgrade and saved
data compatibility. The public app name is Pixorex across platform metadata.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
