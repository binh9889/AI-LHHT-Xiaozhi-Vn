# V4 Architecture Audit

## Vấn đề chính của v3.x

1. `chat_screen.dart` từng gánh quá nhiều trách nhiệm: chat, voice, local command, tool, music, interpreter, Xiaozhi.
2. Realtime request có nguy cơ rơi xuống Agent và bị trả "không có công cụ" hoặc timeout.
3. Dữ liệu realtime thiếu contract thống nhất về source/timestamp/error/cache.
4. Một số nguồn Việt Nam không có public API ổn định, dẫn tới nguy cơ hard-code hoặc scrape dễ gãy.

## Quyết định v4

```text
Voice/Text
  ↓
Transcript normalization
  ↓
ToolIntentRouter
  ├─ Tool Engine
  ├─ Music
  ├─ Interpreter
  └─ Xiaozhi Agent
```

Realtime facts chỉ được lấy từ Tool Engine/provider. Agent chỉ dùng để hội thoại/tổng hợp sau khi dữ liệu có nguồn.

## Thành phần giữ lại

- Xiaozhi OTA/WebSocket/PCM integrity từ v3.x.
- Interpreter turn controller.
- In-app music module.
- ConfigProvider / ThemeProvider.

## Thành phần mới

- `lib/tools/models/`
- `lib/tools/providers/`
- `lib/tools/services/`
- `lib/tools/widgets/`
- `RealtimeToolsScreen`
- `ToolDetailScreen`
- `ToolProviderSettingsScreen`
