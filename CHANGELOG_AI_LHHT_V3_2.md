# AI-LHHT v3.2.0 Voice Pro – Real Connect + ASR Audio Fix

## Mục tiêu
Bản này không coi HTTP 200 hay việc tạo socket là "đã kết nối". Kết nối Xiaozhi chỉ PASS khi server trả `hello` hợp lệ theo protocol WebSocket v1.

## Sửa kết nối Xiaozhi
- Chờ server `hello` tối đa 10 giây trước khi chuyển trạng thái Connected.
- Giữ đúng headers trong WebSocket HTTP handshake: `Authorization`, `Protocol-Version`, `Device-Id`, `Client-Id`.
- Xóa fallback sai trước đây: gửi chuỗi `Authorization: ...` như một WebSocket text message.
- Sau khi OTA/binding trả `test-token` hoặc `GID_test`, không tự kết luận production PASS hay FAIL chỉ dựa trên tên token.
- Thêm nút **Kiểm tra kết nối Agent thật**: mở socket, gửi hello và chỉ PASS khi nhận server hello.
- Chỉ cho lưu cấu hình sau khi protocol handshake PASS.

## Sửa đường mic / ASR
Lỗi quan trọng của v3.1: `record.startStream()` có thể trả PCM chunk kích thước bất kỳ, nhưng code cũ encode mỗi chunk riêng và chỉ lấy 960 sample đầu. Chunk dài bị bỏ audio; chunk ngắn bị pad silence. Điều này có thể làm server ASR nhận audio méo/đứt đoạn.

v3.2:
- Buffer toàn bộ PCM16 theo byte.
- Tách chính xác frame 60 ms = 960 sample = 1920 byte ở 16 kHz mono.
- Không làm rơi sample.
- Không tự chèn silence vào chunk ngắn.
- Có unit test kiểm tra fragmentation/oversized chunk không mất dữ liệu.

## Giới hạn còn phụ thuộc server
Nếu `api.tenclass.net` vẫn trả `GID_test/test-token`, đây là dữ liệu OTA do cloud cấp. v3.2 sẽ thử protocol thật thay vì chặn sớm, nhưng app không thể tự biến credential cloud test thành token production của tài khoản.

STT cuối cùng vẫn do ASR phía Xiaozhi server tạo. v3.2 sửa lỗi audio client có bằng chứng trong source, nhưng độ chính xác tiếng Việt sau đó vẫn cần test thực tế trên server/model ASR đang dùng.
