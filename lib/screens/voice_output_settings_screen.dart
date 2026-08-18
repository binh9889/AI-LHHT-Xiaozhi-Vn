import 'package:flutter/material.dart';
import 'package:ai_assistant/services/unified_speech_output_service.dart';
import 'package:ai_assistant/services/voice_output_preferences.dart';

class VoiceOutputSettingsScreen extends StatefulWidget {
  const VoiceOutputSettingsScreen({super.key});

  @override
  State<VoiceOutputSettingsScreen> createState() =>
      _VoiceOutputSettingsScreenState();
}

class _VoiceOutputSettingsScreenState
    extends State<VoiceOutputSettingsScreen> {
  final VoiceOutputPreferences _preferences = VoiceOutputPreferences();
  final UnifiedSpeechOutputService _speech =
      UnifiedSpeechOutputService.instance;
  bool _loading = true;
  bool _unified = true;
  bool _ttsReady = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final unified = await _preferences.useUnifiedVoice();
    final ready = await _speech.initialize(locale: 'vi-VN');
    if (!mounted) return;
    setState(() {
      _unified = unified;
      _ttsReady = ready;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Giọng nói ổn định')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: SwitchListTile.adaptive(
                    value: _unified,
                    onChanged: (value) async {
                      await _preferences.setUseUnifiedVoice(value);
                      if (!mounted) return;
                      setState(() => _unified = value);
                    },
                    secondary: const Icon(Icons.record_voice_over_rounded),
                    title: const Text(
                      'Dùng một giọng cho toàn bộ app',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      _unified
                          ? 'Agent, công cụ realtime và phiên dịch dùng cùng TTS hệ thống. Khuyên dùng để tránh đổi giọng và tranh audio-focus.'
                          : 'Agent dùng giọng Xiaozhi cloud; Tool/phiên dịch dùng giọng hệ thống nên có thể khác giọng.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: Icon(
                      _ttsReady ? Icons.check_circle : Icons.error_outline,
                      color: _ttsReady ? Colors.green : Colors.orange,
                    ),
                    title: Text(_ttsReady
                        ? 'TTS tiếng Việt sẵn sàng'
                        : 'TTS tiếng Việt chưa sẵn sàng'),
                    subtitle: Text(
                      _ttsReady
                          ? 'Voice: ${_speech.lastVoice.isEmpty ? 'theo hệ thống' : _speech.lastVoice}'
                          : 'Hãy cài dữ liệu Text-to-Speech tiếng Việt trong Android.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: !_ttsReady
                      ? null
                      : () async {
                          await _speech.stop();
                          await _speech.speak(
                            'Đây là giọng nói ổn định của AI LHHT.',
                            locale: 'vi-VN',
                          );
                        },
                  icon: const Icon(Icons.volume_up_rounded),
                  label: const Text('Nghe thử giọng'),
                ),
                const SizedBox(height: 16),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Lưu ý: nếu tắt “một giọng”, câu trả lời từ Xiaozhi có thể dùng giọng cloud khác với giọng của công cụ realtime. Đây là hành vi cố ý, không phải lỗi.',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
