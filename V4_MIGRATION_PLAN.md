# Migration Plan v3.4 → v4.0

1. Giữ Xiaozhi/Interpreter/Music hiện hành làm baseline.
2. Đưa realtime intent vào `ToolIntentRouter` trước Agent.
3. Chuyển lottery/tool cũ thành provider trong `RealtimeToolEngine` theo thời gian.
4. Các nguồn có public API ổn định chạy trực tiếp.
5. Các nguồn cần credential/market-data được chuẩn hóa qua Realtime Bridge.
6. UI tool không gọi API lúc render; chỉ gọi khi người dùng yêu cầu.
7. Mọi result bắt buộc có source/timestamp/success/errorCode.
8. Sau khi GitHub Actions xanh, test runtime trên Android thật trước khi merge `develop-v4` vào `main`.
