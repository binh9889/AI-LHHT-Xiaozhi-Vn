# Build AI-LHHT v3.2.0

Branch khuyến nghị: `develop-v3`

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test test/widget_test.dart test/minimax_test.dart test/pcm_frame_buffer_test.dart test/xiaozhi_websocket_manager_test.dart
flutter build apk --debug --build-name=3.2.0 --build-number=320
```

APK mục tiêu:
`AI-LHHT-v3.2.0-Voice-Pro-Real-Connect-VI.apk`

## Acceptance test kết nối
1. OTA nhận Device-ID/Client-ID ổn định.
2. Nếu có mã 6 số, bind trên xiaozhi.me.
3. Bấm kiểm tra lại OTA.
4. Bấm **Kiểm tra kết nối Agent thật**.
5. PASS chỉ khi server trả hello WebSocket hợp lệ trong 10 giây.
6. Sau PASS mới lưu Agent.

## Acceptance test mic
Nói tối thiểu 10 câu tiếng Việt có phụ âm gần nhau, ví dụ:
- tra kết quả xổ số miền Bắc hôm nay
- mở phiên dịch Anh Việt
- hôm nay thời tiết ở Hà Nội thế nào
- đặt lời nhắc lúc tám giờ sáng
- tôi muốn nghe một bài nhạc nhẹ

Ghi lại RAW STT để so sánh với v3.1. Không gọi PASS chỉ vì một câu nhận đúng.
