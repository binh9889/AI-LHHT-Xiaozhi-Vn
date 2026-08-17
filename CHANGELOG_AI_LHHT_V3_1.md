# AI-LHHT v3.1.0 Voice Pro – Live Interpreter

## Mục tiêu
Bản 3.1 tập trung vào hai vấn đề thực tế của v3.0:

1. OTA Xiaozhi không trả mã 6 số mà chỉ trả credential thử nghiệm.
2. Phiên dịch phải chạy trực tiếp ngay trong cuộc trò chuyện, hai chiều Việt ↔ Anh (và các cặp phổ biến khác), không bắt người dùng vào một form dịch riêng.

## Xiaozhi provisioning
- Đổi payload OTA sang cấu trúc tối thiểu `application` + `board` giống ví dụ OTA của server Xiaozhi mã nguồn mở.
- Giữ `Device-Id`, `Client-Id`, `Content-Type: application/json`, `Activation-Version: 1`.
- Không giả mạo Serial-Number/HMAC eFuse.
- Parser lấy trực tiếp `activation.code` nếu server cấp.
- Mã 6 số có nút sao chép và nút kiểm tra lại sau khi liên kết.
- `test-token/GID_test` chỉ được xem là diagnostic; không được lưu thành cấu hình production.
- Hiển thị profile request để chẩn đoán.

## Phiên dịch trực tiếp trong Chat
Có thể nói hoặc nhập:

- `Mở phiên dịch Anh Việt`
- `Bật phiên dịch Việt Anh`
- `Mở phiên dịch Việt Trung`
- `Tắt phiên dịch`

Khi bật:
- banner phiên dịch xuất hiện ngay trong Chat;
- mỗi câu STT được chặn khỏi luồng trả lời Agent bình thường;
- app tự xác định câu đang là ngôn ngữ A hay B;
- dịch sang chiều còn lại;
- tự phát giọng bản dịch;
- câu gốc và bản dịch vẫn xuất hiện trong lịch sử trò chuyện.

Có thêm nút Translate trên AppBar để bật/tắt bằng tay.

## Màn hình Phiên dịch AI
- Thêm chế độ hai chiều trực tiếp.
- Tự động phát bản dịch.
- Dùng Xiaozhi như ASR.
- Nếu có MiniMax/Dify thì ưu tiên backend API để không gián đoạn WebSocket audio.
- Nếu chỉ có Xiaozhi, tái sử dụng chính kết nối Xiaozhi đang mở, không tạo hai kết nối cùng Device-ID.

## Voice pipeline
- Sau khi nhận STT ở chế độ phiên dịch, app gửi abort để ngăn Agent trả lời nội dung câu nói.
- Backend dịch tạo đúng bản dịch, không trả lời câu hỏi.
- Với Việt ↔ Anh và các cặp có script đặc trưng, chiều dịch được xác định cục bộ để Xiaozhi chỉ đọc bản dịch, không đọc JSON kỹ thuật.

## Android/build
- Version: `3.1.0+310`.
- Kotlin Gradle Plugin: `2.1.20`.
- APK output: `AI-LHHT-v3.1.0-Voice-Pro-Live-Interpreter-VI.apk`.
