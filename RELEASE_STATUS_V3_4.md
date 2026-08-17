# RELEASE STATUS — AI-LHHT v3.4.0

## Đã triển khai trong source
- [x] In-app online music WebView
- [x] Normal Xiaozhi audio flow
- [x] Local device-info tool
- [x] Lottery multi-source + retry
- [x] Interpreter locale-locked ASR
- [x] Target-locale TTS
- [x] Android ML Kit translation fallback
- [x] Kotlin 2.1.20
- [x] GitHub Actions build/test workflow

## Chưa được phép gọi PASS trước CI/device test
- [ ] `flutter pub get` trên CI
- [ ] `flutter analyze`
- [ ] Flutter unit/widget tests
- [ ] Android APK compile
- [ ] WebView playback trên điện thoại thật
- [ ] Xiaozhi cloud voice roundtrip trên tài khoản thật
- [ ] `vi-VN` / `zh-CN` recognizer trên máy người dùng
- [ ] ML Kit model download + translation trên máy thật

Không tuyên bố bản phát hành production hoàn chỉnh cho đến khi các mục runtime trên được kiểm tra.
