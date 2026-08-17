# AI-LHHT v2.2.0 VI - Build & Xiaozhi official provisioning

## Điểm sửa quan trọng

- OTA/provisioning dùng `POST https://api.tenclass.net/xiaozhi/ota/`.
- Gửi `Content-Type: application/json`, `Device-Id`, `Client-Id`, `User-Agent`, `Accept-Language`.
- Dùng `Activation-Version: 1` trên Android.
- KHÔNG tạo Serial-Number/HMAC giả. Firmware Xiaozhi chính thức chỉ dùng Activation-Version 2 khi thiết bị có serial + khóa HMAC/eFuse thật.
- Body JSON bám cấu trúc `Board::GetSystemInfoJson()` của firmware chính thức, nhưng các giá trị ESP-only không được giả mạo.
- Lưu riêng `Client-Id` và dùng đúng `Client-Id` trong WebSocket handshake.
- Fix lỗi cấu hình thủ công trước đây nhập token nhưng không lưu token.
- Không log token thật ra console.
- Workflow build tạo `AI-LHHT-v2.2.0-VI.apk`.

## Build trên GitHub Actions

1. Upload/commit toàn bộ source lên branch `main`.
2. Vào **Actions** -> **Build AI-LHHT Vietnamese APK**.
3. Chọn **Run workflow** -> branch `main`.
4. Khi job xanh, tải artifact `AI-LHHT-v2.2.0-VI`.
5. Giải nén để lấy `AI-LHHT-v2.2.0-VI.apk`.

## Test liên kết Xiaozhi

1. Cài APK mới.
2. Mở **Cài đặt -> Xiaozhi -> Kết nối Xiaozhi chính thức**.
3. Bấm **Lấy cấu hình / mã liên kết**.
4. Nếu có `activation.code`, nhập 6 số tại `xiaozhi.me -> Robot -> Thiết bị -> Liên kết thiết bị mới`.
5. Sau khi liên kết, bấm lại **Lấy cấu hình / mã liên kết** để nhận WebSocket URL/token rồi lưu Agent.
6. Nếu không có mã, mở **Xem phản hồi OTA để chẩn đoán** và kiểm tra raw JSON.

## Nguồn protocol chính thức đã đối chiếu

- `78/xiaozhi-esp32/main/ota.cc`: SetupHttp, CheckVersion, Activate.
- `78/xiaozhi-esp32/main/boards/common/board.cc`: GetSystemInfoJson.
- `78/xiaozhi-esp32/docs/websocket.md`: Authorization, Protocol-Version, Device-Id, Client-Id và hello.
