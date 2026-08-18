# Build AI-LHHT v4.1.2

## Version

```text
4.1.2+412
```

## Kiểm tra tĩnh

```bash
bash scripts/verify_v4.sh --static-only
```

## Kiểm tra đầy đủ khi có Flutter SDK

```bash
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
  test/vietnamese_transcript_normalizer_test.dart \
  test/response_text_sanitizer_test.dart \
  test/realtime_tool_engine_local_test.dart
flutter build apk --debug --build-name=4.1.2 --build-number=412
```

APK mục tiêu:

```text
AI-LHHT-v4.1.2-Native-Voice-Weather-Clean-Pro-VI.apk
```

GitHub Actions `.github/workflows/build-vi-apk.yml` chạy tự động khi push lên `develop-v4`.

## Release gate

Không gọi release là compile PASS nếu `flutter analyze`, tests hoặc `flutter build apk` chưa chạy thành công. Source package này chỉ có thể xác nhận static source checks trong môi trường đóng gói hiện tại.
