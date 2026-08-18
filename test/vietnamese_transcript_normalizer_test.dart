import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/utils/vietnamese_transcript_normalizer.dart';

void main() {
  test('repairs observed lottery ASR errors only in lottery context', () {
    final result = VietnameseTranscriptNormalizer.normalize(
      'Alo AI tra cho tao kết quả sổ số miền mắt hôm nay',
    );
    expect(result.normalized.toLowerCase(), contains('xổ số miền bắc'));
    expect(result.changed, isTrue);
  });

  test('does not rewrite unrelated normal sentence into lottery intent', () {
    final result = VietnameseTranscriptNormalizer.normalize(
      'mắt hôm nay hơi mỏi',
    );
    expect(result.normalized, 'mắt hôm nay hơi mỏi');
  });

  test('normalizes common exchange-rate spelling variant', () {
    final result = VietnameseTranscriptNormalizer.normalize(
      'tỉ giá USD hôm nay',
    );
    expect(result.normalized, contains('tỷ giá'));
  });
}
