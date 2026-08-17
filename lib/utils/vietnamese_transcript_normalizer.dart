class TranscriptNormalization {
  final String raw;
  final String normalized;
  final bool changed;
  final List<String> corrections;
  const TranscriptNormalization({required this.raw, required this.normalized, required this.changed, required this.corrections});
}

class VietnameseTranscriptNormalizer {
  static TranscriptNormalization normalize(String input) {
    var text = input.trim().replaceAll(RegExp(r'\s+'), ' ');
    final raw = text;
    final corrections = <String>[];

    // Chỉ sửa các nhầm lẫn âm học rất phổ biến khi ngữ cảnh đủ rõ.
    final lotteryContext = RegExp(r'\b(kết quả|miền bắc|miền nam|miền trung|vé|giải đặc biệt|tra)\b', caseSensitive: false).hasMatch(text);
    if (lotteryContext) {
      final patterns = <RegExp, String>{
        RegExp(r'\b(sổ xố|sổ số|sổ xổ|sửa sổ|sửa số|xổ xố)\b', caseSensitive: false): 'xổ số',
        RegExp(r'\bsổ\s+xổ\b', caseSensitive: false): 'xổ số',
      };
      patterns.forEach((pattern, replacement) {
        if (pattern.hasMatch(text)) {
          text = text.replaceAll(pattern, replacement);
          corrections.add('Chuẩn hóa cụm “xổ số”');
        }
      });
    }

    text = text
        .replaceAll(RegExp(r'\bmiền bắc\b', caseSensitive: false), 'miền Bắc')
        .replaceAll(RegExp(r'\bmiền nam\b', caseSensitive: false), 'miền Nam')
        .replaceAll(RegExp(r'\bmiền trung\b', caseSensitive: false), 'miền Trung');

    return TranscriptNormalization(
      raw: raw,
      normalized: text,
      changed: raw != text,
      corrections: corrections,
    );
  }
}
