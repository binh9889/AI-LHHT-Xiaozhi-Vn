# RELEASE STATUS – AI-LHHT v4.1.2

> `READY` ở đây nghĩa là implementation/source route đã có nguồn chạy được theo phạm vi ghi rõ. Compile/runtime APK vẫn phải được GitHub Actions xác nhận.

| Tool | Trạng thái | Nguồn / bằng chứng trong source | Giới hạn |
|---|---|---|---|
| Xổ số | PARTIAL | 2 dataset XSMB + retry/fallback | Built-in xác minh XSMB; XSMT/XSMN cần Bridge |
| Lịch âm | READY | thuật toán local | Không cần mạng |
| Mã vùng | READY | bảng local | Không cần mạng |
| Nhà mạng | READY | bảng prefix local | Không xác nhận chuyển mạng giữ số realtime |
| Biển số | READY | bảng local | Tra mã tỉnh/thành cơ bản |
| Giá vàng | PARTIAL | trang SJC + Bridge | HTML SJC có thể không parse ổn định; không bịa giá |
| FX | READY | Frankfurter | tỷ giá tham chiếu, không phải tỷ giá tiền mặt từng ngân hàng |
| Lãi suất NH | NEEDS_CONFIGURATION | Bridge contract | cần provider có quyền sử dụng |
| Giá xăng | NEEDS_CONFIGURATION | Bridge contract | cần nguồn chuẩn hóa |
| VNIndex | NEEDS_CONFIGURATION | Bridge contract | cần market-data provider |
| Cổ phiếu VN | NEEDS_CONFIGURATION | Bridge contract | cần market-data provider |
| Crypto | READY | Binance public market data | spot market-data |
| Fear & Greed | PARTIAL | public Fear & Greed endpoint | phụ thuộc dịch vụ bên ngoài |
| Quy đổi tiền | READY | Frankfurter + local calculation | tỷ giá tham chiếu |
| Chỉ số thế giới | NEEDS_CONFIGURATION | Bridge contract | cần market-data provider |
| Hàng hóa | NEEDS_CONFIGURATION | Bridge contract | cần commodity provider |
| Tin tức | READY | VnExpress RSS | headline/latest feed |
| Realtime Info | PARTIAL | router tổng hợp | hiện dispatch crypto/news; mở rộng qua Bridge |
| Thời tiết | READY | Open-Meteo | phụ thuộc mạng |
| AQI | READY | Open-Meteo Air Quality | phụ thuộc mạng |
| Thể thao | PARTIAL | TheSportsDB | free/development capability có giới hạn; livescore đầy đủ cần provider phù hợp |

## Source validation

- `scripts/verify_v4.sh --static-only`: PASS tại thời điểm đóng gói.
- Flutter compile: CHƯA XÁC NHẬN trong môi trường đóng gói do không có Flutter SDK.
- GitHub Actions là gate compile/test chính thức.

## Patch 4.0.1 build fix

Ba lỗi unit test quan sát trên GitHub Actions đã được xử lý ở tầng production code, không chỉ sửa assertion:

- Tool router: Unicode-safe matching cho tiếng Việt có dấu.
- Local engine: không cần persistent config để chạy local-only tools.
- Preferences: fallback an toàn + mock deterministic trong test.

Trạng thái compile APK vẫn phải được xác nhận bởi GitHub Actions sau khi người dùng push patch này.
