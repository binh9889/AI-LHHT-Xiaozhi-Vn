# AI-LHHT v4.0.0 – Realtime Tools Pro

AI-LHHT v4 refactor luồng hội thoại theo kiến trúc **Voice → ASR → Intent Router → Tool / Music / Interpreter / Xiaozhi Agent → TTS**. Mục tiêu là không gửi mọi câu hỏi realtime sang Agent rồi chờ Agent tự biết dữ liệu.

## Thành phần chính

- Xiaozhi voice/WebSocket/OTA giữ từ nhánh v3.4.
- Live Interpreter giữ kiến trúc khóa locale từng lượt.
- Online Music giữ player trong app từ v3.4.
- Realtime Tool Engine v4 mới với registry 21 công cụ.
- Tool Intent Router xử lý câu nói/typed text trước Agent.
- Cache, retry, fallback bridge, lịch sử và mục ghim.
- Màn Realtime & Tra cứu, màn chi tiết từng tool, màn cấu hình nguồn dữ liệu.
- Diagnostics có kiểm tra Tool Engine.

## 21 công cụ

1. Xổ số
2. Lịch âm
3. Mã vùng điện thoại
4. Tra nhà mạng
5. Tra biển số xe
6. Giá vàng
7. Tỷ giá ngoại tệ
8. Lãi suất ngân hàng
9. Giá xăng dầu
10. Chứng khoán VN-Index
11. Tra mã cổ phiếu
12. Giá Crypto
13. Tâm lý thị trường Crypto
14. Quy đổi tiền tệ
15. Chỉ số chứng khoán thế giới
16. Giá hàng hóa thế giới
17. Tin tức nóng
18. Realtime Info
19. Thời tiết
20. Chất lượng không khí
21. Tỷ số thể thao

## Trạng thái trung thực

Không phải mọi nguồn dữ liệu realtime đều có API công khai, ổn định, hợp pháp và không cần khóa. Vì vậy v4 phân biệt rõ:

- **READY:** chạy bằng nguồn cục bộ hoặc public API tích hợp.
- **PARTIAL:** chạy được một phạm vi xác minh được, phần còn lại dùng Bridge.
- **NEEDS_CONFIGURATION:** UI/router/service đã hoàn chỉnh nhưng cần Realtime Bridge/API có quyền sử dụng.

Xem `RELEASE_STATUS_V4.md` để biết bằng chứng từng tool.

## Realtime Bridge

Các nguồn chưa thể tích hợp an toàn trực tiếp dùng một contract chung:

```text
GET <bridge>?toolId=<id>&q=<query>&...
Authorization: Bearer <token>   # tùy chọn
```

Response:

```json
{
  "success": true,
  "title": "VNIndex",
  "summary": "VNIndex ...",
  "source": "Provider name",
  "timestamp": "2026-08-18T01:00:00+07:00",
  "data": {
    "Điểm": "...",
    "Thay đổi": "..."
  }
}
```

## Build

Xem `BUILD_V4_VI.md`.
