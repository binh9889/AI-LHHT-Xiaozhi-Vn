import 'dart:convert';

import 'package:ai_assistant/providers/config_provider.dart';
import 'package:ai_assistant/services/dify_service.dart';
import 'package:ai_assistant/services/minimax_service.dart';
import 'package:ai_assistant/services/xiaozhi_service.dart';

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

class TranslationService {
  final ConfigProvider configProvider;

  TranslationService(this.configProvider);

  bool get isAvailable =>
      configProvider.minimaxConfigs.isNotEmpty ||
      configProvider.difyConfigs.isNotEmpty ||
      configProvider.xiaozhiConfigs.isNotEmpty;

  String get availableBackends {
    final names = <String>[];
    if (configProvider.minimaxConfigs.isNotEmpty) names.add('MiniMax');
    if (configProvider.difyConfigs.isNotEmpty) names.add('Dify');
    if (configProvider.xiaozhiConfigs.isNotEmpty) names.add('Xiaozhi');
    return names.isEmpty ? 'Chưa cấu hình' : names.join(' • ');
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

    final prompt = _buildPrompt(
      input,
      sourceLanguage,
      targetLanguage,
      naturalSpeech,
    );
    final result = await _invokePrompt(prompt, existingXiaozhi: existingXiaozhi);
    return TranslationResult(text: _clean(result.text), backend: result.backend);
  }

  /// Một lượt phiên dịch hai chiều. AI tự xác định câu hiện tại thuộc ngôn ngữ
  /// A hay B rồi dịch sang ngôn ngữ còn lại. Đây là API dùng cho chế độ
  /// "Việt ↔ Anh" trực tiếp trong cuộc trò chuyện.
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

    // Với các cặp có thể nhận biết chắc chắn bằng ký tự/từ vựng (đặc biệt
    // Việt ↔ Anh), xác định chiều ngay trên máy. Nhờ vậy nếu backend là
    // Xiaozhi thì server chỉ nói BẢN DỊCH, không đọc một gói JSON kỹ thuật.
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
      final raw = await _invokePrompt(prompt, existingXiaozhi: existingXiaozhi);
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
    } catch (_) {
      // Fallback bên dưới. Không để một lỗi JSON làm hỏng cả phiên dịch.
    }

    final fromA = _guessLanguageA(input, localeA, localeB);
    final fallback = await translate(
      text: input,
      sourceLanguage: fromA ? languageA : languageB,
      targetLanguage: fromA ? languageB : languageA,
      naturalSpeech: naturalSpeech,
      existingXiaozhi: existingXiaozhi,
    );
    return ConversationTranslationResult(
      text: fallback.text,
      backend: fallback.backend,
      sourceLanguage: fromA ? languageA : languageB,
      targetLanguage: fromA ? languageB : languageA,
      targetLocale: fromA ? localeB : localeA,
    );
  }

  Future<TranslationResult> _invokePrompt(
    String prompt, {
    XiaozhiService? existingXiaozhi,
  }) async {
    // Ưu tiên backend API nếu người dùng đã cấu hình vì nó không làm gián đoạn
    // luồng audio WebSocket đang dùng làm ASR.
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

    if (existingXiaozhi != null && existingXiaozhi.isConnected) {
      final response = await existingXiaozhi.sendTextMessageSilently(prompt);
      return TranslationResult(text: response, backend: 'Xiaozhi');
    }

    if (configProvider.xiaozhiConfigs.isNotEmpty) {
      final config = configProvider.xiaozhiConfigs.first;
      final service = XiaozhiService(
        websocketUrl: config.websocketUrl,
        macAddress: config.macAddress,
        clientId: config.clientId,
        token: config.token,
      );
      try {
        await service.connect();
        for (var i = 0; i < 30 && !service.isConnected; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        if (!service.isConnected) {
          throw Exception('Xiaozhi chưa sẵn sàng để nhận yêu cầu dịch.');
        }
        final response = await service.sendTextMessageSilently(prompt);
        return TranslationResult(text: response, backend: 'Xiaozhi');
      } finally {
        await service.disconnect();
      }
    }

    throw Exception(
      'Chưa có dịch vụ AI để phiên dịch. Hãy cấu hình Xiaozhi, MiniMax hoặc Dify.',
    );
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

    // Với các cặp Latin khó phân biệt, ưu tiên A. LLM thường đã xử lý được
    // trước khi rơi xuống fallback này.
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
