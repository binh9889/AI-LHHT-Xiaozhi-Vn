import 'dart:async';
import 'package:ai_assistant/providers/config_provider.dart';
import 'package:ai_assistant/services/dify_service.dart';
import 'package:ai_assistant/services/minimax_service.dart';
import 'package:ai_assistant/services/xiaozhi_service.dart';

class TranslationResult {
  final String text;
  final String backend;

  const TranslationResult({required this.text, required this.backend});
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

    // Ưu tiên MiniMax vì API chat-completions ít phụ thuộc cấu hình workflow.
    if (configProvider.minimaxConfigs.isNotEmpty) {
      final config = configProvider.minimaxConfigs.first;
      final service = MiniMaxService(apiKey: config.apiKey, model: config.model);
      final response = await service.sendMessage(
        prompt,
        sessionId: 'translation_${DateTime.now().millisecondsSinceEpoch}',
        forceNewConversation: true,
      );
      return TranslationResult(text: _clean(response), backend: 'MiniMax');
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
      return TranslationResult(text: _clean(response), backend: 'Dify');
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
        for (var i = 0; i < 20 && !service.isConnected; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        if (!service.isConnected) {
          throw Exception('Xiaozhi chưa sẵn sàng để nhận yêu cầu dịch.');
        }
        final response = await service.sendTextMessage(prompt);
        return TranslationResult(text: _clean(response), backend: 'Xiaozhi');
      } finally {
        await service.disconnect();
      }
    }

    throw Exception(
      'Chưa có dịch vụ AI để phiên dịch. Hãy cấu hình MiniMax, Dify hoặc Xiaozhi.',
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

  String _clean(String value) {
    var output = value.trim();
    if (output.startsWith('```') && output.endsWith('```')) {
      output = output.replaceFirst(RegExp(r'^```[^\n]*\n?'), '');
      output = output.replaceFirst(RegExp(r'\n?```$'), '');
    }
    return output.trim();
  }
}
