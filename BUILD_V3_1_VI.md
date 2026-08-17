# Build AI-LHHT v3.1.0

Branch khuyến nghị: `develop-v3`.

Sau khi thay source:

```bash
git add -A
git commit -m "Upgrade AI-LHHT to v3.1 Live Interpreter"
git push origin develop-v3
```

Workflow `.github/workflows/build-vi-apk.yml` tự chạy khi push vào `develop-v3`, hoặc có thể chạy bằng `workflow_dispatch`.

Pipeline:
1. Flutter pub get
2. Flutter analyze
3. widget/unit tests
4. patch namespace plugin PCM
5. build debug APK
6. SHA256
7. upload artifact

APK:
`AI-LHHT-v3.1.0-Voice-Pro-Live-Interpreter-VI.apk`

## Test bắt buộc sau cài APK

### OTA
1. Cài đặt → Xiaozhi → Kết nối Xiaozhi chính thức.
2. Bấm `Lấy cấu hình / mã liên kết`.
3. Nếu response có `activation.code`, nhập 6 số vào xiaozhi.me → Robot → Thiết bị.
4. Quay lại app, bấm kiểm tra lại.
5. Nếu vẫn chỉ có `test-token/GID_test`, server chưa cấp activation cho danh tính Android này; app không tự tạo mã giả.

### Phiên dịch trực tiếp
1. Mở cuộc trò chuyện Xiaozhi.
2. Nói: `Mở phiên dịch Anh Việt`.
3. Nói tiếng Việt → phải phát tiếng Anh.
4. Người đối diện nói tiếng Anh → phải phát tiếng Việt.
5. Nói: `Tắt phiên dịch` để về Agent bình thường.
