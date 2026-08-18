# AI-LHHT v4.1.3+413 — Build Stability Hotfix

GitHub Actions của v4.1.3 dừng ở bước `UI and unit tests`: 42 PASS, 3 FAIL.
Ba lỗi đều nằm trong `response_text_sanitizer_test.dart`:

- removes markdown emphasis before display or TTS
- joins fragmented TTS into one clean reply
- limits realtime tool verbosity without touching normal sanitizer

Hotfix thay phần sanitizer bằng các phép biến đổi deterministic, tránh regex capture/back-reference phức tạp, đồng thời giữ nguyên behavior của internal tool command filter.

Không thay đổi protocol Xiaozhi Native Female Voice, weather routing hay Realtime Tool Engine trong hotfix này.

Version: `4.1.3+413`.
