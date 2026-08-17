import 'dart:convert';

import 'package:ai_assistant/providers/config_provider.dart';
import 'package:ai_assistant/services/dify_service.dart';
import 'package:ai_assistant/services/minimax_service.dart';
import 'package:ai_assistant/services/xiaozhi_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TranslationResult {
  final String text;
  final String backend;

  const TranslationResult({required this.text, required this.backend});
}

class ConversationTranslationResult extends TranslationResult {
  final String sourceLanguage;
  final String targetLanguage;
  final String targetLocale;

  const ConversationTranslationResult({
    required super.text,
    required super.backend,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.targetLocale,
  });
}

/// Dịch hai chiều cho AI-LHHT.
///
/// v3.4 không còn dùng Xiaozhi `listen/detect` như một API text-chat giả để
/// phiên dịch. MiniMax/Dify vẫn được ưu tiên nếu người dùng đã cấu hình; trên
/// Android, Google ML Kit on-device là fallback độc lập và ổn định.
class TranslationService {
  TranslationService(this.configProvider);

  final ConfigProvider configProvider;

  static const MethodChannel _mlKitChannel = MethodChannel(
    'com.lhht.ai_assistant/mlkit_translation',
  );

  bool get _supportsOnDeviceTranslation =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get isAvailable =>
      configProvider.minimaxConfigs.isNotEmpty ||
      configProvider.difyConfigs.isNotEmpty ||
      _supportsOnDeviceTranslation;

  String get availableBackends {
    final names = <String>[];
    if (configProvider.minimaxConfigs.isNotEmpty) names.add('MiniMax');
    if (configProvider.difyConfigs.isNotEmpty) names.add('Dify');
    if (_supportsOnDeviceTranslation) names.add('ML Kit trên máy');
    return names.isEmpty ? 'Chưa có backend tương thích' : names.join(' • ');
  }

  Future<TranslationResult> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
    bool naturalSpeech = true,
    XiaozhiService? existingXiaozhi,
  }) async {
    final input = text.trim();
    if (input.isEmpty) {
      throw Exception('Nội dung cần dịch đang trống.');
    }

    // Nếu đã cấu hình LLM, dùng LLM để có câu hội thoại tự nhiên hơn.
    // Nếu API chậm/lỗi hoặc chưa cấu hình, rơi xuống ML Kit thay vì dùng
    // text-injection không thuộc protocol Xiaozhi.
    if (configProvider.minimaxConfigs.isNotEmpty ||
        configProvider.difyConfigs.isNotEmpty) {
      final prompt = _buildPrompt(
        input,
        sourceLanguage,
        targetLanguage,
        naturalSpeech,
      );
      try {
        final result = await _invokeAiPrompt(prompt);
        final cleaned = _clean(result.text);
        if (cleaned.isNotEmpty) {
          return TranslationResult(text: cleaned, backend: result.backend);
        }
      } catch (_) {
        // Fallback on-device bên dưới.
      }
    }

    return _translateOnDevice(
      input,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
  }

  Future<ConversationTranslationResult> translateConversationTurn({
    required String text,
    required String languageA,
    required String localeA,
    required String languageB,
    required String localeB,
    bool naturalSpeech = true,
    XiaozhiService? existingXiaozhi,
  }) async {
    final input = text.trim();
    if (input.isEmpty) {
      throw Exception('Không có câu nói để phiên dịch.');
    }

    // Chế độ hội thoại v3.3+ ưu tiên khóa ASR theo lượt. Hàm này vẫn hỗ trợ
    // màn hình cũ/auto bằng heuristic, nhưng không gọi Xiaozhi text API.
    if (_canGuessDirection(localeA, localeB)) {
      final fromA = _guessLanguageA(input, localeA, localeB);
      final direct = await translate(
        text: input,
        sourceLanguage: fromA ? languageA : languageB,
        targetLanguage: fromA ? languageB : languageA,
        naturalSpeech: naturalSpeech,
        existingXiaozhi: existingXiaozhi,
      );
      return ConversationTranslationResult(
        text: direct.text,
        backend: direct.backend,
        sourceLanguage: fromA ? languageA : languageB,
        targetLanguage: fromA ? languageB : languageA,
        targetLocale: fromA ? localeB : localeA,
      );
    }

    // Với cặp Latin khó đoán, nếu có LLM thì cho LLM xác định chiều. Nếu
    // không có, giữ fallback A → B để tránh một lỗi JSON làm treo phiên dịch.
    if (configProvider.minimaxConfigs.isNotEmpty ||
        configProvider.difyConfigs.isNotEmpty) {
      final style = naturalSpeech
          ? 'Dịch tự nhiên như người thật đang hội thoại, giữ nguyên tên riêng, số liệu và ý nghĩa.'
          : 'Dịch sát nghĩa, không tự thêm nội dung.';
      final prompt = '''Bạn là bộ phiên dịch hai chiều thời gian thực.
Hai ngôn ngữ của phiên dịch viên là:
A = $languageA
B = $languageB

Nhiệm vụ:
1. Xác định câu người dùng vừa nói chủ yếu là A hay B.
2. Nếu là A, dịch sang B. Nếu là B, dịch sang A.
3. $style
4. Không trả lời nội dung câu nói, chỉ phiên dịch nó.
5. Chỉ trả về đúng một JSON hợp lệ, không markdown, theo mẫu:
{"source":"A","translation":"..."}
hoặc
{"source":"B","translation":"..."}

Câu cần phiên dịch:
$input''';
      try {
        final raw = await _invokeAiPrompt(prompt);
        final parsed = _parseConversationJson(raw.text);
        final source = (parsed['source'] ?? '').toString().toUpperCase();
        final translated = (parsed['translation'] ?? '').toString().trim();
        if ((source == 'A' || source == 'B') && translated.isNotEmpty) {
          final fromA = source == 'A';
          return ConversationTranslationResult(
            text: translated,
            backend: raw.backend,
            sourceLanguage: fromA ? languageA : languageB,
            targetLanguage: fromA ? languageB : languageA,
            targetLocale: fromA ? localeB : localeA,
          );
        }
      } catch (_) {}
    }

    final direct = await translate(
      text: input,
      sourceLanguage: languageA,
      targetLanguage: languageB,
      naturalSpeech: naturalSpeech,
      existingXiaozhi: existingXiaozhi,
    );
    return ConversationTranslationResult(
      text: direct.text,
      backend: direct.backend,
      sourceLanguage: languageA,
      targetLanguage: languageB,
      targetLocale: localeB,
    );
  }

  Future<TranslationResult> _invokeAiPrompt(String prompt) async {
    if (configProvider.minimaxConfigs.isNotEmpty) {
      final config = configProvider.minimaxConfigs.first;
      final service = MiniMaxService(apiKey: config.apiKey, model: config.model);
      final response = await service.sendMessage(
        prompt,
        sessionId: 'translation_${DateTime.now().millisecondsSinceEpoch}',
        forceNewConversation: true,
      );
      return TranslationResult(text: response, backend: 'MiniMax');
    }

    if (configProvider.difyConfigs.isNotEmpty) {
      final config = configProvider.difyConfigs.first;
      final service = await DifyService.create(
        apiKey: config.apiKey,
        apiUrl: config.apiUrl,
      );
      final response = await service.sendMessage(
        prompt,
        sessionId: 'translation_${DateTime.now().millisecondsSinceEpoch}',
        forceNewConversation: true,
      );
      return TranslationResult(text: response, backend: 'Dify');
    }

    throw Exception('Không có backend AI dạng text đã cấu hình.');
  }

  Future<TranslationResult> _translateOnDevice(
    String text, {
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    if (!_supportsOnDeviceTranslation) {
      throw Exception(
        'Thiết bị này chưa có backend dịch on-device. Hãy cấu hình MiniMax hoặc Dify.',
      );
    }

    final sourceTag = _languageTag(sourceLanguage);
    final targetTag = _languageTag(targetLanguage);
    if (sourceTag == null || targetTag == null) {
      throw Exception(
        'Chưa hỗ trợ dịch $sourceLanguage → $targetLanguage trên thiết bị.',
      );
    }

    try {
      final translated = await _mlKitChannel.invokeMethod<String>('translate', {
        'text': text,
        'sourceTag': sourceTag,
        'targetTag': targetTag,
      }).timeout(const Duration(seconds: 45));
      final output = translated?.trim() ?? '';
      if (output.isEmpty) {
        throw Exception('ML Kit trả bản dịch trống.');
      }
      return TranslationResult(text: output, backend: 'ML Kit trên máy');
    } on PlatformException catch (e) {
      final code = e.code;
      if (code == 'MODEL_DOWNLOAD_FAILED') {
        throw Exception(
          'Không tải được model dịch lần đầu. Hãy bật mạng rồi thử lại.',
        );
      }
      throw Exception(e.message ?? 'Dịch trên thiết bị thất bại ($code).');
    } on MissingPluginException {
      throw Exception('APK hiện tại chưa tích hợp ML Kit Translation.');
    }
  }

  String? _languageTag(String language) {
    final value = language.trim().toLowerCase();
    if (value == 'tiếng việt' || value.startsWith('vi-') || value == 'vi') {
      return 'vi';
    }
    if (value == 'english' || value.startsWith('en-') || value == 'en') {
      return 'en';
    }
    if (value == '中文' || value.contains('trung') || value.startsWith('zh')) {
      return 'zh';
    }
    if (value == '日本語' || value.contains('nhật') || value.startsWith('ja')) {
      return 'ja';
    }
    if (value == '한국어' || value.contains('hàn') || value.startsWith('ko')) {
      return 'ko';
    }
    if (value == 'français' || value.contains('pháp') || value.startsWith('fr')) {
      return 'fr';
    }
    if (value == 'deutsch' || value.contains('đức') || value.startsWith('de')) {
      return 'de';
    }
    if (value == 'español' || value.contains('tây ban nha') || value.startsWith('es')) {
      return 'es';
    }
    if (value == 'ไทย' || value.contains('thái') || value.startsWith('th')) {
      return 'th';
    }
    if (value == 'русский' || value.contains('nga') || value.startsWith('ru')) {
      return 'ru';
    }
    return null;
  }

  String _buildPrompt(
    String text,
    String source,
    String target,
    bool naturalSpeech,
  ) {
    final style = naturalSpeech
        ? 'Ưu tiên cách nói tự nhiên như hội thoại, giữ đúng ý, tên riêng, số liệu và sắc thái.'
        : 'Dịch sát nghĩa, giữ nguyên cấu trúc và thuật ngữ khi có thể.';

    return '''Bạn đang ở chế độ PHIÊN DỊCH CHUYÊN NGHIỆP.
Hãy dịch nội dung từ $source sang $target.
$style
Chỉ trả về BẢN DỊCH CUỐI CÙNG. Không giải thích, không thêm tiêu đề, không đặt trong dấu ngoặc kép.

Nội dung:
$text''';
  }

  Map<String, dynamic> _parseConversationJson(String value) {
    var text = _clean(value);
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      text = text.substring(start, end + 1);
    }
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      return decoded.map((key, val) => MapEntry(key.toString(), val));
    }
    throw const FormatException('Phản hồi phiên dịch không phải JSON object.');
  }

  bool _canGuessDirection(String localeA, String localeB) {
    final a = localeA.toLowerCase();
    final b = localeB.toLowerCase();
    return a.startsWith('vi') ||
        b.startsWith('vi') ||
        a.startsWith('zh') ||
        b.startsWith('zh') ||
        a.startsWith('ja') ||
        b.startsWith('ja') ||
        a.startsWith('ko') ||
        b.startsWith('ko');
  }

  bool _guessLanguageA(String text, String localeA, String localeB) {
    final a = localeA.toLowerCase();
    final b = localeB.toLowerCase();

    if (a.startsWith('vi') || b.startsWith('vi')) {
      final looksVi = RegExp(
            r'[ăâđêôơưáàảãạấầẩẫậắằẳẵặéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ]',
            caseSensitive: false,
          ).hasMatch(text) ||
          RegExp(
            r'\b(tôi|mình|bạn|anh|chị|em|không|có|là|và|được|muốn|cần|hôm nay|xin chào)\b',
            caseSensitive: false,
          ).hasMatch(text);
      return a.startsWith('vi') ? looksVi : !looksVi;
    }

    final hasHan = RegExp(r'[\u4E00-\u9FFF]').hasMatch(text);
    if (a.startsWith('zh') || b.startsWith('zh')) {
      return a.startsWith('zh') ? hasHan : !hasHan;
    }

    final hasKana = RegExp(r'[\u3040-\u30FF]').hasMatch(text);
    if (a.startsWith('ja') || b.startsWith('ja')) {
      return a.startsWith('ja') ? hasKana : !hasKana;
    }

    final hasHangul = RegExp(r'[\uAC00-\uD7AF]').hasMatch(text);
    if (a.startsWith('ko') || b.startsWith('ko')) {
      return a.startsWith('ko') ? hasHangul : !hasHangul;
    }

    return true;
  }

  String _clean(String value) {
    var output = value.trim();
    if (output.startsWith('```') && output.endsWith('```')) {
      output = output.replaceFirst(RegExp(r'^```[^\n]*\n?'), '');
      output = output.replaceFirst(RegExp(r'\n?```$'), '');
    }
    return output.trim();
  }
}
