import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:ai_assistant/services/voice_output_preferences.dart';

/// Một TTS duy nhất cho toàn app.
///
/// v4.0.x có hai đường phát tiếng:
/// - Agent Xiaozhi phát audio cloud.
/// - Tool/Interpreter dùng FlutterTts của điện thoại.
/// Vì vậy người dùng có thể nghe hai giọng khác nhau và hai audio pipeline có
/// thể giành audio-focus. v4.1 gom mọi câu trả lời về một hàng đợi TTS duy nhất
/// khi bật "Giọng ổn định".
class UnifiedSpeechOutputService {
  UnifiedSpeechOutputService._();

  static final UnifiedSpeechOutputService instance =
      UnifiedSpeechOutputService._();

  final FlutterTts _tts = FlutterTts();
  final VoiceOutputPreferences _preferences = VoiceOutputPreferences();

  bool _initialized = false;
  bool _available = false;
  Future<void> _tail = Future<void>.value();
  int _generation = 0;
  String _lastLocale = '';
  String _lastVoice = '';

  bool get isAvailable => _available;
  String get lastLocale => _lastLocale;
  String get lastVoice => _lastVoice;

  Future<bool> initialize({String locale = 'vi-VN'}) async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      _available = await _configureLocale(locale);
    } catch (_) {
      _available = false;
    }
    return _available;
  }

  Future<bool> canSpeakLocale(String locale) async {
    try {
      final result = await _tts.isLanguageAvailable(locale);
      return result == true || result == 1;
    } catch (_) {
      return false;
    }
  }

  /// Phát tuần tự, không để câu Tool/Agent/Interpreter chồng lên nhau.
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    if (!_initialized) {
      await initialize(locale: locale);
    }
    if (!await _configureLocale(locale)) {
      throw StateError('TTS hệ thống không khả dụng cho $locale.');
    }

    final myGeneration = _generation;
    _tail = _tail.then((_) async {
      if (myGeneration != _generation) return;
      final localeReady = await _configureLocale(locale);
      if (!localeReady || myGeneration != _generation) return;

      // Một lần retry nhẹ nếu engine Android vừa mất audio-focus.
      try {
        final result = await _tts.speak(clean, focus: true);
        if (result == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          if (myGeneration == _generation) await _tts.speak(clean, focus: true);
        }
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (myGeneration == _generation) await _tts.speak(clean, focus: true);
      }
    });
    return _tail;
  }

  Future<void> stop() async {
    _generation++;
    _tail = Future<void>.value();
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<bool> _configureLocale(String locale) async {
    if (!await canSpeakLocale(locale)) return false;
    try {
      await _tts.setLanguage(locale);
      _lastLocale = locale;
      await _selectStableVoice(locale);
      _available = true;
      return true;
    } catch (_) {
      _available = false;
      return false;
    }
  }

  Future<void> _selectStableVoice(String locale) async {
    try {
      final dynamic rawVoices = await _tts.getVoices;
      if (rawVoices is! List) return;
      final language = locale.toLowerCase().split(RegExp('[-_]')).first;
      final candidates = <Map<String, String>>[];
      for (final dynamic item in rawVoices) {
        if (item is! Map) continue;
        final name = (item['name'] ?? '').toString();
        final voiceLocale = (item['locale'] ?? '').toString();
        if (name.isEmpty || voiceLocale.isEmpty) continue;
        final normalizedLocale = voiceLocale.toLowerCase();
        if (normalizedLocale == locale.toLowerCase() ||
            normalizedLocale.startsWith('$language-') ||
            normalizedLocale.startsWith('${language}_') ||
            normalizedLocale == language) {
          candidates.add({'name': name, 'locale': voiceLocale});
        }
      }
      if (candidates.isEmpty) return;
      candidates.sort((a, b) => a['name']!.compareTo(b['name']!));

      final saved = await _preferences.preferredVoiceFor(locale);
      Map<String, String>? selected;
      if (saved != null && saved.isNotEmpty) {
        for (final candidate in candidates) {
          if (candidate['name'] == saved) {
            selected = candidate;
            break;
          }
        }
      }
      final chosen = selected ?? candidates.first;
      await _tts.setVoice({
        'name': chosen['name']!,
        'locale': chosen['locale']!,
      });
      _lastVoice = chosen['name']!;
      if (saved == null || saved.isEmpty) {
        await _preferences.setPreferredVoiceFor(locale, _lastVoice);
      }
    } catch (_) {
      // Không chọn được voice cụ thể thì vẫn giữ setLanguage(locale).
    }
  }
}
