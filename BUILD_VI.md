# AI-LHHT / Xiaozhi Android 2.1.0 – hướng dẫn build

## Thay đổi chính
- Thêm màn hình **Kết nối Xiaozhi chính thức**.
- Gọi OTA/provisioning trước WebSocket.
- Tự tạo và lưu Device-ID dạng MAC local + Client-ID ổn định.
- Nếu OTA trả `activation.code`, app hiển thị mã để nhập tại xiaozhi.me.
- Nếu server chỉ trả `test-token`/`GID_test`, app báo rõ đây là chế độ test và không giả vờ đã bind Agent.
- Có thể lưu WebSocket/token server trả về và dùng lại trong hội thoại.
- Giữ chế độ cấu hình Xiaozhi thủ công hiện có.

## Build APK
Yêu cầu Flutter tương thích Dart >=3.7.

```bash
flutter pub get
flutter analyze
flutter build apk --debug
```

APK debug nằm tại:
`build/app/outputs/flutter-apk/app-debug.apk`

Bản release:
```bash
flutter build apk --release
```

## Cách thử
1. Cài APK.
2. Mở Cài đặt → Xiaozhi → **Xiaozhi chính thức**.
3. Chọn **Lấy cấu hình / mã liên kết**.
4. Nếu có mã 6 số: xiaozhi.me → Robot → Thiết bị → Liên kết thiết bị mới → nhập mã.
5. Quay lại app và chạy provisioning lần nữa.
6. Lưu cấu hình rồi tạo hội thoại.

## Lưu ý về xiaozhi.me
Server chính thức có thể trả `test-token` cho danh tính thiết bị Android/không được hỗ trợ và không trả `activation`. Khi đó app vẫn test được WebSocket, nhưng không thể tự ép server gắn điện thoại vào Agent. Đây là giới hạn server-side.
