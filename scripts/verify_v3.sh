#!/usr/bin/env bash
set -euo pipefail

echo '== AI-LHHT v3.4 source checks =='
grep -q '^version: 3.4.0+340$' pubspec.yaml
grep -q 'speech_to_text: ^7.4.0' pubspec.yaml
grep -q 'webview_flutter: ^4.13.0' pubspec.yaml
test -f lib/screens/interpreter_screen.dart
test -f lib/screens/diagnostics_screen.dart
test -f lib/screens/music_player_screen.dart
test -f lib/services/translation_service.dart
test -f lib/services/native_speech_service.dart
test -f lib/services/realtime_tool_service.dart
test -f lib/utils/interpreter_turn_controller.dart
test -f test/interpreter_turn_controller_test.dart
test -f test/realtime_tool_service_test.dart
test -f test/pcm_frame_buffer_test.dart
test -f test/xiaozhi_websocket_manager_test.dart
! grep -R "Bearer test-token" lib/services/xiaozhi_websocket_manager.dart
grep -q 'version "2.1.20"' android/settings.gradle.kts
grep -q 'android.speech.RecognitionService' android/app/src/main/AndroidManifest.xml
grep -q 'com.google.mlkit:translate:17.0.3' android/app/build.gradle.kts
grep -q 'mlkit_translation' android/app/src/main/kotlin/com/lhht/ai_assistant/MainActivity.kt
grep -q 'ML Kit trên máy' lib/services/translation_service.dart
grep -q 'm.youtube.com' lib/services/realtime_tool_service.dart
grep -q 'MusicPlayerScreen' lib/screens/chat_screen.dart
grep -q 'vietnam-lottery-xsmb-analysis' lib/services/realtime_tool_service.dart
grep -q 'AnhTuPhi/xsmb-vietnam-lottery-analysis' lib/services/realtime_tool_service.dart
grep -q 'fromXiaozhiStt' lib/screens/chat_screen.dart
! grep -q '_xiaozhiService!\.sendTextMessage(text)' lib/screens/chat_screen.dart
! grep -q 'Yêu cầu hết thời gian chờ' lib/services/xiaozhi_service.dart
grep -q 'Hãy giữ mic để nói' lib/screens/chat_screen.dart

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
