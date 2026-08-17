#!/usr/bin/env bash
set -euo pipefail

echo '== AI-LHHT v3 source checks =='
grep -q '^version: 3.0.0+300$' pubspec.yaml
grep -q 'flutter_tts:' pubspec.yaml
test -f lib/screens/interpreter_screen.dart
test -f lib/screens/diagnostics_screen.dart
test -f lib/services/translation_service.dart
test -f lib/utils/vietnamese_transcript_normalizer.dart
! grep -R "Bearer test-token" lib/services/xiaozhi_websocket_manager.dart

echo 'Static source checks: PASS'

if command -v flutter >/dev/null 2>&1; then
  flutter pub get
  flutter analyze --no-fatal-infos --no-fatal-warnings
  flutter test test/widget_test.dart test/minimax_test.dart
  echo 'Flutter checks: PASS'
else
  echo 'Flutter SDK not found; compile checks must run in GitHub Actions.'
fi
