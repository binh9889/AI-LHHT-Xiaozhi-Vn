# AI-LHHT v3.4 — In-App Music & Reliable Tools

Bản này tập trung sửa lỗi runtime được ghi nhận sau v3.3:

- Không dùng `listen/detect` như general text chat Xiaozhi nữa.
- Normal voice chat gửi audio thật tới Xiaozhi; STT cloud chỉ được dùng để hiển thị và bắt local intent.
- `mã thiết bị` trả trực tiếp từ cấu hình app.
- Xổ số chạy local realtime tool với 2 nguồn + retry.
- Nhạc online mở và phát trong WebView của AI-LHHT, không gọi app YouTube ngoài.
- Phiên dịch Android có fallback Google ML Kit on-device; không mở thêm Xiaozhi WebSocket để dịch text.
- Việt ↔ Trung vẫn khóa ASR theo lượt và TTS theo ngôn ngữ đích.

## Lưu ý nhạc
AI-LHHT không trích xuất luồng audio từ YouTube/nhà cung cấp. Với cấu hình không có API key của nhà cung cấp, app mở trang kết quả trong trình phát web tích hợp và người dùng chọn bài để phát trong app. Muốn tìm chính xác + autoplay hoàn toàn bằng giọng nói cần cấu hình API chính thức của nhà cung cấp phù hợp.

## Trạng thái
Source checks đã PASS trong môi trường đóng gói. Flutter compile/runtime phải được GitHub Actions và thiết bị thật xác nhận trước khi gọi production-ready.
