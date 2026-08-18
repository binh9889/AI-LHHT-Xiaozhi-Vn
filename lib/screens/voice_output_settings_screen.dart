import 'package:flutter/material.dart';
import 'package:ai_assistant/services/unified_speech_output_service.dart';
import 'package:ai_assistant/services/voice_output_preferences.dart';

class VoiceOutputSettingsScreen extends StatefulWidget {
  const VoiceOutputSettingsScreen({super.key});

  @override
  State<VoiceOutputSettingsScreen> createState() => _VoiceOutputSettingsScreenState();
}

class _VoiceOutputSettingsScreenState extends State<VoiceOutputSettingsScreen> {
  final VoiceOutputPreferences _preferences = VoiceOutputPreferences();
  final UnifiedSpeechOutputService _speech = UnifiedSpeechOutputService.instance;
  bool _loading = true;
  bool _nativeXiaozhi = true;
  bool _localUnified = false;
  bool _ttsReady = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final native = await _preferences.useXiaozhiNativeVoice();
    final unified = await _preferences.useUnifiedVoice();
    final ready = await _speech.initialize(locale: 'vi-VN');
    if (!mounted) return;
    setState(() {
      _nativeXiaozhi = native;
      _localUnified = unified;
      _ttsReady = ready;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nguồn giọng nói')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: SwitchListTile.adaptive(
                    value: _nativeXiaozhi,
                    onChanged: (value) async {
                      await _preferences.setUseXiaozhiNativeVoice(value);
                      if (value) await _preferences.setUseUnifiedVoice(false);
                      if (!mounted) return;
                      setState(() {
                        _nativeXiaozhi = value;
                        if (value) _localUnified = false;
                      });
                    },
                    secondary: const Icon(Icons.cloud_done_rounded),
                    title: const Text(
                      'Giữ giọng Xiaozhi chính thức',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      _nativeXiaozhi
                          ? 'Đang ưu tiên audio cloud của Agent. Nếu xiaozhi.me đang chọn “Giọng nữ (Female Voice)”, app sẽ phát đúng audio giọng đó, không thay bằng TTS Android.'
                          : 'Đã tắt giọng cloud. Có thể dùng TTS Android bên dưới.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: SwitchListTile.adaptive(
                    value: _localUnified,
                    onChanged: _nativeXiaozhi
                        ? null
                        : (value) async {
                            await _preferences.setUseUnifiedVoice(value);
                            if (!mounted) return;
                            setState(() => _localUnified = value);
                          },
                    secondary: const Icon(Icons.phone_android_rounded),
                    title: const Text('Dùng TTS Android thay thế'),
                    subtitle: const Text(
                      'Chỉ bật khi bạn thực sự muốn thay giọng Xiaozhi. Chế độ này không được bật mặc định ở v4.1.3.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: Icon(
                      _nativeXiaozhi ? Icons.check_circle : (_ttsReady ? Icons.info : Icons.error_outline),
                      color: _nativeXiaozhi ? Colors.green : (_ttsReady ? Colors.blue : Colors.orange),
                    ),
                    title: Text(_nativeXiaozhi ? 'Xiaozhi Native Voice đang được khóa' : 'TTS Android ${_ttsReady ? 'sẵn sàng' : 'chưa sẵn sàng'}'),
                    subtitle: Text(
                      _nativeXiaozhi
                          ? 'Agent và kết quả realtime qua MCP sẽ do Xiaozhi server tổng hợp và phát bằng voice profile của Agent. Nếu có chữ nhưng không có tiếng, mở Chẩn đoán hệ thống để xem downlink/sample-rate và trạng thái PCM player.'
                          : (_ttsReady ? 'Voice local: ${_speech.lastVoice.isEmpty ? 'theo hệ thống' : _speech.lastVoice}' : 'Cần cài dữ liệu TTS trên Android.'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Lưu ý: lựa chọn “Female Voice” nằm trên cấu hình Agent của xiaozhi.me. App không tự đặt tên voice cloud; app chỉ bảo đảm không chặn hoặc thay thế audio TTS mà Xiaozhi gửi về. Phiên dịch đa ngôn ngữ vẫn có thể cần TTS theo ngôn ngữ đích trên điện thoại.',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
