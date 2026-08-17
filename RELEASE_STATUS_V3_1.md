# Release status v3.1.0

## Đã kiểm tra trong gói tạo source
- Cấu trúc file: PASS
- Cân bằng ngoặc các file Dart sửa chính: PASS
- Version 3.1.0+310: PASS
- Kotlin plugin 2.1.20: PASS
- Workflow output v3.1: PASS
- Không lưu test-token thành production config trong màn OTA: PASS

## Chưa thể khẳng định trước GitHub Actions
- `flutter analyze`: cần runner Flutter
- `flutter test`: cần runner Flutter
- `flutter build apk`: cần runner Flutter/Android SDK
- OTA server có thực sự cấp `activation.code`: phụ thuộc phản hồi server với Device-ID/Client-ID thật
- TTS/ASR end-to-end trên điện thoại: cần test thiết bị thật

Không gọi bản này là release production cho đến khi workflow xanh và smoke test trên điện thoại PASS.
