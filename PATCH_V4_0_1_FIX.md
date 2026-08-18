# AI-LHHT v4.0.1+401 – Build Stability Fix

Patch này xử lý đúng 3 test fail quan sát trong GitHub Actions của v4.0.0:

1. `tool_intent_router_test.dart` – cụm tiếng Việt có dấu có thể rơi khỏi Tool Router do `\b` của RegExp không an toàn với ranh giới Unicode tiếng Việt.
2. `realtime_tool_engine_local_test.dart` – local lunar tool không nên phụ thuộc persistent provider config / SharedPreferences.
3. `realtime_tool_engine_local_test.dart` – area code / carrier local tools cũng phải chạy được khi storage platform chưa sẵn sàng.

## Sửa production code

- ToolIntentRouter thử regex strict, sau đó fallback bỏ ASCII word-boundary marker để bắt đúng `xổ số`, `thời tiết`, `giá vàng`, `tin tức`, v.v.
- RealtimeToolEngine bypass provider config đối với 4 local-only tools: lunar, area code, carrier, plate lookup.
- ToolProviderConfigStore.load() fallback về config mặc định nếu SharedPreferences tạm thời không khả dụng.
- Unit test local engine dùng `SharedPreferences.setMockInitialValues` để deterministic.
- Thêm regression test cho các cụm tiếng Việt có dấu.

## Version

`4.0.1+401`

## APK mục tiêu

`AI-LHHT-v4.0.1-Realtime-Tools-Pro-VI.apk`

## Xác minh hiện tại

- `scripts/verify_v4.sh --static-only`: PASS trong môi trường đóng gói.
- ZIP integrity: kiểm tra khi đóng gói.
- Flutter analyze/test/build: cần GitHub Actions xác nhận vì môi trường đóng gói này không có Flutter SDK.
