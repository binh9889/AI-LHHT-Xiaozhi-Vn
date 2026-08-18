/// Dọn văn bản trước khi hiển thị/đọc thành tiếng.
///
/// Mục tiêu là loại bỏ các dấu Markdown/command nội bộ mà backend Xiaozhi
/// đôi khi gửi trong `tts.sentence_start`, nhưng không "viết lại" nội dung.
class ResponseTextSanitizer {
  const ResponseTextSanitizer._();

  static bool isInternalToolCommand(String input) {
    final value = input.trim();
    if (value.isEmpty) return false;
    return RegExp(
      r'^%\s*(weather|gold_price|search_knowledge|search_music|lottery|news|crypto|currency|stock|tool)[\w.-]*\s*\.{0,3}\s*$',
      caseSensitive: false,
    ).hasMatch(value);
  }

  static String clean(String input, {bool compact = false}) {
    var text = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (text.isEmpty || isInternalToolCommand(text)) return '';

    // Markdown emphasis / inline-code thường bị đọc thành "sao sao" hoặc
    // xuất hiện nguyên `**` trong bong bóng chat.
    text = text
        .replaceAllMapped(RegExp(r'\*\*([^*\n]+)\*\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'__([^_\n]+)__'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'\*([^*\n]+)\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'_([^_\n]+)_'), (m) => m.group(1) ?? '')
        .replaceAll('`', '');

    // Heading/list markdown -> văn bản thuần, dễ đọc hơn bằng TTS.
    text = text
        .replaceAll(RegExp(r'(?m)^\s{0,3}#{1,6}\s*'), '')
        .replaceAll(RegExp(r'(?m)^\s*[-*+]\s+'), '• ')
        .replaceAll(RegExp(r'(?m)^\s*>\s?'), '');

    // Loại command marker bị lẫn đầu câu nhưng giữ phần nội dung phía sau.
    text = text.replaceAll(
      RegExp(r'(?im)^\s*%\s*[a-z_][\w.-]*\.{0,3}\s*\n?'),
      '',
    );

    // Dọn khoảng trắng/dấu câu bị lặp do ghép nhiều sentence_start.
    text = text
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n[ \t]+'), '\n')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAllMapped(
          RegExp(r'([!?.,])\1{1,}'),
          (match) => match.group(1) ?? '',
        )
        .trim();

    if (compact) {
      text = text
          .replaceAll(RegExp(r'\s*\n\s*'), ' ')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();
    }
    return text;
  }

  /// Giới hạn câu trả lời dữ liệu realtime để không biến một kết quả ngắn
  /// thành nhiều đoạn bình luận. Chỉ dùng khi đã biết đây là tool response.
  static String limitSentences(
    String input, {
    int maxSentences = 2,
    int maxChars = 420,
  }) {
    final value = clean(input, compact: true);
    if (value.isEmpty) return '';
    final parts = RegExp(r'[^.!?]+[.!?]?')
        .allMatches(value)
        .map((m) => (m.group(0) ?? '').trim())
        .where((part) => part.isNotEmpty)
        .take(maxSentences)
        .toList();
    var result = parts.isEmpty ? value : parts.join(' ');
    if (result.length > maxChars) {
      result = '${result.substring(0, maxChars).trimRight()}…';
    }
    return result;
  }

  /// Ghép các mảnh TTS thành một câu/bubble duy nhất, tránh mỗi sentence_start
  /// thành một bong bóng khiến kết quả bị dài và rời rạc.
  static String joinSentences(Iterable<String> parts) {
    final cleaned = <String>[];
    for (final part in parts) {
      final value = clean(part, compact: true);
      if (value.isEmpty) continue;
      if (cleaned.isNotEmpty && cleaned.last == value) continue;
      cleaned.add(value);
    }
    return clean(cleaned.join(' '), compact: true);
  }
}
