import 'package:ai_assistant/tools/models/tool_models.dart';
import 'package:ai_assistant/tools/tool_registry.dart';
import 'package:ai_assistant/utils/vietnamese_transcript_normalizer.dart';

class ToolIntentRouter {
  const ToolIntentRouter();

  ToolRoute? route(String raw) {
    final normalized = VietnameseTranscriptNormalizer.normalize(raw).normalized.trim();
    if (normalized.isEmpty) return null;
    final q = normalized.toLowerCase();

    ToolRoute hit(String id, double confidence, [Map<String, String> params = const {}]) {
      return ToolRoute(toolId: id, confidence: confidence, parameters: params, reason: normalized);
    }

    if (_matches(q, r'\b(xổ\s*số|sổ\s*xố|sổ\s*số|xổ\s*xố|xsmb|xsmn|xsmt|kết\s*quả\s*xổ)\b')) {
      final region = q.contains('miền nam') || q.contains('xsmn')
          ? 'south'
          : q.contains('miền trung') || q.contains('xsmt')
              ? 'central'
              : 'north';
      return hit('vn_lottery', .98, {'region': region});
    }
    if (_matches(q, r'\b(lịch\s*âm|âm\s*lịch|ngày\s*âm|can\s*chi)\b')) {
      return hit('lunar_calendar', .97);
    }
    if (_matches(q, r'\b(mã\s*vùng|area\s*code|đầu\s*số\s*cố\s*định)\b')) {
      return hit('vn_area_code', .96);
    }
    if (_matches(q, r'\b(nhà\s*mạng|mạng\s*gì|mạng\s*nào|thuộc\s*mạng|viettel|vinaphone|mobifone)\b') &&
        _matches(q, r'\d{3,10}|đầu\s*số|đầu\s*\d{3,4}|số\s*điện\s*thoại')) {
      return hit('vn_carrier_lookup', .94);
    }
    if (_matches(q, r'\b(biển\s*số|biển\s*xe|mã\s*biển)\b')) {
      return hit('vn_plate_lookup', .97);
    }
    if (_matches(q, r'\b(giá\s*vàng|vàng\s*sjc|vàng\s*9999|vàng\s*nhẫn)\b')) {
      return hit('gold_price', .98);
    }
    if (_matches(q, r'\b(lãi\s*suất|gửi\s*tiết\s*kiệm)\b')) {
      return hit('vn_bank_interest', .97);
    }
    if (_matches(q, r'\b(giá\s*xăng|ron\s*95|ron95|e5\s*ron92|diesel|giá\s*dầu\s*trong\s*nước)\b')) {
      return hit('vn_fuel_price', .98);
    }
    if (_matches(q, r'\b(vn\s*index|vnindex|hnx\s*index|hnxindex|upcom)\b')) {
      return hit('vn_market_index', .98);
    }
    if (_matches(q, r'\b(cổ\s*phiếu|mã\s*cổ\s*phiếu|giá\s*(fpt|vnm|vic|hpg|ssi|vcb))\b')) {
      return hit('stock_lookup', .94);
    }
    if (_matches(q, r'\b(fear\s*(and|&)\s*greed|sợ\s*hãi.*tham\s*lam|tâm\s*lý.*crypto)\b')) {
      return hit('crypto_sentiment', .98);
    }
    if (_matches(q, r'\b(bitcoin|btc|ethereum|eth|bnb|solana|sol|xrp|crypto)\b') &&
        _matches(q, r'\b(giá|bao\s*nhiêu|tăng|giảm|hiện\s*tại|hôm\s*nay|24h)\b')) {
      final symbol = _cryptoSymbol(q);
      return hit('crypto_price', .97, {'symbol': symbol});
    }
    if (_matches(q, r'\b(s&p\s*500|sp500|nasdaq|dow\s*jones|nikkei|hang\s*seng)\b')) {
      return hit('global_market_index', .97);
    }
    if (_matches(q, r'\b(dầu\s*wti|brent|giá\s*bạc|giá\s*đồng|cà\s*phê\s*thế\s*giới|hàng\s*hóa)\b')) {
      return hit('commodity_price', .95);
    }
    if (_matches(q, r'\b(thời\s*tiết|nhiệt\s*độ|trời\s*mưa|mưa\s*không|bao\s*nhiêu\s*độ)\b')) {
      return hit('weather', .98, {'location': _extractLocation(normalized)});
    }
    if (_matches(q, r'\b(aqi|chất\s*lượng\s*không\s*khí|pm\s*2[.,]?5|pm10|ô\s*nhiễm\s*không\s*khí)\b')) {
      return hit('air_quality', .98, {'location': _extractLocation(normalized)});
    }
    if (_matches(q, r'\b(tỷ\s*số|lịch\s*thi\s*đấu|kết\s*quả\s*trận|bóng\s*đá|trận\s*đấu)\b')) {
      return hit('sports_score', .94, {'team': _extractSportsTeam(normalized)});
    }
    if (_matches(q, r'\b(tin\s*tức|tin\s*nóng|tin\s*mới|có\s*gì\s*mới|thời\s*sự)\b')) {
      return hit('news_latest', .96);
    }

    final converter = _currencyConversion(q);
    if (converter != null) return hit('currency_converter', .97, converter);

    if (_matches(q, r'\b(tỷ\s*giá|ngoại\s*tệ|usd|eur|jpy|cny|krw|gbp|aud)\b') &&
        _matches(q, r'\b(giá|tỷ\s*giá|hôm\s*nay|bao\s*nhiêu|vnd)\b')) {
      return hit('fx_rate', .92, _currencyPair(q));
    }

    // Realtime Info chỉ nhận khi câu hỏi rõ ràng đang đòi dữ liệu hiện tại.
    if (_matches(q, r'\b(hôm\s*nay|hiện\s*tại|mới\s*nhất|realtime|bây\s*giờ)\b')) {
      return hit('realtime_info', .64);
    }
    return null;
  }

  bool _matches(String input, String source) {
    // Dart/ECMAScript `\\b` is not reliable around Vietnamese letters such as
    // “ố”, “ế”, “ộ”. That made valid intents like “xổ số” and “thời tiết”
    // intermittently miss the realtime router and fall through to Agent.
    // Try the strict expression first, then a phrase-safe version without the
    // ASCII word-boundary markers. The expressions themselves are specific
    // enough that this fallback does not broaden routing to arbitrary text.
    if (RegExp(source, caseSensitive: false, unicode: true).hasMatch(input)) {
      return true;
    }
    final vietnameseSafe = source.replaceAll(r'\b', '');
    return RegExp(vietnameseSafe, caseSensitive: false, unicode: true)
        .hasMatch(input);
  }

  String _cryptoSymbol(String q) {
    if (q.contains('ethereum') || RegExp(r'\beth\b').hasMatch(q)) return 'ETH';
    if (RegExp(r'\bbnb\b').hasMatch(q)) return 'BNB';
    if (q.contains('solana') || RegExp(r'\bsol\b').hasMatch(q)) return 'SOL';
    if (RegExp(r'\bxrp\b').hasMatch(q)) return 'XRP';
    return 'BTC';
  }

  String _extractLocation(String original) {
    var value = original.trim().replaceAll(RegExp(r'[?!,.]+$'), '');

    // Ưu tiên phần người dùng nói rõ sau "ở/tại":
    // "thời tiết ở Chánh Hiệp hôm nay" -> "Chánh Hiệp".
    final explicit = RegExp(
      r'(?:^|\s)(?:ở|tại)\s+(.+)$',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(value);
    if (explicit != null && (explicit.group(1) ?? '').trim().isNotEmpty) {
      value = explicit.group(1)!.trim();
    } else {
      value = value.replaceAll(
        RegExp(
          r'(thời\s*tiết|nhiệt\s*độ|chất\s*lượng\s*không\s*khí|aqi|pm\s*2[.,]?5|pm10)',
          caseSensitive: false,
          unicode: true,
        ),
        ' ',
      );
    }

    // Chỉ bỏ phần hỏi/thời gian ở CUỐI câu, không xóa từ nằm giữa tên địa danh.
    value = value.replaceAll(
      RegExp(
        r'\s+(?:hôm\s*nay|bây\s*giờ|hiện\s*tại|lúc\s*này|thế\s*nào|ra\s*sao|bao\s*nhiêu\s*độ|có\s*mưa\s*không|cho\s*tôi|giúp\s*tôi|nhé|với|đi)\s*$',
        caseSensitive: false,
        unicode: true,
      ),
      '',
    );
    value = value
        .replaceAll(RegExp(r'^\s*(?:ở|tại|cho|giúp|xem|coi)\s+', caseSensitive: false, unicode: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    const aliases = <String, String>{
      'sài gòn': 'Hồ Chí Minh',
      'saigon': 'Hồ Chí Minh',
      'tp hcm': 'Hồ Chí Minh',
      'tphcm': 'Hồ Chí Minh',
      'thành phố hồ chí minh': 'Hồ Chí Minh',
      'hn': 'Hà Nội',
    };
    final alias = aliases[value.toLowerCase()];
    if (alias != null) value = alias;

    // Nếu người dùng không nói địa điểm, giữ mặc định cũ. Nhưng khi họ đã
    // nói tên nơi, tuyệt đối không tự thay bằng một địa điểm khác ở router.
    return value.isEmpty ? 'Hà Nội' : value;
  }

  String _extractSportsTeam(String original) {
    var value = original.replaceAll(
      RegExp(r'\b(tỷ số|lịch thi đấu|kết quả trận|bóng đá|trận đấu|hôm nay|mới nhất|của|cho tôi|giúp tôi)\b', caseSensitive: false),
      ' ',
    );
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return value.isEmpty ? 'Manchester United' : value;
  }

  Map<String, String>? _currencyConversion(String q) {
    final codePattern = r'(USD|EUR|VND|JPY|CNY|KRW|GBP|AUD|SGD|THB)';
    final direct = RegExp(
      '(\\d+(?:[.,]\\d+)?)\\s*$codePattern\\s*(?:sang|thành|bằng|đổi sang)\\s*$codePattern',
      caseSensitive: false,
    ).firstMatch(q.toUpperCase());
    if (direct != null) {
      return <String, String>{
        'amount': direct.group(1)!.replaceAll(',', '.'),
        'from': direct.group(2)!.toUpperCase(),
        'to': direct.group(3)!.toUpperCase(),
      };
    }
    if (RegExp(r'\b(quy\s*đổi|đổi\s*tiền|bằng\s*bao\s*nhiêu)\b', caseSensitive: false).hasMatch(q)) {
      final pair = _currencyPair(q);
      return <String, String>{'amount': _extractAmount(q), ...pair};
    }
    return null;
  }

  Map<String, String> _currencyPair(String q) {
    final upper = q.toUpperCase();
    final found = RegExp(r'\b(USD|EUR|VND|JPY|CNY|KRW|GBP|AUD|SGD|THB)\b')
        .allMatches(upper)
        .map((m) => m.group(1)!)
        .toList();
    if (found.length >= 2) return {'from': found[0], 'to': found[1]};
    if (found.length == 1) {
      return {'from': found[0], 'to': found[0] == 'VND' ? 'USD' : 'VND'};
    }
    return const {'from': 'USD', 'to': 'VND'};
  }

  String _extractAmount(String q) {
    final match = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(q);
    if (match == null) return '1';
    var amount = double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? 1;
    if (q.contains('triệu')) amount *= 1000000;
    if (q.contains('nghìn') || q.contains('ngàn')) amount *= 1000;
    return amount.toString();
  }

  static List<ToolDefinition> searchDefinitions(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return ToolRegistry.all;
    return ToolRegistry.all.where((tool) {
      return tool.name.toLowerCase().contains(q) ||
          tool.description.toLowerCase().contains(q) ||
          tool.keywords.any((word) => word.toLowerCase().contains(q));
    }).toList();
  }
}
