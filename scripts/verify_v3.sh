#!/usr/bin/env bash
set -euo pipefail

echo '== AI-LHHT v3.3 source checks =='
grep -q '^version: 3.3.0+330$' pubspec.yaml
grep -q 'speech_to_text: ^7.4.0' pubspec.yaml
grep -q 'url_launcher: ^6.3.2' pubspec.yaml
test -f lib/screens/interpreter_screen.dart
test -f lib/screens/diagnostics_screen.dart
test -f lib/services/translation_service.dart
test -f lib/services/native_speech_service.dart
test -f lib/services/realtime_tool_service.dart
test -f lib/utils/interpreter_turn_controller.dart
test -f test/interpreter_turn_controller_test.dart
test -f test/realtime_tool_service_test.dart
! grep -R "Bearer test-token" lib/services/xiaozhi_websocket_manager.dart
grep -q 'version "2.1.20"' android/settings.gradle.kts
grep -q 'android.speech.RecognitionService' android/app/src/main/AndroidManifest.xml
grep -q 'NSSpeechRecognitionUsageDescription' ios/Runner/Info.plist
grep -q 'sendTextMessageSilently' lib/services/xiaozhi_service.dart
grep -q 'music.youtube.com' lib/services/realtime_tool_service.dart
grep -q 'vietnam-lottery-xsmb-analysis' lib/services/realtime_tool_service.dart
grep -q 'Đang nghe:' lib/screens/chat_screen.dart

echo 'Static source checks: PASS'

if command -v flutter >/dev/null 2>&1; then
  flutter pub get
  flutter analyze --no-fatal-infos --no-fatal-warnings
  flutter test \
    test/widget_test.dart \
    test/minimax_test.dart \
    test/pcm_frame_buffer_test.dart \
    test/xiaozhi_websocket_manager_test.dart \
    test/interpreter_turn_controller_test.dart \
    test/realtime_tool_service_test.dart
  echo 'Flutter checks: PASS'
else
  echo 'Flutter SDK not found; compile checks must run in GitHub Actions.'
fi
