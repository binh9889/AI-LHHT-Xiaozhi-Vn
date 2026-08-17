# RELEASE STATUS – v3.3.0

## Đã thực hiện trong source
- [x] Tool XSMB online trong APK
- [x] Online music search + mở provider ngoài
- [x] Native speech recognizer singleton
- [x] Khóa locale theo lượt phiên dịch
- [x] Việt ↔ Trung không dùng auto direction từ transcript
- [x] TTS local theo target locale
- [x] Xiaozhi translation silent mode
- [x] Android RecognitionService query
- [x] iOS speech recognition permission
- [x] Diagnostics vi-VN / zh-CN
- [x] Tests cho tool router và turn controller
- [x] Workflow build v3.3

## Chưa được tuyên bố PASS trong môi trường đóng gói
Môi trường đóng gói không có Flutter SDK, vì vậy compile/test thật phải do GitHub Actions xác nhận.

Không được gọi build là hoàn chỉnh cho đến khi GitHub Actions xanh và test trên điện thoại thật đạt các ca kiểm thử trong `BUILD_V3_3_VI.md`.
