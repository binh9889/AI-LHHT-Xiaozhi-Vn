import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/providers/config_provider.dart';
import 'package:ai_assistant/services/translation_service.dart';
import 'package:ai_assistant/services/xiaozhi_service.dart';
import 'package:ai_assistant/utils/vietnamese_transcript_normalizer.dart';

class InterpreterScreen extends StatefulWidget {
  const InterpreterScreen({super.key});

  @override
  State<InterpreterScreen> createState() => _InterpreterScreenState();
}

class _InterpreterScreenState extends State<InterpreterScreen> {
  static const Map<String, String> _languages = {
    'Tự động nhận diện': 'auto',
    'Tiếng Việt': 'vi-VN',
    'English': 'en-US',
    '中文': 'zh-CN',
    '日本語': 'ja-JP',
    '한국어': 'ko-KR',
    'Français': 'fr-FR',
    'Deutsch': 'de-DE',
    'Español': 'es-ES',
    'ไทย': 'th-TH',
    'Русский': 'ru-RU',
  };

  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _outputController = TextEditingController();
  final FlutterTts _tts = FlutterTts();

  String _sourceLanguage = 'Tiếng Việt';
  String _targetLanguage = 'English';
  bool _naturalSpeech = true;
  bool _translating = false;
  bool _listening = false;
  bool _voiceReady = false;
  String _backend = 'Chưa dịch';
  String _voiceStatus = 'Chưa kết nối giọng nói';
  XiaozhiService? _xiaozhiService;

  @override
  void initState() {
    super.initState();
    Future.microtask(_prepareVoiceAsr);
  }

  Future<void> _prepareVoiceAsr() async {
    final provider = Provider.of<ConfigProvider>(context, listen: false);
    if (provider.xiaozhiConfigs.isEmpty) {
      if (mounted) {
        setState(() => _voiceStatus = 'Cấu hình Xiaozhi để dùng nhận giọng nói');
      }
      return;
    }

    final config = provider.xiaozhiConfigs.first;
    final service = XiaozhiService(
      websocketUrl: config.websocketUrl,
      macAddress: config.macAddress,
      clientId: config.clientId,
      token: config.token,
    );
    service.addListener(_handleXiaozhiEvent);
    _xiaozhiService = service;

    try {
      await service.connect();
      if (mounted) {
        setState(() {
          _voiceReady = service.isConnected;
          _voiceStatus = service.isConnected
              ? 'ASR Xiaozhi đã sẵn sàng'
              : 'Chưa kết nối được ASR Xiaozhi';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _voiceStatus = 'Lỗi kết nối giọng nói');
    }
  }

  void _handleXiaozhiEvent(XiaozhiServiceEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case XiaozhiServiceEventType.connected:
        setState(() {
          _voiceReady = true;
          _voiceStatus = 'ASR Xiaozhi đã sẵn sàng';
        });
        break;
      case XiaozhiServiceEventType.disconnected:
        setState(() {
          _voiceReady = false;
          _voiceStatus = 'Mất kết nối ASR';
        });
        break;
      case XiaozhiServiceEventType.userMessage:
        final rawText = (event.data ?? '').toString().trim();
        final normalized = VietnameseTranscriptNormalizer.normalize(rawText);
        final text = normalized.normalized;
        if (text.isNotEmpty) {
          _inputController.text = text;
          _inputController.selection = TextSelection.collapsed(
            offset: _inputController.text.length,
          );
          setState(() => _voiceStatus = 'Đã nhận: $text');
          _translate();
        }
        break;
      case XiaozhiServiceEventType.textMessage:
        // Màn phiên dịch chỉ lấy STT; không dùng câu trả lời của Agent Xiaozhi.
        _xiaozhiService?.stopPlayback();
        break;
      case XiaozhiServiceEventType.error:
        setState(() => _voiceStatus = 'Lỗi ASR: ${event.data}');
        break;
      case XiaozhiServiceEventType.audioData:
      case XiaozhiServiceEventType.voiceCallStart:
      case XiaozhiServiceEventType.voiceCallEnd:
        break;
    }
  }

  Future<void> _startListening() async {
    if (_xiaozhiService == null || !_voiceReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ASR Xiaozhi chưa sẵn sàng.')),
      );
      return;
    }
    try {
      setState(() {
        _listening = true;
        _voiceStatus = 'Đang nghe... thả nút khi nói xong';
      });
      await _xiaozhiService!.startListening(mode: 'manual');
    } catch (e) {
      if (mounted) {
        setState(() {
          _listening = false;
          _voiceStatus = 'Không thể bắt đầu thu âm';
        });
      }
    }
  }

  Future<void> _stopListening() async {
    if (!_listening) return;
    await _xiaozhiService?.stopListening();
    if (mounted) {
      setState(() {
        _listening = false;
        _voiceStatus = 'Đang nhận dạng giọng nói...';
      });
    }
  }

  Future<void> _translate() async {
    if (_translating || _inputController.text.trim().isEmpty) return;
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    final service = TranslationService(configProvider);
    if (!service.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hãy cấu hình MiniMax, Dify hoặc Xiaozhi trước.'),
        ),
      );
      return;
    }

    setState(() => _translating = true);
    try {
      final result = await service.translate(
        text: _inputController.text,
        sourceLanguage: _sourceLanguage,
        targetLanguage: _targetLanguage,
        naturalSpeech: _naturalSpeech,
      );
      if (!mounted) return;
      _outputController.text = result.text;
      setState(() => _backend = result.backend);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Phiên dịch thất bại: $e')),
      );
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  Future<void> _speakTranslation() async {
    final text = _outputController.text.trim();
    if (text.isEmpty) return;
    final locale = _languages[_targetLanguage] ?? 'en-US';
    if (locale != 'auto') await _tts.setLanguage(locale);
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    await _tts.speak(text);
  }

  void _swapLanguages() {
    if (_sourceLanguage == 'Tự động nhận diện') return;
    setState(() {
      final old = _sourceLanguage;
      _sourceLanguage = _targetLanguage;
      _targetLanguage = old;
      final oldText = _inputController.text;
      _inputController.text = _outputController.text;
      _outputController.text = oldText;
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _outputController.dispose();
    _tts.stop();
    _xiaozhiService?.removeListener(_handleXiaozhiEvent);
    _xiaozhiService?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phiên dịch AI'),
        actions: [
          IconButton(
            tooltip: 'Đổi ngôn ngữ',
            onPressed: _swapLanguages,
            icon: const Icon(Icons.swap_horiz_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 760;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LanguageBar(
                    source: _sourceLanguage,
                    target: _targetLanguage,
                    languages: _languages.keys.toList(),
                    onSourceChanged: (value) =>
                        setState(() => _sourceLanguage = value),
                    onTargetChanged: (value) =>
                        setState(() => _targetLanguage = value),
                    onSwap: _swapLanguages,
                  ),
                  const SizedBox(height: 14),
                  if (horizontal)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildInputCard(theme)),
                        const SizedBox(width: 14),
                        Expanded(child: _buildOutputCard(theme)),
                      ],
                    )
                  else ...[
                    _buildInputCard(theme),
                    const SizedBox(height: 14),
                    _buildOutputCard(theme),
                  ],
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Dịch hội thoại tự nhiên'),
                            subtitle: const Text(
                              'Ưu tiên câu nói tự nhiên thay vì dịch từng chữ.',
                            ),
                            value: _naturalSpeech,
                            onChanged: (value) =>
                                setState(() => _naturalSpeech = value),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              _voiceReady
                                  ? Icons.graphic_eq_rounded
                                  : Icons.mic_off_outlined,
                            ),
                            title: Text(_voiceStatus),
                            subtitle: Text('AI dịch: $_backend'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInputCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Nội dung gốc',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    _inputController.clear();
                    _outputController.clear();
                  },
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  label: const Text('Xóa'),
                ),
              ],
            ),
            TextField(
              controller: _inputController,
              minLines: 6,
              maxLines: 12,
              decoration: const InputDecoration(
                hintText: 'Nhập nội dung hoặc giữ nút mic để nói...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _translating ? null : _translate,
                    icon: _translating
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.translate_rounded),
                    label: Text(_translating ? 'Đang dịch...' : 'Dịch ngay'),
                  ),
                ),
                const SizedBox(width: 10),
                Listener(
                  onPointerDown: (_) => _startListening(),
                  onPointerUp: (_) => _stopListening(),
                  onPointerCancel: (_) => _stopListening(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _listening
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                      boxShadow: _listening
                          ? [
                              BoxShadow(
                                color: theme.colorScheme.error.withOpacity(.28),
                                blurRadius: 18,
                                spreadRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                    child: const Icon(Icons.mic_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Giữ mic để nói • Thả để nhận dạng và dịch',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutputCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Bản dịch',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Đọc bản dịch',
                  onPressed: _speakTranslation,
                  icon: const Icon(Icons.volume_up_rounded),
                ),
              ],
            ),
            TextField(
              controller: _outputController,
              readOnly: true,
              minLines: 6,
              maxLines: 12,
              decoration: const InputDecoration(
                hintText: 'Bản dịch sẽ xuất hiện ở đây',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _speakTranslation,
              icon: const Icon(Icons.record_voice_over_rounded),
              label: const Text('Phát giọng bản dịch'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageBar extends StatelessWidget {
  final String source;
  final String target;
  final List<String> languages;
  final ValueChanged<String> onSourceChanged;
  final ValueChanged<String> onTargetChanged;
  final VoidCallback onSwap;

  const _LanguageBar({
    required this.source,
    required this.target,
    required this.languages,
    required this.onSourceChanged,
    required this.onTargetChanged,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: source,
                  items: languages
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onSourceChanged(value);
                  },
                ),
              ),
            ),
            IconButton(onPressed: onSwap, icon: const Icon(Icons.swap_horiz)),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: target,
                  items: languages
                      .where((e) => e != 'Tự động nhận diện')
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onTargetChanged(value);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
