# AI-LHHT v4.1.1 – Xiaozhi Native Voice Pro

- Khôi phục audio TTS cloud của Xiaozhi làm đầu ra mặc định.
- Không dùng TTS Android để thay giọng Agent khi Xiaozhi Native Voice đang bật.
- Voice profile (ví dụ Female Voice) vẫn được chọn trên xiaozhi.me; app phát nguyên audio Opus do server gửi về.
- Bổ sung MCP server tối thiểu trong app: initialize, tools/list, tools/call.
- Expose `self.realtime.lookup` để Agent Xiaozhi có thể gọi Realtime Tool Engine và tự nói kết quả bằng chính voice cloud.
- Nếu backend chưa bắt tay MCP, app vẫn fallback router local; ở Native Voice mode fallback local không tự đọc bằng giọng Android để tránh đổi giọng.
- Phiên dịch vẫn dùng TTS ngôn ngữ đích khi cần vì đó là luồng khác với voice Agent.
