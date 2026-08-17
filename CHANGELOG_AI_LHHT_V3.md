# AI-LHHT v3.0 Voice Pro — Thay đổi chính

## Giao diện
- Viết lại Home/Tin nhắn theo Material 3, responsive, tìm kiếm hội thoại thật.
- Viết lại thẻ hội thoại để tránh tràn tên Agent/tag/thời gian.
- Viết lại Khám phá bằng SliverGrid responsive 2/3/4 cột.
- Viết lại Cài đặt: bỏ 4 tab ngang gây overflow; chuyển thành danh mục dịch vụ.
- Light/Dark mode hoàn chỉnh ở cấp ThemeData.
- Header chat dùng Expanded + ellipsis để không đè tên Agent lên nút gọi.
- Chuẩn hóa nhiều thông báo lỗi người dùng sang tiếng Việt.

## Phiên dịch AI
- Màn hình Phiên dịch AI mới.
- Dịch văn bản đa ngôn ngữ.
- Voice input: dùng STT/ASR từ kết nối Xiaozhi hiện có.
- Tự dịch sau khi nhận transcript.
- TTS đọc bản dịch bằng giọng hệ thống qua flutter_tts.
- Đổi chiều ngôn ngữ nhanh.
- Chế độ dịch hội thoại tự nhiên.
- Backend tự chọn theo thứ tự: MiniMax → Dify → Xiaozhi.

Ngôn ngữ giao diện có sẵn:
- Auto detect
- Tiếng Việt
- English
- 中文
- 日本語
- 한국어
- Français
- Deutsch
- Español
- ไทย
- Русский

## Voice / ASR
- Thêm VietnameseTranscriptNormalizer.
- Chỉ sửa các nhầm lẫn có độ tin cậy cao khi có ngữ cảnh rõ, ví dụ “sổ xố / sửa sổ” → “xổ số”.
- Trong chat Xiaozhi, khi transcript được sửa, app gửi abort để ngắt phản hồi dựa trên transcript sai rồi gửi lại text đã chuẩn hóa.
- Không áp dụng correction rộng để tránh tự ý thay đổi câu nói đúng.

## Xiaozhi
- Giữ OTA/provisioning v2.2.
- Bỏ tạo test-token mặc định cho cấu hình mới.
- WebSocket không còn tự gửi Bearer test-token khi token rỗng.
- Token được mask trong UI mới.
- Thêm trang Chẩn đoán hệ thống với test WebSocket và pipeline MIC → VAD → ASR → Agent → TTS.

## CI / Build
- Version: 3.0.0+300.
- Workflow: Build AI-LHHT v3 Voice Pro APK.
- flutter pub get
- flutter analyze
- UI/unit tests
- build debug APK
- SHA-256
- Artifact: AI-LHHT-v3.0.0-Voice-Pro-VI.apk

## Giới hạn cần hiểu đúng
- Chất lượng ASR nền vẫn phụ thuộc dịch vụ Xiaozhi/server đang dùng; app chỉ thêm correction an toàn cho một số lỗi rõ ràng.
- Phiên dịch giọng nói cần cấu hình Xiaozhi để lấy STT và ít nhất một backend AI hợp lệ (MiniMax/Dify/Xiaozhi).
- Kết quả xổ số “hôm nay” vẫn cần Tool/MCP/API realtime ở phía Agent/server; knowledge base tĩnh không thể tự cập nhật dữ liệu realtime.
