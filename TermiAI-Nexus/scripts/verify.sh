#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found. Install Flutter stable, then rerun this script." >&2
  exit 2
fi
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
printf '\nAPK: %s\n' "$ROOT/build/app/outputs/flutter-apk/app-debug.apk"
