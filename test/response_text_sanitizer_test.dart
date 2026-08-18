import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/utils/response_text_sanitizer.dart';

void main() {
  test('removes markdown emphasis before display or TTS', () {
    final cleaned = ResponseTextSanitizer.clean(
      '**Nhiệt độ:** 29°C. __Độ ẩm:__ 71%.',
      compact: true,
    );
    expect(cleaned, isNot(contains('**')));
    expect(cleaned, isNot(contains('__')));
    expect(cleaned, contains('Nhiệt độ: 29°C'));
  });

  test('hides internal percent tool commands', () {
    expect(ResponseTextSanitizer.clean('% weather...'), isEmpty);
    expect(ResponseTextSanitizer.clean('% search_knowledge...'), isEmpty);
  });

  test('joins fragmented TTS into one clean reply', () {
    final joined = ResponseTextSanitizer.joinSentences([
      '% weather...',
      '**Nhiệt độ:** 29°C.',
      'Độ ẩm 71%.',
    ]);
    expect(joined, 'Nhiệt độ: 29°C. Độ ẩm 71%.');
  });

  test('limits realtime tool verbosity without touching normal sanitizer', () {
    final limited = ResponseTextSanitizer.limitSentences(
      'Nhiệt độ 29°C. Độ ẩm 71%. Đây là một câu bình luận dài không cần thiết. Câu thứ tư.',
    );
    expect(limited, 'Nhiệt độ 29°C. Độ ẩm 71%.');
  });
}
