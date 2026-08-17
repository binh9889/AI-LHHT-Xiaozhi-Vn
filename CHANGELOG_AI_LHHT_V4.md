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
