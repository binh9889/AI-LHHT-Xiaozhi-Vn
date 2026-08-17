# AI-LHHT v3.4.0 — Build & kiểm thử

## Phiên bản
- App: `3.4.0+340`
- APK mục tiêu: `AI-LHHT-v3.4.0-Voice-Pro-InApp-Music-Reliable-Tools-VI.apk`
- Nhánh khuyến nghị: `develop-v3`

## Mục tiêu sửa lỗi
1. Normal Xiaozhi voice chat quay về luồng audio chính thức; không dùng native STT rồi gửi `listen/detect` như text chat.
2. Lệnh cục bộ (mã thiết bị, xổ số, nhạc) được xử lý ngay trong app sau STT và chặn câu trả lời Agent thừa.
3. Nhạc online mở trong WebView của AI-LHHT, không bật ứng dụng YouTube bên ngoài và không dùng kho 5 bài cục bộ.
4. Xổ số miền Bắc có hai nguồn dữ liệu + retry + cache phiên.
5. Phiên dịch Android có fallback Google ML Kit on-device, không còn phụ thuộc Xiaozhi text injection.
6. Phiên dịch hai chiều vẫn khóa ASR theo lượt `vi-VN ↔ zh-CN` và phát TTS theo locale đích.

## Build GitHub Actions
Sau khi đưa source lên `develop-v3`:

```bash
git add -A
git commit -m "Upgrade AI-LHHT v3.4 In-App Music and Reliable Tools"
git push origin develop-v3
```

Workflow `Build AI-LHHT v3.4 Voice Pro Reliable Tools APK` tự chạy khi push.

## Kiểm thử runtime bắt buộc
### A. Xiaozhi voice
- Vào chat Xiaozhi.
- Giữ mic và nói một câu bình thường.
- Phải thấy transcript STT một lần và Agent phản hồi; không được có timeout do gửi transcript lại lần hai.

### B. Thông tin thiết bị
Nói: `mã thiết bị của bạn là gì`.
App phải trả trực tiếp Device-ID/MAC, Client-ID, WebSocket và trạng thái mà không chờ Agent.

### C. Nhạc online
Nói: `bật nhạc Lê Bảo Bình cho tôi`.
App phải mở màn `Nhạc trực tuyến` nằm trong AI-LHHT. Chọn kết quả để phát ngay trong WebView; không chuyển sang ứng dụng YouTube bên ngoài.

### D. Xổ số
Nói: `kiểm tra kết quả xổ số miền Bắc hôm nay`.
App phải gọi local realtime tool, thử nguồn thứ hai nếu nguồn đầu lỗi, và đọc kết quả bằng TTS.

### E. Phiên dịch Việt ↔ Trung
Nói: `mở phiên dịch Việt Trung`.
- Lượt Việt: ASR `vi-VN` → dịch Trung → TTS `zh-CN`.
- Lượt Trung: ASR `zh-CN` → dịch Việt → TTS `vi-VN`.
- Nếu MiniMax/Dify chưa cấu hình, Android dùng ML Kit trên máy. Lần đầu có thể cần tải model ngôn ngữ qua mạng.

## Trạng thái xác minh
Môi trường đóng gói không có Flutter SDK nên không được tuyên bố compile PASS trước GitHub Actions. `scripts/verify_v3.sh` kiểm tra source và tự chạy Flutter checks nếu Flutter tồn tại.
