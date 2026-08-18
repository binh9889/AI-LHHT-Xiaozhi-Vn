# AI-LHHT v4.1.2+412 – Native Voice / Weather / Clean Response Fix

## Lỗi runtime được nhắm tới

1. Xiaozhi trả subtitle/text nhưng APK không phát được Female Voice.
2. Weather có thể chọn địa điểm khác địa điểm người dùng vừa nói.
3. `% weather...`, `% search_knowledge...`, Markdown `**` xuất hiện trong chat.
4. Một câu trả lời Xiaozhi bị tách thành nhiều bubble và trở nên dài/rối.
5. Cần biết rõ server có gửi audio frame hay player của APK đang lỗi.

## Sửa audio Xiaozhi Native Voice

- Giữ mặc định `Xiaozhi Native Voice = ON` bằng preference key v4.1.2 mới.
- Khi Native Voice bật, app KHÔNG khởi tạo Android `FlutterTts` ở nền. Đây là cách ly audio-focus để TTS local không can thiệp đường Female Voice của Xiaozhi.
- Đọc `audio_params.sample_rate` từ server hello.
- Opus decoder bám đúng downlink sample-rate của server.
- PCM output vẫn được đưa về 16 kHz cho player hiện tại.
- Quan trọng: thay đổi sample-rate ở `hello` KHÔNG còn stop/re-create PCM player. Việc stop player ngay lúc hello có thể race với `tts:start` và làm mất cả câu TTS.
- Binary Opus frames đi qua một queue tuần tự để tránh nhiều frame đồng thời re-init player.
- Đếm `cloudAudioFramesReceived`, `cloudFramesPlayed`, giữ `lastPlaybackError` cho Diagnostics.
- Nếu server gửi TTS text nhưng không gửi binary audio frame, app báo lỗi rõ thay vì chỉ im lặng.

## Sửa weather location

- Router ưu tiên địa điểm nguyên văn sau `ở` / `tại`.
- MCP tool ưu tiên transcript STT gốc của chính lượt nói thay vì location/query do LLM tự suy diễn; giảm lỗi hỏi một nơi nhưng tool nhận một nơi khác.
- Geocoder lấy tối đa 10 candidate thay vì chọn kết quả đầu tiên.
- So khớp tên/cấp hành chính cả có dấu và không dấu.
- Khi trùng tên, ưu tiên candidate Việt Nam nhưng không lọc cứng để vẫn tra quốc tế.
- Nếu candidate tốt nhất có điểm khớp thấp, trả `LOCATION_NOT_FOUND` thay vì đoán một địa điểm khác.
- Weather summary tối đa 2 câu và dùng dữ liệu có cấu trúc của provider.

## Sửa text hiển thị

- Ẩn internal command `% weather...`, `% search_knowledge...`, `% gold_price...`.
- Xóa Markdown `**`, `__`, backtick trước khi hiển thị/đọc.
- Ghép nhiều `tts.sentence_start` thành một reply duy nhất ở `tts.stop`.
- Với phản hồi tool đã xác định, giới hạn tối đa 2 câu để tránh trả lời dài, lặp và bình luận linh tinh.
- MCP descriptions yêu cầu backend dùng device tool cho weather/AQI/news và trả lời ngắn, không Markdown.

## Regression tests

- Weather location: `Chánh Hiệp`, `Đà Nẵng`.
- Markdown sanitizer.
- Internal percent-command sanitizer.
- Fragmented TTS join.

## Trạng thái xác minh

- Static source checks: chạy bằng `bash scripts/verify_v4.sh --static-only`.
- Flutter analyze/test/build: phải được GitHub Actions xác nhận; không được tự ghi PASS nếu chưa chạy.
