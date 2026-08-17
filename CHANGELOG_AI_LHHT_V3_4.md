# CHANGELOG — AI-LHHT v3.4.0

## Voice / Xiaozhi
- Normal chat dùng audio WebSocket Xiaozhi thay vì native ASR + fake text `listen/detect`.
- Không gửi lại transcript STT lên Xiaozhi khi server đã nhận chính audio của lượt đó.
- Giảm lỗi timeout lặp lại do duplicate/fake text flow.
- Local intent có thể abort/suppress Agent cloud khi app đã tự xử lý.

## Local device data
- `mã thiết bị`, `Device-ID`, `Client-ID`, `MAC`, `thông tin thiết bị` trả ngay trong app.
- Không gửi những câu này lên Agent rồi chờ timeout.

## Nhạc online trong app
- Bỏ hành vi mở ứng dụng YouTube ngoài AI-LHHT.
- Thêm `MusicPlayerScreen` dùng WebView trong app.
- Tìm catalog để chuẩn hóa tên bài/ca sĩ; playback provider hiển thị bên trong app.
- Không dùng kho nhạc 5 bài local.
- Không trích xuất hoặc tải stream từ nhà cung cấp.

## Xổ số realtime
- Nhận cả lỗi ASR thường gặp: `xổ số`, `sổ xố`, `sổ số`, `xổ xố`, `XSMB`.
- Hai nguồn dữ liệu CSV cộng đồng.
- Retry khi server 5xx hoặc mạng chập chờn.
- Cache kết quả gần nhất trong phiên với nhãn rõ ràng.

## Phiên dịch
- Loại Xiaozhi text-injection khỏi fallback dịch.
- Android tích hợp Google ML Kit Translation native `17.0.3` qua MethodChannel.
- MiniMax/Dify vẫn được ưu tiên khi đã cấu hình; nếu lỗi sẽ fallback ML Kit.
- Model ngôn ngữ ML Kit tải theo yêu cầu ở lần đầu.
- Không tạo thêm WebSocket Xiaozhi chỉ để phiên dịch.

## Build
- Version `3.4.0+340`.
- Workflow build/test v3.4.
