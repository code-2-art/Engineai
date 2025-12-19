# enginai

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Web Persistence

When running `flutter run -d chrome`, a temporary Chrome profile is created, meaning local data (Hive, SharedPreferences) is lost between restarts.

To persist data during development:

1. Run with a fixed port:
   ```bash
   flutter run -d chrome --web-port=8080
   ```
2. Open [http://localhost:8080](http://localhost:8080) in your *primary* Chrome browser (not the automated instance).

Data will now persist in your browser's local storage.

## macos
   ```bash
   flutter run -d macos
   ```


