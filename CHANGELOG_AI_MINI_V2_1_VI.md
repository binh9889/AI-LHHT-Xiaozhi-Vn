# AI-LHHT / Xiaozhi Android 2.1.0+3

## Mục tiêu
Bổ sung luồng provisioning Xiaozhi trước WebSocket để điện thoại có thể thử hành vi gần với thiết bị Xiaozhi thật hơn và chẩn đoán chính xác trường hợp server chỉ cấp test-token.

## Thay đổi
- Thêm `XiaozhiProvisioningService` gọi OTA official endpoint.
- Device-ID dạng locally-administered MAC được tạo một lần và lưu ổn định.
- Client-ID UUID được tạo một lần và lưu ổn định.
- Parse `websocket`, `token`, `activation`, `mqtt` từ phản hồi OTA.
- Hiển thị mã activation nếu server cấp.
- Nhận biết `test-token` / `GID_test` và báo rõ chế độ thử nghiệm.
- Lưu cấu hình WebSocket/token nhận từ OTA để sử dụng trong hội thoại.
- Thêm màn hình tiếng Việt `Kết nối Xiaozhi chính thức`.
- Giữ cấu hình Xiaozhi thủ công để dùng server tự triển khai.

## Giới hạn đã biết
Không có mã phía client nào có thể ép xiaozhi.me cấp mã 6 số nếu server quyết định danh tính Android/board đó chỉ được dùng test credential. App sẽ hiển thị chính xác trạng thái này thay vì báo nhầm là đã liên kết Agent.
