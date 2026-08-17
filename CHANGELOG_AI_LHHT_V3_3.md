# AI-LHHT v3.3.0 – Online Tools + Bilingual ASR

## Mục tiêu
Sửa ba lỗi thực tế của v3.2:

1. Agent báo không có công cụ khi hỏi kết quả xổ số.
2. `search_music` chỉ tìm kho nhạc cục bộ rất nhỏ.
3. Phiên dịch Việt ↔ Trung dùng ASR sai ngôn ngữ, dịch sai chiều và không đảm bảo có âm thanh ngôn ngữ đích.

## Nâng cấp chính

### Tool xổ số online ngay trong APK
- Chặn intent `xổ số / sổ số / sổ xố / XSMB` trước khi gửi Agent.
- Lấy dữ liệu XSMB trực tuyến dạng CSV.
- Kiểm tra ngày của dữ liệu trước khi gọi là "hôm nay".
- Giữ số 0 đầu các giải ngắn.
- Không còn phụ thuộc Agent tenclass có plugin xổ số hay không.

### Tìm nhạc trực tuyến
- Chặn lệnh `bật nhạc / mở nhạc / ca sĩ / bài hát` trước Agent.
- Nếu chưa có tên bài/ca sĩ, app hỏi tiếp và nhớ trạng thái.
- Tra catalog online để làm rõ bài/ca sĩ rồi mở tìm kiếm YouTube Music bằng ứng dụng/trình duyệt ngoài.
- Không còn phụ thuộc kho nhạc cục bộ 5 bài.
- Không dùng preview iTunes làm nguồn nghe nhạc toàn bài.

### Phiên dịch hai chiều theo lượt
- Thêm `speech_to_text` native ASR.
- Mỗi lượt khóa locale cụ thể, ví dụ:
  - Lượt A: `vi-VN` → dịch → nói `zh-CN`.
  - Lượt B: `zh-CN` → dịch → nói `vi-VN`.
- Không còn đoán ngôn ngữ sau khi transcript đã bị ASR nhận sai.
- Có nút **Đổi lượt**.
- Nếu `zh-CN` không có trên thiết bị, app báo rõ để cài dịch vụ/ngôn ngữ ASR thay vì fallback sang ASR tiếng Việt và tạo transcript sai.

### TTS bản dịch
- Xiaozhi làm backend dịch ở chế độ silent.
- App luôn phát bản dịch bằng Flutter TTS với locale đích.
- Kiểm tra TTS locale khả dụng và báo rõ nếu máy thiếu giọng.

### Chat tiếng Việt
- Push-to-talk ưu tiên native ASR `vi-VN`.
- Nếu native ASR không khả dụng ở chat thường, mới fallback sang Xiaozhi ASR.
- Transcript sạch được gửi tiếp cho Xiaozhi để giữ Agent/MCP/TTS hiện tại.

### Diagnostics
- Kiểm tra ASR `vi-VN` và `zh-CN`.
- Hiển thị PASS/thiếu cho từng locale.

## Phiên bản
`3.3.0+330`

APK mục tiêu:
`AI-LHHT-v3.3.0-Voice-Pro-Online-Tools-Bilingual-VI.apk`
