#!/usr/bin/env bash
set -euo pipefail

STATIC_ONLY="${1:-}"

echo '== AI-LHHT v4.1.0 Voice Stability Pro source checks =='
grep -q '^version: 4.1.0+410$' pubspec.yaml
grep -q "static const String appVersion = '4.1.0';" lib/services/xiaozhi_provisioning_service.dart
grep -q 'version "2.1.20"' android/settings.gradle.kts
grep -q 'android.speech.RecognitionService' android/app/src/main/AndroidManifest.xml
grep -q 'com.google.mlkit:translate:17.0.3' android/app/build.gradle.kts

test -f lib/tools/models/tool_models.dart
test -f lib/tools/tool_registry.dart
test -f lib/tools/services/tool_intent_router.dart
test -f lib/tools/services/realtime_tool_engine.dart
test -f lib/tools/services/tool_provider_config.dart
test -f lib/tools/providers/public_data_providers.dart
test -f lib/screens/realtime_tools_screen.dart
test -f lib/screens/tool_detail_screen.dart
test -f lib/screens/tool_provider_settings_screen.dart
test -f lib/screens/music_player_screen.dart
test -f lib/screens/interpreter_screen.dart
test -f lib/screens/diagnostics_screen.dart
test -f lib/screens/voice_output_settings_screen.dart
test -f test/tool_registry_test.dart
test -f test/tool_intent_router_test.dart
test -f test/realtime_tool_engine_local_test.dart
test -f test/vietnamese_transcript_normalizer_test.dart
test -f README_V4_VI.md
test -f BUILD_V4_VI.md
test -f CHANGELOG_AI_LHHT_V4.md
test -f RELEASE_STATUS_V4.md
test -f V4_ARCHITECTURE_AUDIT.md
test -f V4_MIGRATION_PLAN.md
test -f V4_SPRINT_PLAN.md

grep -q "id: 'weather'" lib/tools/tool_registry.dart
grep -q "id: 'air_quality'" lib/tools/tool_registry.dart
grep -q "id: 'crypto_price'" lib/tools/tool_registry.dart
grep -q "id: 'news_latest'" lib/tools/tool_registry.dart
grep -q "id: 'sports_score'" lib/tools/tool_registry.dart
grep -q 'api.open-meteo.com' lib/tools/providers/public_data_providers.dart
grep -q 'air-quality-api.open-meteo.com' lib/tools/providers/public_data_providers.dart
grep -q 'api.frankfurter.dev' lib/tools/providers/public_data_providers.dart
grep -q 'data-api.binance.vision' lib/tools/providers/public_data_providers.dart
grep -q 'vnexpress.net/rss' lib/tools/providers/public_data_providers.dart
grep -q 'thesportsdb.com' lib/tools/providers/public_data_providers.dart
grep -q 'RealtimeToolEngine _toolEngine' lib/screens/chat_screen.dart
grep -q 'RealtimeToolsScreen' lib/widgets/discovery_screen.dart
! grep -R "Bearer test-token" lib/services/xiaozhi_websocket_manager.dart
! grep -q '_xiaozhiService!\.sendTextMessage(text)' lib/screens/chat_screen.dart


grep -q 'class UnifiedSpeechOutputService' lib/services/unified_speech_output_service.dart
grep -q 'beginResponseGate' lib/services/xiaozhi_service.dart
grep -q 'releaseResponseGate' lib/services/xiaozhi_service.dart
grep -q 'miền' lib/utils/vietnamese_transcript_normalizer.dart
grep -q 'mắt|mắc|bắt|bát|bắc' lib/utils/vietnamese_transcript_normalizer.dart
echo 'Static source checks: PASS'

if [ "$STATIC_ONLY" = "--static-only" ]; then
  exit 0
fi

if command -v flutter >/dev/null 2>&1; then
  flutter pub get
  flutter analyze --no-fatal-infos --no-fatal-warnings
  flutter test \
    test/widget_test.dart \
    test/minimax_test.dart \
    test/pcm_frame_buffer_test.dart \
    test/xiaozhi_websocket_manager_test.dart \
    test/interpreter_turn_controller_test.dart \
    test/realtime_tool_service_test.dart \
    test/tool_registry_test.dart \
    test/tool_intent_router_test.dart \
    test/realtime_tool_engine_local_test.dart
  echo 'Flutter checks: PASS'
else
  echo 'Flutter SDK not found; compile checks must run in GitHub Actions.'
fi
