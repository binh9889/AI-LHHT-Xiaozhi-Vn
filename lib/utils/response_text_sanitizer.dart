/// Dọn văn bản trước khi hiển thị/đọc thành tiếng.
///
/// Bản này cố ý dùng các phép biến đổi đơn giản, xác định được thay vì regex
/// phức tạp để tránh khác biệt RegExp giữa môi trường test/build.
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

    // Loại Markdown emphasis / inline-code. Làm theo marker literal để kết quả
    // ổn định và không phụ thuộc capture/back-reference.
    text = text
        .replaceAll('**', '')
        .replaceAll('__', '')
        .replaceAll('`', '');

    // Xử lý emphasis đơn còn sót. Chỉ bỏ marker, không viết lại nội dung.
    text = text.replaceAll('*', '');

    // Heading / quote / list marker ở đầu dòng.
    final lines = <String>[];
    for (final rawLine in text.split('\n')) {
      var line = rawLine.trimRight();
      line = line.replaceFirst(RegExp(r'^\s*#{1,6}\s*'), '');
      line = line.replaceFirst(RegExp(r'^\s*>\s?'), '');
      line = line.replaceFirst(RegExp(r'^\s*[-+]\s+'), '• ');
      lines.add(line);
    }
    text = lines.join('\n');

    // Command nội bộ đứng đầu một dòng: bỏ cả dòng đó.
    final kept = <String>[];
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (isInternalToolCommand(line)) continue;
      kept.add(rawLine);
    }
    text = kept.join('\n');

    // Dọn khoảng trắng.
    text = text
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n[ \t]+'), '\n')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    // Dọn dấu câu lặp mà không dùng back-reference.
    while (text.contains('..')) text = text.replaceAll('..', '.');
    while (text.contains('!!')) text = text.replaceAll('!!', '!');
    while (text.contains('??')) text = text.replaceAll('??', '?');
    while (text.contains(',,')) text = text.replaceAll(',,', ',');

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

    final parts = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final ch = value[i];
      buffer.write(ch);
      if (ch == '.' || ch == '!' || ch == '?') {
        final sentence = buffer.toString().trim();
        if (sentence.isNotEmpty) parts.add(sentence);
        buffer.clear();
        if (parts.length >= maxSentences) break;
      }
    }
    if (parts.length < maxSentences) {
      final tail = buffer.toString().trim();
      if (tail.isNotEmpty) parts.add(tail);
    }

    var result = parts.isEmpty
        ? value
        : parts.take(maxSentences).join(' ').trim();
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
