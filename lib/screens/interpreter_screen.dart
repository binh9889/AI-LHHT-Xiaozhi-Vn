import 'dart:async';

import 'package:ai_assistant/providers/config_provider.dart';
import 'package:ai_assistant/services/native_speech_service.dart';
import 'package:ai_assistant/services/translation_service.dart';
import 'package:ai_assistant/utils/interpreter_turn_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';

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
  final NativeSpeechService _speech = NativeSpeechService.instance;

  String _sourceLanguage = 'Tiếng Việt';
  String _targetLanguage = 'English';
  bool _naturalSpeech = true;
  bool _conversationMode = true;
  bool _autoSpeak = true;
  bool _translating = false;
  bool _listening = false;
  bool _voiceReady = false;
  String _backend = 'Chưa dịch';
  String _voiceStatus = 'Đang chuẩn bị nhận giọng nói...';
  late InterpreterTurnController _turn;

  @override
  void initState() {
    super.initState();
    _turn = InterpreterTurnController(
      languageA: _sourceLanguage,
      localeA: _languages[_sourceLanguage]!,
      languageB: _targetLanguage,
      localeB: _languages[_targetLanguage]!,
    );
    Future.microtask(_prepareServices);
  }

  Future<void> _prepareServices() async {
    final ready = await _speech.initialize();
    if (mounted) {
      setState(() {
        _voiceReady = ready;
        _voiceStatus = ready
            ? 'ASR theo ngôn ngữ đã sẵn sàng'
            : 'Máy không có dịch vụ nhận dạng giọng nói khả dụng';
      });
    }
  }

  void _syncTurnPair({bool reset = true}) {
    var source = _sourceLanguage;
    if (_conversationMode && source == 'Tự động nhận diện') {
      source = 'Tiếng Việt';
      _sourceLanguage = source;
    }
    final aLocale = _languages[source] ?? 'vi-VN';
    final bLocale = _languages[_targetLanguage] ?? 'en-US';
    _turn.updatePair(
      newLanguageA: source,
      newLocaleA: aLocale,
      newLanguageB: _targetLanguage,
      newLocaleB: bLocale,
    );
    if (!reset) _turn.swapTurn();
  }

  Future<void> _startListening() async {
    if (!_voiceReady || _translating) {
      _snack('Nhận dạng giọng nói chưa sẵn sàng.');
      return;
    }

    final locale = _conversationMode
        ? _turn.sourceLocale
        : (_languages[_sourceLanguage] ?? 'auto');
    final label = _conversationMode ? _turn.sourceLanguage : _sourceLanguage;
    final started = await _speech.start(
      localeId: locale,
      onResult: (words, isFinal) {
        if (!mounted || words.trim().isEmpty) return;
        setState(() {
          _inputController.text = words;
          _inputController.selection = TextSelection.collapsed(
            offset: words.length,
          );
          _voiceStatus = isFinal ? 'Đã nhận $label' : 'Đang nghe $label…';
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _listening = started;
      _voiceStatus = started
          ? 'Đang nghe $label… thả nút khi nói xong'
          : 'Không mở được ASR $label: ${_speech.lastError}';
    });
  }

  Future<void> _stopListening() async {
    if (!_listening) return;
    setState(() {
      _listening = false;
      _voiceStatus = 'Đang chốt câu nói…';
    });
    final text = (await _speech.stopAndGetText()).trim();
    if (!mounted) return;
    if (text.isEmpty) {
      setState(() => _voiceStatus = 'Không nghe rõ. Hãy thử nói lại gần micro hơn.');
      return;
    }
    _inputController.text = text;
    _inputController.selection = TextSelection.collapsed(offset: text.length);
    await _translateCurrentInput(fromVoice: true);
  }

  Future<void> _cancelListening() async {
    await _speech.cancel();
    if (mounted) {
      setState(() {
        _listening = false;
        _voiceStatus = 'Đã hủy lượt nói';
      });
    }
  }

  Future<void> _translateCurrentInput({bool fromVoice = false}) async {
    if (_translating || _inputController.text.trim().isEmpty) return;
    final provider = Provider.of<ConfigProvider>(context, listen: false);
    final service = TranslationService(provider);
    if (!service.isAvailable) {
      _snack('Thiết bị chưa có backend dịch khả dụng. Hãy kiểm tra Android ML Kit hoặc cấu hình MiniMax/Dify.');
      return;
    }

    final text = _inputController.text.trim();
    final sourceLanguage = _conversationMode ? _turn.sourceLanguage : _sourceLanguage;
    final targetLanguage = _conversationMode ? _turn.targetLanguage : _targetLanguage;
    final targetLocale = _conversationMode
        ? _turn.targetLocale
        : (_languages[_targetLanguage] ?? 'en-US');

    setState(() {
      _translating = true;
      _voiceStatus = '$sourceLanguage → $targetLanguage: đang dịch…';
    });
    try {
      final result = await service.translate(
        text: text,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        naturalSpeech: _naturalSpeech,
      );
      if (!mounted) return;
      _outputController.text = result.text;
      setState(() {
        _backend = result.backend;
        _voiceStatus = '$sourceLanguage → $targetLanguage';
      });

      // Luôn phát TTS trên máy bằng locale ĐÍCH. Không phụ thuộc server Xiaozhi
      // có chọn đúng giọng/ngôn ngữ hay không.
      if (_autoSpeak) {
        await _speakText(result.text, targetLocale);
      }

      if (_conversationMode) {
        _turn.nextTurn();
        if (mounted) setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _voiceStatus = 'Phiên dịch thất bại');
      _snack('Phiên dịch thất bại: $e');
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  Future<void> _speakText(String text, String locale) async {
    if (text.trim().isEmpty) return;
    try {
      await _tts.stop();
      await _tts.awaitSpeakCompletion(true);
      if (locale != 'auto') {
        final available = await _tts.isLanguageAvailable(locale);
        if (available == false || available == 0) {
          _snack('Máy chưa có giọng TTS $locale. Hãy cài giọng nói ngôn ngữ này trong cài đặt Android.');
          return;
        }
        await _tts.setLanguage(locale);
      }
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);
      await _tts.speak(text);
    } catch (e) {
      _snack('Không phát được giọng $locale: $e');
    }
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
      _syncTurnPair();
    });
  }

  void _swapConversationTurn() {
    setState(() {
      _turn.swapTurn();
      _voiceStatus = 'Đã đổi lượt. Đang chờ ${_turn.sourceLanguage}.';
    });
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    _speech.cancel();
    _inputController.dispose();
    _outputController.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phiên dịch trực tiếp'),
        actions: [
          IconButton(
            tooltip: 'Đổi hai ngôn ngữ',
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
                    onSourceChanged: (value) {
                      setState(() {
                        _sourceLanguage = value;
                        _syncTurnPair();
                      });
                    },
                    onTargetChanged: (value) {
                      setState(() {
                        _targetLanguage = value;
                        _syncTurnPair();
                      });
                    },
                    onSwap: _swapLanguages,
                  ),
                  const SizedBox(height: 12),
                  if (_conversationMode) _buildTurnCard(theme),
                  if (_conversationMode) const SizedBox(height: 12),
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
                            title: const Text('Phiên dịch hai chiều theo lượt'),
                            subtitle: const Text(
                              'Khóa ASR theo đúng ngôn ngữ từng người: A → B rồi B → A. Không tự đoán ngôn ngữ từ transcript.',
                            ),
                            value: _conversationMode,
                            onChanged: (value) {
                              setState(() {
                                _conversationMode = value;
                                _syncTurnPair();
                              });
                            },
                          ),
                          const Divider(height: 1),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Tự động nói bản dịch'),
                            subtitle: const Text('Bản dịch được phát bằng TTS đúng locale đích.'),
                            value: _autoSpeak,
                            onChanged: (value) => setState(() => _autoSpeak = value),
                          ),
                          const Divider(height: 1),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Dịch hội thoại tự nhiên'),
                            subtitle: const Text('Giữ đúng ý nhưng diễn đạt tự nhiên cho giao tiếp trực tiếp.'),
                            value: _naturalSpeech,
                            onChanged: (value) => setState(() => _naturalSpeech = value),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(_voiceReady ? Icons.graphic_eq_rounded : Icons.mic_off_outlined),
                            title: Text(_voiceStatus),
                            subtitle: Text('Backend dịch: $_backend'),
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

  Widget _buildTurnCard(ThemeData theme) {
    return Card(
      color: theme.colorScheme.primaryContainer.withOpacity(0.55),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.record_voice_over_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lượt hiện tại: ${_turn.sourceLanguage}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text('Nghe ${_turn.sourceLocale} → dịch và nói ${_turn.targetLanguage} (${_turn.targetLocale})'),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: _listening ? null : _swapConversationTurn,
              icon: const Icon(Icons.swap_calls_rounded),
              label: const Text('Đổi lượt'),
            ),
          ],
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
                Expanded(
                  child: Text(
                    _conversationMode ? 'Người đang nói: ${_turn.sourceLanguage}' : 'Nội dung gốc',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _inputController.clear();
                    _outputController.clear();
                    setState(() {});
                  },
                  child: const Text('Xóa'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _inputController,
              minLines: 5,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: _conversationMode
                    ? 'Giữ mic và nói bằng ${_turn.sourceLanguage}…'
                    : 'Nhập nội dung hoặc giữ nút mic để nói…',
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _translating ? null : () => _translateCurrentInput(),
                    icon: _translating
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.translate_rounded),
                    label: const Text('Dịch ngay'),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onLongPressStart: (_) => unawaited(_startListening()),
                  onLongPressEnd: (_) => unawaited(_stopListening()),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: _listening ? Colors.red : theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_listening ? Icons.graphic_eq_rounded : Icons.mic_rounded, color: Colors.white, size: 29),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _listening ? 'Đang nghe đúng ${_conversationMode ? _turn.sourceLanguage : _sourceLanguage}' : 'Giữ mic để nói • Thả để nhận dạng và dịch',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                Expanded(
                  child: Text(
                    _conversationMode ? 'Nói cho: ${_turn.targetLanguage}' : 'Bản dịch',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Phát lại bản dịch',
                  onPressed: _outputController.text.trim().isEmpty
                      ? null
                      : () => _speakText(
                            _outputController.text,
                            _conversationMode ? _turn.targetLocale : (_languages[_targetLanguage] ?? 'en-US'),
                          ),
                  icon: const Icon(Icons.volume_up_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _outputController,
              readOnly: true,
              minLines: 5,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: 'Bản dịch sẽ xuất hiện ở đây',
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageBar extends StatelessWidget {
  const _LanguageBar({
    required this.source,
    required this.target,
    required this.languages,
    required this.onSourceChanged,
    required this.onTargetChanged,
    required this.onSwap,
  });

  final String source;
  final String target;
  final List<String> languages;
  final ValueChanged<String> onSourceChanged;
  final ValueChanged<String> onTargetChanged;
  final VoidCallback onSwap;

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
                  items: languages.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (value) {
                    if (value != null) onSourceChanged(value);
                  },
                ),
              ),
            ),
            IconButton(onPressed: onSwap, icon: const Icon(Icons.swap_horiz_rounded)),
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
