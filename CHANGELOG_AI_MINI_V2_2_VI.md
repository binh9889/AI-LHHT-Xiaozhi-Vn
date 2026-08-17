# AI-LHHT / Xiaozhi Android 2.2.0 VI

## Sửa lỗi chính thức Xiaozhi provisioning

- Sửa OTA từ GET rỗng sang POST JSON.
- Dùng `Activation-Version: 1` trên Android thay vì giả mạo Serial-Number/HMAC eFuse.
- Body OTA bám cấu trúc `Board::GetSystemInfoJson()` từ firmware `78/xiaozhi-esp32`.
- Hiển thị raw OTA response, HTTP status và final URL để chẩn đoán.
- Parse `activation.code`, `activation.message`, `activation.challenge`, `websocket`, `mqtt`, `firmware`.

## Sửa WebSocket identity

- Lưu riêng `Device-Id` và `Client-Id`.
- WebSocket handshake gửi đúng `Device-Id`, `Client-Id`, `Protocol-Version` và Bearer token.
- Không in token thật ra log.
- Migration cấu hình v2.1.x để bổ sung Client-Id ổn định.

## Sửa cấu hình app

- Token nhập thủ công trong màn hình cấu hình Xiaozhi nay được lưu đúng.
- Mỗi `XiaozhiService` dùng đúng cấu hình hiện tại, không giữ singleton credential cũ.
- Version app/build: `2.2.0+220`.

## Build

Workflow: `.github/workflows/build-vi-apk.yml`

Artifact: `AI-LHHT-v2.2.0-VI.apk`
