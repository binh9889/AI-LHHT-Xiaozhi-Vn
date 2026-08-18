# AI-LHHT v4.1.0+410 – Voice Stability Pro

## Vấn đề runtime được xử lý

Ảnh runtime v4.0.1 cho thấy ba nhóm lỗi độc lập:

1. **Một câu trả lời có lúc có tiếng, có lúc im lặng.**
   - Agent Xiaozhi phát audio cloud.
   - Tool/Interpreter phát bằng `FlutterTts` cục bộ.
   - Cơ chế suppress theo thời gian 4–5 giây có thể nuốt phản hồi kế tiếp nếu người dùng hỏi nhanh.
   - Hai audio pipeline có thể tranh audio-focus.

2. **Cùng một cuộc trò chuyện nhưng giọng nói thay đổi.**
   - Agent và local tools dùng hai TTS provider khác nhau.

3. **STT tiếng Việt bị sai và local tool rơi sang Agent.**
   - Ví dụ quan sát: `sổ số miền mắt` thay vì `xổ số miền Bắc`.
   - `số điện thoại đầu 098 là mạng nào` chưa được router bắt đủ rộng.
   - Khi Agent bắt đầu trả lời trước khi Tool Router nhận STT, các chuỗi `% gold_price...` / `% search_knowledge...` có thể lọt ra giao diện.

## Thay đổi kiến trúc v4.1

### Unified Speech Output

Thêm `UnifiedSpeechOutputService`:

- Một hàng đợi TTS duy nhất.
- Một voice ổn định theo locale, được chọn và lưu lại.
- Retry nhẹ khi Android TTS vừa mất audio-focus.
- Agent + realtime tools + tool detail + interpreter dùng chung service khi bật chế độ mặc định `Dùng một giọng cho toàn bộ app`.
- Khi chế độ này bật, binary audio TTS của Xiaozhi bị suppress để tránh hai giọng phát chồng nhau.

### Response Gate

Thêm response gate vào `XiaozhiService`:

- Khi bắt đầu nói, audio/text phản hồi Agent được buffer tạm thời.
- STT vẫn đi ra ngay để local Router phân loại.
- Nếu câu là realtime tool/local command: discard buffer + abort Agent.
- Nếu câu là hội thoại bình thường: release buffer và tiếp tục Agent.
- Có fail-open timeout 8 giây để không khóa phản hồi vô hạn.

### Bỏ suppress bằng đồng hồ

Xóa `_suppressAgentRepliesUntil` vì nó có thể làm câu hỏi kế tiếp bị im tiếng nếu người dùng nói trong cửa sổ 4–5 giây.

### Vietnamese ASR normalization

- `sổ số / sổ xố / xổ xố` → `xổ số` khi có ngữ cảnh xổ số.
- `miền mắt / miền mắc / miền bắt / miền bát` → `miền Bắc` chỉ trong ngữ cảnh xổ số.
- `tỉ giá` → `tỷ giá`.
- Router nhận thêm `mạng nào` cho carrier lookup.

### Diagnostics + Settings

- Cài đặt mới: `Giọng nói ổn định`.
- Có nút nghe thử voice.
- Diagnostics hiển thị trạng thái Unified TTS / voice đang chọn.

## Version

`4.1.0+410`

## APK mục tiêu

`AI-LHHT-v4.1.0-Voice-Stability-Pro-VI.apk`

## Validation

- Static source checks: PASS.
- ZIP integrity: kiểm tra khi đóng gói.
- Flutter analyze/test/build: GitHub Actions phải xác nhận vì môi trường đóng gói không có Flutter SDK.

- Pin `flutter_tts` 4.2.3 để lấy bản sửa Android TTS reconnection và dùng `focus: true` cho spoken audio.
