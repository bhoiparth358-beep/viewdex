# Viewdex

Viewdex is a Flutter file manager and viewer for browsing files and opening common image, video, audio, PDF, archive, and text formats from one app.

## Features

- Browse files and folders; create, rename, delete, sort, and multi-select items.
- Search files by name and filter by file category.
- Open images with zoom and pan controls.
- Play video and audio files.
- Read PDFs and preview supported archive contents.
- View text and source files with syntax highlighting.
- Keep a favorites and recent-files library.
- Switch between light, dark, and system themes.
- Open supported Office documents with an installed system app.

## Built with

- Flutter and Dart
- Material 3
- Riverpod for state management
- GoRouter for navigation
- `pdfrx` for PDF viewing

## Getting started

Install the Flutter SDK (Dart SDK constraint: `^3.8.0`), then run:

```sh
flutter pub get
flutter run
```

Choose a target device or emulator supported by your Flutter installation.

## Android APK

This repository includes a GitHub Actions workflow that analyzes the project, runs tests, builds a universal release APK and split ABI APKs, and uploads them as workflow artifacts. To build locally:

```sh
flutter build apk --release
```

After a workflow run completes, download the APK from that run's **Artifacts** section in GitHub Actions.

## Project structure

```text
lib/
  app/       App setup, routing, and theme
  core/      Shared services, errors, logging, and file detection
  features/  File manager and file-type viewer features
  shared/    Reusable widgets
test/        Flutter tests
```

## License

No license has been added yet. All rights reserved unless a license is added to this repository.
