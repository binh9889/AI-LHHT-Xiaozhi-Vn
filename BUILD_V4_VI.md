# Build AI-LHHT v4.1.0

## Version

```text
4.1.0+410
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
  test/realtime_tool_engine_local_test.dart
flutter build apk --debug --build-name=4.0.1 --build-number=401
```

APK mục tiêu:

```text
AI-LHHT-v4.1.0-Realtime-Tools-Pro-VI.apk
```

GitHub Actions `.github/workflows/build-vi-apk.yml` chạy tự động khi push lên `develop-v4`.

## Release gate

Không gọi release là compile PASS nếu `flutter analyze`, tests hoặc `flutter build apk` chưa chạy thành công. Source package này chỉ có thể xác nhận static source checks trong môi trường đóng gói hiện tại.
