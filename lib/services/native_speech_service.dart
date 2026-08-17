import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Một lớp duy nhất bọc speech_to_text cho toàn ứng dụng.
///
/// Chế độ phiên dịch không được để ASR tự đoán ngôn ngữ. Mỗi lượt nghe sẽ
/// được khóa vào locale cụ thể (vi-VN, zh-CN, en-US...), nhờ vậy câu tiếng
/// Trung không còn bị gửi vào bộ nhận dạng tiếng Việt như ở v3.2.
class NativeSpeechService {
  NativeSpeechService._();

  static final NativeSpeechService instance = NativeSpeechService._();

  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  bool _available = false;
  String _latestWords = '';
  String _lastError = '';
  String _activeLocale = '';
  List<LocaleName> _locales = const [];

  bool get isAvailable => _available;
  bool get isListening => _speech.isListening;
  String get latestWords => _latestWords.trim();
  String get lastError => _lastError;
  String get activeLocale => _activeLocale;

  Future<bool> initialize() async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      _available = await _speech.initialize(
        onError: _onError,
        debugLogging: false,
        options: [SpeechToText.androidIntentLookup],
      );
      if (_available) {
        _locales = await _speech.locales();
      }
    } catch (e) {
      _lastError = e.toString();
      _available = false;
    }
    return _available;
  }

  void _onError(SpeechRecognitionError error) {
    _lastError = '${error.errorMsg}${error.permanent ? ' (permanent)' : ''}';
  }

  /// Tìm locale thực tế gần nhất mà bộ nhận dạng của máy hỗ trợ.
  Future<List<String>> availableLocaleIds() async {
    await initialize();
    return _locales.map((e) => e.localeId).toList(growable: false);
  }

  Future<bool> supportsLocale(String requestedLocale) async {
    final ids = await availableLocaleIds();
    final requested = requestedLocale.toLowerCase();
    final language = requested.split(RegExp('[-_]')).first;
    return ids.any((id) {
      final value = id.toLowerCase();
      return value == requested ||
          value == language ||
          value.startsWith('$language-') ||
          value.startsWith('${language}_');
    });
  }

  Future<String> resolveLocale(String requestedLocale) async {
    await initialize();
    if (_locales.isEmpty) return requestedLocale;

    if (requestedLocale.toLowerCase() == 'auto') {
      final system = await _speech.systemLocale();
      return system?.localeId ?? (_locales.isNotEmpty ? _locales.first.localeId : 'vi-VN');
    }

    final requested = requestedLocale.toLowerCase();
    for (final locale in _locales) {
      if (locale.localeId.toLowerCase() == requested) return locale.localeId;
    }

    final language = requested.split(RegExp('[-_]')).first;
    for (final locale in _locales) {
      final id = locale.localeId.toLowerCase();
      if (id == language || id.startsWith('$language-') || id.startsWith('${language}_')) {
        return locale.localeId;
      }
    }
    return requestedLocale;
  }

  Future<bool> start({
    required String localeId,
    void Function(String words, bool isFinal)? onResult,
  }) async {
    if (!await initialize()) return false;

    if (_speech.isListening) {
      await _speech.cancel();
    }

    _latestWords = '';
    _lastError = '';
    _activeLocale = await resolveLocale(localeId);

    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) _latestWords = words;
          onResult?.call(words, result.finalResult);
        },
        localeId: _activeLocale,
        listenFor: const Duration(seconds: 35),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      );
      return _speech.isListening;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  Future<String> stopAndGetText() async {
    if (!_initialized) return latestWords;
    try {
      if (_speech.isListening) {
        await _speech.stop();
        // Một số Android gửi result cuối ngay sau stop(). Cho callback thời
        // gian rất ngắn để cập nhật từ cuối cùng, không kéo dài UX.
        await Future<void>.delayed(const Duration(milliseconds: 320));
      }
    } catch (e) {
      _lastError = e.toString();
    }
    return latestWords;
  }

  Future<void> cancel() async {
    if (!_initialized) return;
    try {
      if (_speech.isListening) await _speech.cancel();
    } catch (_) {}
    _latestWords = '';
  }
}
