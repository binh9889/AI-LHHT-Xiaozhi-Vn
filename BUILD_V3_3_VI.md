# Build AI-LHHT v3.3.0

## GitHub Actions
Workflow: `.github/workflows/build-vi-apk.yml`

Workflow tự chạy khi push `develop-v3` hoặc có thể chạy thủ công.

Các bước bắt buộc:
1. `flutter pub get`
2. `flutter analyze --no-fatal-infos --no-fatal-warnings`
3. Unit/widget tests, gồm tool realtime và interpreter turn controller
4. `flutter build apk --debug --build-name=3.3.0 --build-number=330`
5. SHA-256
6. Upload Artifact

APK:
`AI-LHHT-v3.3.0-Voice-Pro-Online-Tools-Bilingual-VI.apk`

## Test sau khi cài

### Xổ số
Nói: `Kiểm tra kết quả xổ số miền Bắc hôm nay`.
App phải trả dữ liệu online hoặc nói rõ nguồn chưa cập nhật ngày hôm nay. Không được trả `không có công cụ`.

### Nhạc
Nói: `Bật nhạc` → app hỏi tên bài/ca sĩ.
Nói tiếp: `Ca sĩ Lê Bảo Bình` → app mở kết quả tìm kiếm online trên YouTube Music. Không được dùng kho local 5 bài.

### Việt ↔ Trung
Nói: `Mở phiên dịch Việt Trung`.
- Banner phải hiện `Đang nghe: Tiếng Việt → nói 中文`.
- Nói tiếng Việt → transcript tiếng Việt → dịch Trung → có TTS Trung.
- Sau đó banner đổi `Đang nghe: 中文 → nói Tiếng Việt`.
- Khách nói tiếng Trung → ASR chạy `zh-CN` → dịch Việt → có TTS Việt.
- Nếu máy không hỗ trợ `zh-CN`, Diagnostics phải báo `中文: thiếu`; cài Speech Services/ngôn ngữ Trung trên Android rồi test lại.
