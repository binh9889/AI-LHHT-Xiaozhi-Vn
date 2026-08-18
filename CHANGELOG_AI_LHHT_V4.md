# CHANGELOG – AI-LHHT v4

## 4.1.3+413 – Native Voice + Weather Clean Pro


- Sửa race ở cloud TTS: đổi sample-rate theo server hello không còn stop/re-create PCM player đúng lúc `tts:start`.
- Queue Opus downlink tuần tự, đếm frame nhận/phát và ghi lỗi playback để chẩn đoán trường hợp có chữ nhưng không tiếng.
- Giữ mặc định Xiaozhi Native Voice; reset preference key để bản nâng cấp không kế thừa nhầm lựa chọn local TTS cũ.
- Khi Native Voice bật, không khởi tạo FlutterTts ở nền để tránh local TTS tranh audio-focus với PCM Female Voice.
- Ghép nhiều `tts.sentence_start` thành một bubble; ẩn `% weather...` / `% search_knowledge...` và bỏ Markdown `**`, `__`, backtick trước khi hiển thị.
- Weather giữ nguyên địa điểm người dùng nói sau `ở/tại`; geocoder so khớp cả tiếng Việt có/không dấu, ưu tiên Việt Nam khi trùng tên và từ chối kết quả có độ khớp thấp thay vì đoán địa điểm khác.
- MCP công bố tool weather/AQI/news cụ thể, ưu tiên STT gốc để chống query drift và yêu cầu backend trả tối đa 2 câu, không Markdown/bình luận thêm.
- Thêm regression tests cho location routing và response sanitizer.

# PATCH 4.0.1+401 – Build Stability & Routing Fix

- Sửa ToolIntentRouter với cụm tiếng Việt có dấu (`xổ số`, `thời tiết`, `giá vàng`, `tin tức`) không còn rơi nhầm sang Agent do giới hạn ASCII của `\b`.
- Local Tool Engine không còn phụ thuộc SharedPreferences để chạy lịch âm, mã vùng, nhà mạng và biển số.
- ToolProviderConfigStore có fallback cấu hình mặc định nếu platform storage tạm thời chưa khả dụng.
- Bổ sung regression tests cho Unicode routing và mock SharedPreferences cho local engine tests.
- GitHub Actions build/release metadata nâng lên 4.0.1+401.

# CHANGELOG – AI-LHHT v4.0.0 Realtime Tools Pro

## Kiến trúc

- Thêm `ToolRegistry` 21 công cụ.
- Thêm `ToolIntentRouter` để realtime intent được xử lý trước Xiaozhi Agent.
- Thêm `RealtimeToolEngine` với cache, lịch sử và provider abstraction.
- Thêm Realtime Bridge cho nguồn cần API/quyền truy cập riêng.

## UI

- Thêm màn **Realtime & Tra cứu** responsive.
- Search, filter category, favorite, recent history.
- Thêm màn chi tiết tool và card kết quả có nguồn/timestamp/freshness.
- Thêm màn cấu hình nguồn dữ liệu realtime.
- Thêm Tool Engine vào Diagnostics và Settings.

## Nguồn tích hợp sẵn

- Open-Meteo: weather/geocoding/AQI.
- Frankfurter: FX và currency conversion.
- Binance public market data: crypto price/24h.
- VnExpress RSS: tin mới.
- TheSportsDB: tra đội/kết quả gần nhất theo khả năng của API key.
- Local data/algorithm: lunar calendar, area code, carrier prefix, plate code.
- XSMB: hai public dataset fallback; XSMT/XSMN dùng Bridge để tránh bịa dữ liệu.

## Safety / reliability

- Không hard-code giá realtime.
- Không fake API success.
- Không tự gọi Agent cho intent tool có confidence cao.
- Có timeout/retry/cache/fallback.
- Kết quả có source + timestamp.
- Tool không có nguồn xác minh trả `NEEDS_CONFIGURATION` thay vì số giả.

## 4.1.0+410 – Voice Stability Pro

- Unified TTS cho Agent, Tool, Tool Detail và Interpreter.
- Stable voice selection/persistence theo locale.
- Response gate chống Agent/Tool race.
- Loại bỏ `_suppressAgentRepliesUntil` 4–5 giây gây mất phản hồi tiếp theo.
- Context-aware ASR normalization cho các lỗi xổ số đã quan sát.
- Carrier intent nhận câu `098 là mạng nào`.
- Voice Stability settings + diagnostics.
