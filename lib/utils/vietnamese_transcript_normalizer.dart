class TranscriptNormalization {
  final String raw;
  final String normalized;
  final bool changed;
  final List<String> corrections;

  const TranscriptNormalization({
    required this.raw,
    required this.normalized,
    required this.changed,
    required this.corrections,
  });
}

/// Chuẩn hóa có ngữ cảnh cho transcript tiếng Việt.
///
/// Không cố "sửa văn" tùy ý. Chỉ sửa các nhầm lẫn âm học đã quan sát được
/// khi có đủ tín hiệu intent xung quanh, đặc biệt nhóm realtime tools.
class VietnameseTranscriptNormalizer {
  static TranscriptNormalization normalize(String input) {
    var text = input.trim().replaceAll(RegExp(r'\s+'), ' ');
    final raw = text;
    final corrections = <String>[];
    var lower = text.toLowerCase();

    bool containsAny(Iterable<String> phrases) {
      return phrases.any((phrase) => lower.contains(phrase));
    }

    final lotteryContext = containsAny(<String>[
      'kết quả',
      'xổ số',
      'sổ số',
      'sổ xố',
      'xổ xố',
      'xsmb',
      'xsmn',
      'xsmt',
      'giải đặc biệt',
      'miền bắc',
      'miền nam',
      'miền trung',
      'miền mắt',
      'miền mắc',
      'miền bắt',
    ]);

    if (lotteryContext) {
      final lotteryPatterns = <RegExp, String>{
        RegExp(r'(sổ\s*xố|sổ\s*số|sổ\s*xổ|sửa\s*sổ|sửa\s*số|xổ\s*xố)', caseSensitive: false): 'xổ số',
        RegExp(r'sổ\s+xổ', caseSensitive: false): 'xổ số',
      };
      lotteryPatterns.forEach((pattern, replacement) {
        if (pattern.hasMatch(text)) {
          text = text.replaceAll(pattern, replacement);
          corrections.add('Chuẩn hóa cụm “xổ số”');
        }
      });

      // Các lỗi cloud STT đã quan sát: "miền mắt/mắc/bắt" khi người dùng nói
      // "miền Bắc". Chỉ sửa trong ngữ cảnh xổ số để không phá câu bình thường.
      final northPattern = RegExp(
        r'miền\s+(mắt|mắc|bắt|bát|bắc)',
        caseSensitive: false,
      );
      if (northPattern.hasMatch(text)) {
        text = text.replaceAll(northPattern, 'miền Bắc');
        corrections.add('Chuẩn hóa “miền Bắc” theo ngữ cảnh xổ số');
      }
    }

    lower = text.toLowerCase();
    final carrierContext = containsAny(<String>[
      'nhà mạng',
      'mạng nào',
      'mạng gì',
      'đầu số',
      'số điện thoại',
    ]);
    if (carrierContext) {
      text = text.replaceAll(
        RegExp(r'nhà\s*mạng\s*nào', caseSensitive: false),
        'mạng nào',
      );
    }

    text = text
        .replaceAll(RegExp(r'miền\s+bắc', caseSensitive: false), 'miền Bắc')
        .replaceAll(RegExp(r'miền\s+nam', caseSensitive: false), 'miền Nam')
        .replaceAll(RegExp(r'miền\s+trung', caseSensitive: false), 'miền Trung')
        .replaceAll(RegExp(r'tỉ\s+giá', caseSensitive: false), 'tỷ giá');

    return TranscriptNormalization(
      raw: raw,
      normalized: text,
      changed: raw != text,
      corrections: corrections,
    );
  }
}
