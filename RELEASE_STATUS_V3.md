# Release status — AI-LHHT v3.0 Voice Pro

## Implemented in source
- Responsive Home/Conversation list
- Responsive Explore grid
- Responsive Settings without horizontal tabs
- Xiaozhi/Dify/MiniMax config management UI
- Token masking/no new fake test-token
- Chat header overflow fix
- Vietnamese-facing error cleanup (major paths)
- AI text translation
- Voice STT → AI translation
- TTS playback of translated text
- Vietnamese transcript normalization for high-confidence cases
- Voice diagnostics page
- GitHub Actions build/test workflow

## Validation level in this package
- Static source/bracket sanity checks: PASS
- Flutter compile/analyze: MUST be run by GitHub Actions (Flutter SDK is not available in the packaging environment)
- Android device runtime test: PENDING

Do not call the APK production-ready until GitHub Actions and on-device smoke tests pass.
