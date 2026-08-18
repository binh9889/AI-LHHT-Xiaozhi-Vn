import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:ai_assistant/tools/models/tool_models.dart';
import 'package:ai_assistant/tools/services/tool_provider_config.dart';

class PublicDataProviders {
  PublicDataProviders({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _lotterySources = <String>[
    'https://raw.githubusercontent.com/khiemdoan/vietnam-lottery-xsmb-analysis/refs/heads/main/data/xsmb.csv',
    'https://raw.githubusercontent.com/AnhTuPhi/xsmb-vietnam-lottery-analysis/refs/heads/master/data/xsmb.csv',
  ];

  Future<ToolResult> execute(
    String toolId,
    String query,
    Map<String, String> params,
    ToolProviderConfig config,
  ) async {
    final started = DateTime.now();
    ToolResult result;
    try {
      switch (toolId) {
        case 'vn_lottery':
          result = await _lottery(query, params);
          break;
        case 'lunar_calendar':
          result = _lunar(query);
          break;
        case 'vn_area_code':
          result = _areaCode(query);
          break;
        case 'vn_carrier_lookup':
          result = _carrier(query);
          break;
        case 'vn_plate_lookup':
          result = _plate(query);
          break;
        case 'gold_price':
          result = await _gold(query);
          break;
        case 'fx_rate':
          result = await _fxRate(params);
          break;
        case 'currency_converter':
          result = await _currencyConvert(params);
          break;
        case 'crypto_price':
          result = await _crypto(params);
          break;
        case 'crypto_sentiment':
          result = await _cryptoSentiment();
          break;
        case 'news_latest':
          result = await _news();
          break;
        case 'weather':
          result = await _weather(params['location'] ?? 'Hà Nội');
          break;
        case 'air_quality':
          result = await _airQuality(params['location'] ?? 'Hà Nội');
          break;
        case 'sports_score':
          result = await _sports(params['team'] ?? 'Manchester United', config.sportsDbKey);
          break;
        case 'realtime_info':
          result = await _realtimeInfo(query);
          break;
        default:
          result = _needsBridge(toolId);
      }
    } catch (e) {
      result = _failure(toolId, 'PROVIDER_ERROR', 'Nguồn dữ liệu gặp lỗi: ${_shortError(e)}');
    }

    if ((!result.success || result.errorCode == 'NEEDS_CONFIGURATION') && config.hasBridge) {
      final bridge = await _bridge(toolId, query, params, config);
      if (bridge.success) result = bridge;
    }

    return result.copyWith(latencyMs: DateTime.now().difference(started).inMilliseconds);
  }

  Future<ToolResult> _bridge(
    String toolId,
    String query,
    Map<String, String> params,
    ToolProviderConfig config,
  ) async {
    try {
      final base = Uri.tryParse(config.bridgeUrl.trim());
      if (base == null || !base.hasScheme) {
        return _failure(toolId, 'BAD_BRIDGE_URL', 'Địa chỉ Realtime Bridge chưa hợp lệ.');
      }
      final uri = base.replace(queryParameters: <String, String>{
        ...base.queryParameters,
        'toolId': toolId,
        'q': query,
        ...params,
      });
      final response = await _client.get(
        uri,
        headers: <String, String>{
          'Accept': 'application/json',
          if (config.bridgeToken.trim().isNotEmpty) 'Authorization': 'Bearer ${config.bridgeToken.trim()}',
          'User-Agent': 'AI-LHHT/4.1.3 Android',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return _failure(toolId, 'BRIDGE_HTTP_${response.statusCode}', 'Realtime Bridge trả HTTP ${response.statusCode}.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return _failure(toolId, 'BRIDGE_BAD_JSON', 'Realtime Bridge trả dữ liệu không đúng định dạng.');
      final map = Map<String, dynamic>.from(decoded);
      final details = <String, String>{};
      final data = map['data'];
      if (data is Map) {
        for (final entry in data.entries) {
          details[entry.key.toString()] = entry.value?.toString() ?? '';
        }
      }
      return ToolResult(
        toolId: toolId,
        title: (map['title'] ?? toolId).toString(),
        summary: (map['summary'] ?? 'Đã lấy dữ liệu từ Realtime Bridge.').toString(),
        source: (map['source'] ?? 'AI-LHHT Realtime Bridge').toString(),
        timestamp: DateTime.tryParse((map['timestamp'] ?? '').toString()) ?? DateTime.now(),
        success: map['success'] != false,
        details: details,
        freshness: ToolResultFreshness.live,
      );
    } catch (e) {
      return _failure(toolId, 'BRIDGE_ERROR', 'Không gọi được Realtime Bridge: ${_shortError(e)}');
    }
  }

  ToolResult _needsBridge(String toolId) {
    return _failure(
      toolId,
      'NEEDS_CONFIGURATION',
      'Công cụ này cần nguồn dữ liệu realtime. Hãy cấu hình Realtime Bridge trong Cài đặt → Công cụ realtime.',
    );
  }

  Future<ToolResult> _lottery(String query, Map<String, String> params) async {
    final region = params['region'] ?? 'north';
    if (region != 'north') {
      return _failure(
        'vn_lottery',
        'NEEDS_CONFIGURATION',
        'Nguồn tích hợp sẵn hiện xác minh được XSMB. XSMT/XSMN sẽ dùng Realtime Bridge để tránh trả dữ liệu không kiểm chứng.',
      );
    }
    final wanted = _extractDate(query) ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    Object? lastError;
    for (final source in _lotterySources) {
      try {
        final response = await _get(Uri.parse(source), timeout: const Duration(seconds: 8));
        if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
        final parsed = _parseLotteryCsv(response.body, wanted);
        if (parsed != null) return parsed;
      } catch (e) {
        lastError = e;
      }
    }
    return _failure('vn_lottery', 'LOTTERY_UNAVAILABLE', 'Không lấy được XSMB từ các nguồn tích hợp. ${_shortError(lastError)}');
  }

  ToolResult? _parseLotteryCsv(String csv, String wanted) {
    final lines = const LineSplitter().convert(csv).where((line) => line.trim().isNotEmpty).toList();
    if (lines.length < 2) return null;
    final header = _splitCsv(lines.first).map((e) => e.toLowerCase()).toList();
    int dateIndex = header.indexWhere((e) => e.contains('date') || e.contains('ngay'));
    if (dateIndex < 0) dateIndex = 0;
    List<String>? row;
    for (final line in lines.skip(1)) {
      final cells = _splitCsv(line);
      if (cells.length <= dateIndex) continue;
      final normalized = _normalizeCsvDate(cells[dateIndex]);
      if (normalized == wanted) {
        row = cells;
        break;
      }
    }
    // Dataset có thể chưa cập nhật ngày hiện tại; dùng bản ghi mới nhất nhưng ghi rõ ngày.
    row ??= _splitCsv(lines.last);
    if (row.length <= dateIndex) return null;
    final actualDate = _normalizeCsvDate(row[dateIndex]) ?? row[dateIndex];
    final values = <String, String>{};
    for (var i = 0; i < math.min(header.length, row.length); i++) {
      if (i == dateIndex || row[i].trim().isEmpty) continue;
      values[header[i].isEmpty ? 'Giải ${i + 1}' : header[i]] = row[i].trim();
    }
    if (values.isEmpty) return null;
    final special = _pickLottery(values, <String>['db', 'dac biet', 'gdb', 'special']);
    final first = _pickLottery(values, <String>['g1', 'giải 1', 'giai 1', 'first']);
    final summary = StringBuffer('Xổ số miền Bắc ngày $actualDate');
    if (special != null) summary.write(', giải đặc biệt $special');
    if (first != null) summary.write(', giải nhất $first');
    summary.write('.');
    return ToolResult(
      toolId: 'vn_lottery',
      title: 'Kết quả XSMB',
      summary: summary.toString(),
      source: 'GitHub public lottery datasets (2-source fallback)',
      timestamp: DateTime.now(),
      success: true,
      details: <String, String>{'Ngày': actualDate, ...values},
      freshness: actualDate == DateFormat('yyyy-MM-dd').format(DateTime.now())
          ? ToolResultFreshness.live
          : ToolResultFreshness.recent,
    );
  }

  String? _pickLottery(Map<String, String> values, List<String> aliases) {
    for (final entry in values.entries) {
      final key = entry.key.toLowerCase();
      if (aliases.any((a) => key.contains(a))) return entry.value;
    }
    return null;
  }

  ToolResult _lunar(String query) {
    final solar = _extractDmyDate(query) ?? DateTime.now();
    final lunar = _convertSolar2Lunar(solar.day, solar.month, solar.year, 7.0);
    final can = <String>['Giáp', 'Ất', 'Bính', 'Đinh', 'Mậu', 'Kỷ', 'Canh', 'Tân', 'Nhâm', 'Quý'];
    final chi = <String>['Tý', 'Sửu', 'Dần', 'Mão', 'Thìn', 'Tỵ', 'Ngọ', 'Mùi', 'Thân', 'Dậu', 'Tuất', 'Hợi'];
    final jd = _jdFromDate(solar.day, solar.month, solar.year);
    final dayCanChi = '${can[(jd + 9) % 10]} ${chi[(jd + 1) % 12]}';
    final monthCan = can[(lunar[2] * 12 + lunar[1] + 3) % 10];
    final monthChi = chi[(lunar[1] + 1) % 12];
    final yearCanChi = '${can[(lunar[2] + 6) % 10]} ${chi[(lunar[2] + 8) % 12]}';
    final leap = lunar[3] == 1 ? ' (tháng nhuận)' : '';
    return ToolResult(
      toolId: 'lunar_calendar',
      title: 'Lịch âm',
      summary: '${solar.day}/${solar.month}/${solar.year} là ${lunar[0]}/${lunar[1]} âm lịch$leap, ngày $dayCanChi.',
      source: 'Thuật toán âm lịch Việt Nam chạy cục bộ',
      timestamp: DateTime.now(),
      success: true,
      details: <String, String>{
        'Dương lịch': '${solar.day}/${solar.month}/${solar.year}',
        'Âm lịch': '${lunar[0]}/${lunar[1]}/${lunar[2]}$leap',
        'Ngày can chi': dayCanChi,
        'Tháng can chi': '$monthCan $monthChi',
        'Năm can chi': yearCanChi,
      },
      freshness: ToolResultFreshness.staticData,
    );
  }

  ToolResult _areaCode(String query) {
    final q = query.toLowerCase();
    final digits = RegExp(r'\b0?(2\d{1,2})\b').firstMatch(q)?.group(1);
    String? name;
    String? code;
    if (digits != null && _areaCodes.containsKey(digits)) {
      code = digits;
      name = _areaCodes[digits];
    } else {
      for (final entry in _areaCodes.entries) {
        if (_fold(q).contains(_fold(entry.value))) {
          code = entry.key;
          name = entry.value;
          break;
        }
      }
    }
    if (code == null || name == null) {
      return _failure('vn_area_code', 'NOT_FOUND', 'Chưa nhận ra mã vùng/tỉnh trong câu hỏi. Ví dụ: “0236 là tỉnh nào?”');
    }
    return ToolResult(
      toolId: 'vn_area_code',
      title: 'Mã vùng điện thoại',
      summary: 'Mã vùng cố định của $name là 0$code.',
      source: 'Bảng mã vùng cục bộ AI-LHHT',
      timestamp: DateTime.now(),
      success: true,
      details: {'Tỉnh/thành': name, 'Mã vùng': '0$code'},
      freshness: ToolResultFreshness.staticData,
    );
  }

  ToolResult _carrier(String query) {
    final digits = query.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 3) return _failure('vn_carrier_lookup', 'INVALID_INPUT', 'Hãy nói ít nhất 3 số đầu của số điện thoại.');
    var number = digits;
    if (number.startsWith('84') && number.length >= 4) number = '0${number.substring(2)}';
    final prefix3 = number.substring(0, math.min(3, number.length));
    String? carrier;
    for (final entry in _carrierPrefixes.entries) {
      if (entry.value.contains(prefix3)) {
        carrier = entry.key;
        break;
      }
    }
    carrier ??= 'Chưa xác định';
    return ToolResult(
      toolId: 'vn_carrier_lookup',
      title: 'Tra nhà mạng',
      summary: 'Đầu số $prefix3 thuộc dải số gốc của $carrier. Chuyển mạng giữ số có thể làm nhà mạng hiện tại khác với đầu số gốc.',
      source: 'Bảng đầu số di động cục bộ',
      timestamp: DateTime.now(),
      success: true,
      details: {'Đầu số': prefix3, 'Dải số gốc': carrier, 'Lưu ý': 'Không xác nhận MNP realtime'},
      freshness: ToolResultFreshness.staticData,
    );
  }

  ToolResult _plate(String query) {
    final match = RegExp(r'\b(\d{2})(?:[A-ZĐa-zđ])?').firstMatch(query.toUpperCase());
    if (match == null) return _failure('vn_plate_lookup', 'INVALID_INPUT', 'Hãy nói mã biển số, ví dụ 30A hoặc 51F.');
    final code = match.group(1)!;
    final name = _plateCodes[code];
    if (name == null) return _failure('vn_plate_lookup', 'NOT_FOUND', 'Chưa có mã biển $code trong bảng tra cứu cơ bản.');
    return ToolResult(
      toolId: 'vn_plate_lookup',
      title: 'Tra biển số xe',
      summary: 'Mã biển số $code thuộc $name theo bảng mã đăng ký xe truyền thống.',
      source: 'Bảng mã biển số cục bộ',
      timestamp: DateTime.now(),
      success: true,
      details: {'Mã biển': code, 'Tỉnh/thành': name},
      freshness: ToolResultFreshness.staticData,
    );
  }

  Future<ToolResult> _gold(String query) async {
    final uri = Uri.parse('https://www.sjc.com.vn/cong-bo-thong-tin');
    try {
      final response = await _get(uri, timeout: const Duration(seconds: 8));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final text = _htmlToText(response.body);
      final marker = text.toLowerCase().indexOf('giá vàng sjc');
      if (marker >= 0) {
        final sample = text.substring(marker, math.min(text.length, marker + 1500));
        final numbers = RegExp(r'\b\d{1,3}(?:[.,]\d{3})+(?:[.,]\d+)?\b')
            .allMatches(sample)
            .map((m) => m.group(0)!)
            .toList();
        if (numbers.length >= 2) {
          return ToolResult(
            toolId: 'gold_price',
            title: 'Giá vàng SJC',
            summary: 'SJC đang công bố giá vàng; hai mức giá đầu tiên đọc được là ${numbers[0]} và ${numbers[1]} nghìn đồng/lượng. Hãy mở chi tiết để đối chiếu loại vàng.',
            source: 'SJC – Công bố thông tin',
            timestamp: DateTime.now(),
            success: true,
            details: {'Mức 1': numbers[0], 'Mức 2': numbers[1], 'Đơn vị trang nguồn': 'nghìn đồng/lượng'},
            freshness: ToolResultFreshness.live,
            sourceUrl: uri,
          );
        }
      }
      return _failure('gold_price', 'NEEDS_CONFIGURATION', 'Trang SJC đang không cung cấp bảng giá dưới dạng HTML có thể phân tích ổn định. Có thể nối Realtime Bridge để lấy dữ liệu chuẩn hóa.');
    } catch (e) {
      return _failure('gold_price', 'NEEDS_CONFIGURATION', 'Không đọc được bảng SJC lúc này. Có thể dùng Realtime Bridge làm nguồn dự phòng.');
    }
  }

  Future<ToolResult> _fxRate(Map<String, String> params) async {
    final from = (params['from'] ?? 'USD').toUpperCase();
    final to = (params['to'] ?? 'VND').toUpperCase();
    final uri = Uri.parse('https://api.frankfurter.dev/v2/rate/$from/$to');
    final response = await _get(uri, timeout: const Duration(seconds: 6));
    if (response.statusCode != 200) return _failure('fx_rate', 'HTTP_${response.statusCode}', 'Không lấy được tỷ giá $from/$to.');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rate = (data['rate'] as num?)?.toDouble();
    if (rate == null) return _failure('fx_rate', 'BAD_RESPONSE', 'Nguồn tỷ giá không trả rate.');
    return ToolResult(
      toolId: 'fx_rate',
      title: 'Tỷ giá $from/$to',
      summary: '1 $from ≈ ${_formatNumber(rate)} $to theo tỷ giá tham chiếu ngày ${data['date']}.',
      source: 'Frankfurter / central-bank reference rates',
      timestamp: DateTime.now(),
      success: true,
      details: {'Cặp': '$from/$to', 'Tỷ giá': _formatNumber(rate), 'Ngày dữ liệu': '${data['date']}'},
      freshness: ToolResultFreshness.recent,
      sourceUrl: uri,
    );
  }

  Future<ToolResult> _currencyConvert(Map<String, String> params) async {
    final amount = double.tryParse(params['amount'] ?? '1') ?? 1;
    final from = (params['from'] ?? 'USD').toUpperCase();
    final to = (params['to'] ?? 'VND').toUpperCase();
    if (from == to) {
      return ToolResult(
        toolId: 'currency_converter',
        title: 'Quy đổi tiền tệ',
        summary: '${_formatNumber(amount)} $from = ${_formatNumber(amount)} $to.',
        source: 'Tính toán cục bộ',
        timestamp: DateTime.now(),
        success: true,
        details: {'Số tiền': _formatNumber(amount), 'Từ': from, 'Sang': to},
        freshness: ToolResultFreshness.staticData,
      );
    }
    final uri = Uri.parse('https://api.frankfurter.dev/v2/rate/$from/$to');
    final response = await _get(uri, timeout: const Duration(seconds: 6));
    if (response.statusCode != 200) return _failure('currency_converter', 'HTTP_${response.statusCode}', 'Không lấy được tỷ giá để quy đổi.');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rate = (data['rate'] as num?)?.toDouble();
    if (rate == null) return _failure('currency_converter', 'BAD_RESPONSE', 'Không có tỷ giá phù hợp.');
    final converted = amount * rate;
    return ToolResult(
      toolId: 'currency_converter',
      title: 'Quy đổi $from → $to',
      summary: '${_formatNumber(amount)} $from ≈ ${_formatNumber(converted)} $to.',
      source: 'Frankfurter / central-bank reference rates',
      timestamp: DateTime.now(),
      success: true,
      details: {'Số tiền gốc': '${_formatNumber(amount)} $from', 'Tỷ giá': _formatNumber(rate), 'Kết quả': '${_formatNumber(converted)} $to', 'Ngày': '${data['date']}'},
      freshness: ToolResultFreshness.recent,
      sourceUrl: uri,
    );
  }

  Future<ToolResult> _crypto(Map<String, String> params) async {
    final symbol = (params['symbol'] ?? 'BTC').toUpperCase();
    final pair = '${symbol}USDT';
    final uri = Uri.parse('https://data-api.binance.vision/api/v3/ticker/24hr?symbol=$pair');
    final response = await _get(uri, timeout: const Duration(seconds: 6));
    if (response.statusCode != 200) return _failure('crypto_price', 'HTTP_${response.statusCode}', 'Không lấy được dữ liệu $symbol từ Binance market-data.');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final price = double.tryParse('${data['lastPrice']}');
    final change = double.tryParse('${data['priceChangePercent']}');
    if (price == null) return _failure('crypto_price', 'BAD_RESPONSE', 'Nguồn crypto thiếu giá hiện tại.');
    return ToolResult(
      toolId: 'crypto_price',
      title: '$symbol / USDT',
      summary: '$symbol hiện khoảng ${_formatNumber(price)} USDT, ${change == null ? '' : '${change >= 0 ? 'tăng' : 'giảm'} ${change.abs().toStringAsFixed(2)}% trong 24 giờ.'}',
      source: 'Binance Spot public market data',
      timestamp: DateTime.now(),
      success: true,
      details: {
        'Giá': '${_formatNumber(price)} USDT',
        '24h': change == null ? 'N/A' : '${change.toStringAsFixed(2)}%',
        'Cao 24h': '${data['highPrice']}',
        'Thấp 24h': '${data['lowPrice']}',
        'Khối lượng': '${data['volume']}',
      },
      freshness: ToolResultFreshness.live,
      sourceUrl: uri,
    );
  }

  Future<ToolResult> _cryptoSentiment() async {
    final uri = Uri.parse('https://api.alternative.me/fng/?limit=1&format=json');
    final response = await _get(uri, timeout: const Duration(seconds: 6));
    if (response.statusCode != 200) return _failure('crypto_sentiment', 'HTTP_${response.statusCode}', 'Không lấy được Fear & Greed.');
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final list = decoded['data'];
    if (list is! List || list.isEmpty || list.first is! Map) return _failure('crypto_sentiment', 'BAD_RESPONSE', 'Nguồn Fear & Greed trả dữ liệu không hợp lệ.');
    final item = Map<String, dynamic>.from(list.first as Map);
    final value = item['value']?.toString() ?? '?';
    final label = item['value_classification']?.toString() ?? 'N/A';
    return ToolResult(
      toolId: 'crypto_sentiment',
      title: 'Crypto Fear & Greed',
      summary: 'Chỉ số Fear & Greed hiện là $value – $label.',
      source: 'Alternative.me Fear & Greed API',
      timestamp: DateTime.now(),
      success: true,
      details: {'Chỉ số': value, 'Phân loại': label},
      freshness: ToolResultFreshness.recent,
      sourceUrl: uri,
    );
  }

  Future<ToolResult> _news() async {
    final uri = Uri.parse('https://vnexpress.net/rss/tin-moi-nhat.rss');
    final response = await _get(uri, timeout: const Duration(seconds: 8));
    if (response.statusCode != 200) return _failure('news_latest', 'HTTP_${response.statusCode}', 'Không tải được RSS tin mới.');
    final items = RegExp(r'<item>([\s\S]*?)</item>', caseSensitive: false).allMatches(response.body).take(5).toList();
    if (items.isEmpty) return _failure('news_latest', 'BAD_RSS', 'RSS chưa trả danh sách tin.');
    final details = <String, String>{};
    final titles = <String>[];
    for (var i = 0; i < items.length; i++) {
      final block = items[i].group(1)!;
      final title = _xmlValue(block, 'title');
      if (title.isNotEmpty) {
        titles.add(title);
        details['Tin ${i + 1}'] = title;
      }
    }
    return ToolResult(
      toolId: 'news_latest',
      title: 'Tin mới nhất',
      summary: titles.isEmpty ? 'RSS chưa có tiêu đề.' : 'Tin mới: ${titles.take(3).join('; ')}.',
      source: 'VnExpress RSS',
      timestamp: DateTime.now(),
      success: titles.isNotEmpty,
      details: details,
      freshness: ToolResultFreshness.live,
      sourceUrl: uri,
    );
  }

  Future<ToolResult> _weather(String location) async {
    final geo = await _geocode(location);
    if (geo == null) return _failure('weather', 'LOCATION_NOT_FOUND', 'Không tìm thấy địa điểm “$location”.');
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '${geo.$2}',
      'longitude': '${geo.$3}',
      'current': 'temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m',
      'daily': 'temperature_2m_max,temperature_2m_min,precipitation_probability_max',
      'forecast_days': '2',
      'timezone': 'auto',
    });
    final response = await _get(uri, timeout: const Duration(seconds: 7));
    if (response.statusCode != 200) return _failure('weather', 'HTTP_${response.statusCode}', 'Không lấy được thời tiết.');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final current = Map<String, dynamic>.from((data['current'] as Map?) ?? const {});
    final daily = Map<String, dynamic>.from((data['daily'] as Map?) ?? const {});
    final temp = current['temperature_2m'];
    final feels = current['apparent_temperature'];
    final humidity = current['relative_humidity_2m'];
    final rain = current['precipitation'];
    final wind = current['wind_speed_10m'];
    final condition = _weatherCode(current['weather_code']);
    final maxTemp = _first(daily['temperature_2m_max']);
    final minTemp = _first(daily['temperature_2m_min']);
    final rainChance = _first(daily['precipitation_probability_max']);
    return ToolResult(
      toolId: 'weather',
      title: 'Thời tiết ${geo.$1}',
      summary: 'Thời tiết tại ${geo.$1}: ${temp ?? '?'}°C, cảm giác ${feels ?? '?'}°C, $condition. Độ ẩm ${humidity ?? '?'}%, gió ${wind ?? '?'} km/h, khả năng mưa ${rainChance ?? '?'}%.',
      source: 'Open-Meteo',
      timestamp: DateTime.now(),
      success: true,
      details: {
        'Nhiệt độ': '${temp ?? '?'} °C',
        'Cảm giác': '${feels ?? '?'} °C',
        'Điều kiện': condition,
        'Độ ẩm': '${humidity ?? '?'}%',
        'Mưa hiện tại': '${rain ?? '?'} mm',
        'Gió': '${wind ?? '?'} km/h',
        'Cao / thấp': '${maxTemp ?? '?'} / ${minTemp ?? '?'} °C',
        'Khả năng mưa': '${rainChance ?? '?'}%',
      },
      freshness: ToolResultFreshness.live,
      sourceUrl: uri,
    );
  }

  Future<ToolResult> _airQuality(String location) async {
    final geo = await _geocode(location);
    if (geo == null) return _failure('air_quality', 'LOCATION_NOT_FOUND', 'Không tìm thấy địa điểm “$location”.');
    final uri = Uri.https('air-quality-api.open-meteo.com', '/v1/air-quality', {
      'latitude': '${geo.$2}',
      'longitude': '${geo.$3}',
      'current': 'us_aqi,pm2_5,pm10,nitrogen_dioxide,ozone',
      'timezone': 'auto',
    });
    final response = await _get(uri, timeout: const Duration(seconds: 7));
    if (response.statusCode != 200) return _failure('air_quality', 'HTTP_${response.statusCode}', 'Không lấy được AQI.');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final current = Map<String, dynamic>.from((data['current'] as Map?) ?? const {});
    final aqi = (current['us_aqi'] as num?)?.toDouble();
    final label = _aqiLabel(aqi);
    return ToolResult(
      toolId: 'air_quality',
      title: 'Chất lượng không khí ${geo.$1}',
      summary: 'AQI tại ${geo.$1} hiện ${aqi?.round() ?? '?'}, mức $label. PM2.5 ${current['pm2_5'] ?? '?'} µg/m³.',
      source: 'Open-Meteo Air Quality / CAMS',
      timestamp: DateTime.now(),
      success: true,
      details: {
        'US AQI': '${aqi?.round() ?? '?'} – $label',
        'PM2.5': '${current['pm2_5'] ?? '?'} µg/m³',
        'PM10': '${current['pm10'] ?? '?'} µg/m³',
        'NO₂': '${current['nitrogen_dioxide'] ?? '?'} µg/m³',
        'O₃': '${current['ozone'] ?? '?'} µg/m³',
      },
      freshness: ToolResultFreshness.live,
      sourceUrl: uri,
    );
  }

  Future<ToolResult> _sports(String team, String key) async {
    final apiKey = key.trim().isEmpty ? '123' : key.trim();
    final searchUri = Uri.https('www.thesportsdb.com', '/api/v1/json/$apiKey/searchteams.php', {'t': team});
    final response = await _get(searchUri, timeout: const Duration(seconds: 8));
    if (response.statusCode != 200) return _failure('sports_score', 'HTTP_${response.statusCode}', 'Không tìm được đội bóng.');
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final teams = decoded['teams'];
    if (teams is! List || teams.isEmpty || teams.first is! Map) return _failure('sports_score', 'TEAM_NOT_FOUND', 'Không tìm thấy đội “$team”.');
    final teamMap = Map<String, dynamic>.from(teams.first as Map);
    final id = '${teamMap['idTeam']}';
    final display = '${teamMap['strTeam']}';
    final lastUri = Uri.parse('https://www.thesportsdb.com/api/v1/json/$apiKey/eventslast.php?id=$id');
    final lastResponse = await _get(lastUri, timeout: const Duration(seconds: 8));
    if (lastResponse.statusCode != 200) return _failure('sports_score', 'HTTP_${lastResponse.statusCode}', 'Không lấy được trận gần nhất của $display.');
    final lastDecoded = jsonDecode(lastResponse.body) as Map<String, dynamic>;
    final results = lastDecoded['results'];
    if (results is! List || results.isEmpty || results.first is! Map) {
      return ToolResult(
        toolId: 'sports_score',
        title: display,
        summary: 'Đã tìm thấy $display nhưng gói API hiện tại không trả trận gần nhất. Livescore đầy đủ có thể cần API key cao hơn.',
        source: 'TheSportsDB',
        timestamp: DateTime.now(),
        success: true,
        details: {'Đội': display},
        freshness: ToolResultFreshness.recent,
        sourceUrl: searchUri,
      );
    }
    final event = Map<String, dynamic>.from(results.first as Map);
    final home = '${event['strHomeTeam'] ?? ''}';
    final away = '${event['strAwayTeam'] ?? ''}';
    final hs = '${event['intHomeScore'] ?? '-'}';
    final awayScore = '${event['intAwayScore'] ?? '-'}';
    final date = '${event['dateEvent'] ?? ''}';
    return ToolResult(
      toolId: 'sports_score',
      title: 'Kết quả gần nhất – $display',
      summary: '$home $hs – $awayScore $away${date.isEmpty ? '' : ', ngày $date'}.',
      source: 'TheSportsDB',
      timestamp: DateTime.now(),
      success: true,
      details: {'Đội nhà': home, 'Tỷ số': '$hs – $awayScore', 'Đội khách': away, 'Ngày': date, 'Giải': '${event['strLeague'] ?? ''}'},
      freshness: ToolResultFreshness.recent,
      sourceUrl: lastUri,
    );
  }

  Future<ToolResult> _realtimeInfo(String query) async {
    final q = query.toLowerCase();
    if (q.contains('bitcoin') || q.contains('btc')) return _crypto(const {'symbol': 'BTC'});
    if (q.contains('ethereum') || q.contains('eth')) return _crypto(const {'symbol': 'ETH'});
    if (q.contains('tin') || q.contains('đáng chú ý')) return _news();
    return _failure('realtime_info', 'AMBIGUOUS', 'Hãy nói rõ bạn muốn tra thời tiết, tin tức, crypto, tỷ giá, xổ số hoặc một công cụ cụ thể.');
  }

  Future<(String, double, double)?> _geocode(String location) async {
    final requested = location.trim().isEmpty ? 'Hà Nội' : location.trim();
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': requested,
      'count': '10',
      'language': 'vi',
      'format': 'json',
    });
    final response = await _get(uri, timeout: const Duration(seconds: 6));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rawResults = data['results'];
    if (rawResults is! List || rawResults.isEmpty) return null;

    final results = rawResults
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['latitude'] is num && item['longitude'] is num)
        .toList();
    if (results.isEmpty) return null;

    final query = requested.toLowerCase().trim();
    final foldedQuery = _foldVietnamese(query);
    double score(Map<String, dynamic> item) {
      final name = '${item['name'] ?? ''}'.toLowerCase().trim();
      final foldedName = _foldVietnamese(name);
      final countryCode = '${item['country_code'] ?? ''}'.toUpperCase();
      final admins = <String>[
        '${item['admin1'] ?? ''}',
        '${item['admin2'] ?? ''}',
        '${item['admin3'] ?? ''}',
        '${item['admin4'] ?? ''}',
      ].where((v) => v.trim().isNotEmpty).join(' ').toLowerCase();
      final foldedAdmins = _foldVietnamese(admins);

      var value = 0.0;
      if (name == query || foldedName == foldedQuery) value += 150;
      if (name.startsWith(query) || query.startsWith(name) ||
          foldedName.startsWith(foldedQuery) || foldedQuery.startsWith(foldedName)) {
        value += 70;
      }
      if (admins.contains(query) || foldedAdmins.contains(foldedQuery)) value += 55;
      // Ứng dụng là bản Việt Nam: khi hai địa danh trùng tên, ưu tiên kết quả
      // ở Việt Nam nhưng KHÔNG lọc cứng để vẫn tra được Tokyo/London/...
      if (countryCode == 'VN') value += 35;
      final population = item['population'];
      if (population is num && population > 0) {
        value += (population.toDouble().clamp(0, 10000000) / 10000000) * 8;
      }
      return value;
    }

    results.sort((a, b) => score(b).compareTo(score(a)));
    final item = results.first;
    final bestScore = score(item);
    // Không được "đoán đại" địa điểm. Nếu tên người dùng nói không khớp tên
    // hoặc cấp hành chính của bất kỳ kết quả nào, trả LOCATION_NOT_FOUND để
    // người dùng nói rõ hơn thay vì âm thầm đổi sang một nơi khác.
    if (bestScore < 70) return null;
    final lat = (item['latitude'] as num).toDouble();
    final lon = (item['longitude'] as num).toDouble();

    final labels = <String>[];
    void addLabel(dynamic raw) {
      final value = '${raw ?? ''}'.trim();
      if (value.isEmpty) return;
      if (labels.any((e) => e.toLowerCase() == value.toLowerCase())) return;
      labels.add(value);
    }

    addLabel(item['name'] ?? requested);
    addLabel(item['admin3']);
    addLabel(item['admin2']);
    addLabel(item['admin1']);
    final country = '${item['country'] ?? ''}'.trim();
    if (country.isNotEmpty && '${item['country_code'] ?? ''}'.toUpperCase() != 'VN') {
      addLabel(country);
    }
    final display = labels.take(3).join(', ');
    return (display.isEmpty ? requested : display, lat, lon);
  }


  String _foldVietnamese(String input) {
    var value = input.toLowerCase();
    const groups = <String, String>{
      'a': 'àáạảãâầấậẩẫăằắặẳẵ',
      'e': 'èéẹẻẽêềếệểễ',
      'i': 'ìíịỉĩ',
      'o': 'òóọỏõôồốộổỗơờớợởỡ',
      'u': 'ùúụủũưừứựửữ',
      'y': 'ỳýỵỷỹ',
      'd': 'đ',
    };
    groups.forEach((plain, accented) {
      for (final rune in accented.runes) {
        value = value.replaceAll(String.fromCharCode(rune), plain);
      }
    });
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<http.Response> _get(Uri uri, {required Duration timeout}) async {
    Object? last;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client.get(uri, headers: const {
          'Accept': 'application/json,text/xml,text/html,text/csv,*/*;q=0.8',
          'User-Agent': 'AI-LHHT/4.1.3 Android',
          'Cache-Control': 'no-cache',
        }).timeout(timeout);
        if (response.statusCode >= 500 && attempt == 0) {
          last = Exception('HTTP ${response.statusCode}');
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
        return response;
      } catch (e) {
        last = e;
        if (attempt == 0) await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
    throw Exception(_shortError(last));
  }

  ToolResult _failure(String toolId, String code, String message) {
    return ToolResult(
      toolId: toolId,
      title: 'Không lấy được dữ liệu',
      summary: message,
      source: 'AI-LHHT Tool Engine',
      timestamp: DateTime.now(),
      success: false,
      errorCode: code,
      userMessage: message,
      freshness: ToolResultFreshness.recent,
    );
  }

  static String _shortError(Object? e) {
    if (e == null) return '';
    final s = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length > 140 ? '${s.substring(0, 140)}…' : s;
  }

  static String _formatNumber(double value) {
    if (value.abs() >= 1000) return NumberFormat('#,##0.##', 'en_US').format(value);
    if (value.abs() >= 1) return value.toStringAsFixed(value.abs() < 10 ? 4 : 2).replaceFirst(RegExp(r'\.?0+$'), '');
    return value.toStringAsPrecision(6);
  }

  static dynamic _first(dynamic value) => value is List && value.isNotEmpty ? value.first : null;

  static String _weatherCode(dynamic code) {
    final c = code is num ? code.toInt() : -1;
    if (c == 0) return 'trời quang';
    if (<int>{1, 2, 3}.contains(c)) return 'có mây';
    if (<int>{45, 48}.contains(c)) return 'có sương mù';
    if (c >= 51 && c <= 67) return 'có mưa';
    if (c >= 71 && c <= 77) return 'có tuyết';
    if (c >= 80 && c <= 82) return 'mưa rào';
    if (c >= 95) return 'có dông';
    return 'điều kiện thời tiết mã $c';
  }

  static String _aqiLabel(double? aqi) {
    if (aqi == null) return 'không xác định';
    if (aqi <= 50) return 'tốt';
    if (aqi <= 100) return 'trung bình';
    if (aqi <= 150) return 'không tốt cho nhóm nhạy cảm';
    if (aqi <= 200) return 'không tốt';
    if (aqi <= 300) return 'rất không tốt';
    return 'nguy hại';
  }

  static String _xmlValue(String block, String tag) {
    final match = RegExp('<$tag>([\\s\\S]*?)</$tag>', caseSensitive: false).firstMatch(block);
    if (match == null) return '';
    var value = match.group(1) ?? '';
    value = value.replaceAll('<![CDATA[', '').replaceAll(']]>', '');
    value = value.replaceAll(RegExp(r'<[^>]+>'), ' ');
    value = value.replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&#39;', "'");
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _htmlToText(String html) {
    return html
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<String> _splitCsv(String line) {
    final values = <String>[];
    final current = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (ch == ',' && !quoted) {
        values.add(current.toString().trim());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    values.add(current.toString().trim());
    return values;
  }

  static String? _normalizeCsvDate(String input) {
    final value = input.trim();
    for (final pattern in <String>['yyyy-MM-dd', 'dd/MM/yyyy', 'MM/dd/yyyy', 'dd-MM-yyyy']) {
      try {
        return DateFormat('yyyy-MM-dd').format(DateFormat(pattern).parseStrict(value));
      } catch (_) {}
    }
    return null;
  }

  static String? _extractDate(String query) {
    final m = RegExp(r'\b(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})\b').firstMatch(query);
    if (m != null) {
      final date = DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
      return DateFormat('yyyy-MM-dd').format(date);
    }
    if (query.toLowerCase().contains('hôm qua')) {
      return DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1)));
    }
    return null;
  }

  static DateTime? _extractDmyDate(String query) {
    final m = RegExp(r'\b(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})\b').firstMatch(query);
    if (m == null) return null;
    return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
  }

  // Lunar conversion based on the widely used astronomical new-moon algorithm.
  static int _jdFromDate(int dd, int mm, int yy) {
    final a = ((14 - mm) / 12).floor();
    final y = yy + 4800 - a;
    final m = mm + 12 * a - 3;
    var jd = dd + ((153 * m + 2) / 5).floor() + 365 * y + (y / 4).floor() - (y / 100).floor() + (y / 400).floor() - 32045;
    if (jd < 2299161) jd = dd + ((153 * m + 2) / 5).floor() + 365 * y + (y / 4).floor() - 32083;
    return jd;
  }

  static double _newMoon(int k) {
    final t = k / 1236.85;
    final t2 = t * t;
    final t3 = t2 * t;
    const dr = math.pi / 180;
    var jd1 = 2415020.75933 + 29.53058868 * k + 0.0001178 * t2 - 0.000000155 * t3;
    jd1 += 0.00033 * math.sin((166.56 + 132.87 * t - 0.009173 * t2) * dr);
    final m = 359.2242 + 29.10535608 * k - 0.0000333 * t2 - 0.00000347 * t3;
    final mpr = 306.0253 + 385.81691806 * k + 0.0107306 * t2 + 0.00001236 * t3;
    final f = 21.2964 + 390.67050646 * k - 0.0016528 * t2 - 0.00000239 * t3;
    var c1 = (0.1734 - 0.000393 * t) * math.sin(m * dr) + 0.0021 * math.sin(2 * dr * m);
    c1 -= 0.4068 * math.sin(mpr * dr) + 0.0161 * math.sin(2 * dr * mpr);
    c1 -= 0.0004 * math.sin(3 * dr * mpr);
    c1 += 0.0104 * math.sin(2 * dr * f) - 0.0051 * math.sin((m + mpr) * dr);
    c1 -= 0.0074 * math.sin((m - mpr) * dr) + 0.0004 * math.sin((2 * f + m) * dr);
    c1 -= 0.0004 * math.sin((2 * f - m) * dr) - 0.0006 * math.sin((2 * f + mpr) * dr);
    c1 += 0.0010 * math.sin((2 * f - mpr) * dr) + 0.0005 * math.sin((2 * mpr + m) * dr);
    final deltat = t < -11
        ? 0.001 + 0.000839 * t + 0.0002261 * t2 - 0.00000845 * t3 - 0.000000081 * t * t3
        : -0.000278 + 0.000265 * t + 0.000262 * t2;
    return jd1 + c1 - deltat;
  }

  static double _sunLongitude(double jdn) {
    final t = (jdn - 2451545.0) / 36525;
    final t2 = t * t;
    const dr = math.pi / 180;
    final m = 357.52910 + 35999.05030 * t - 0.0001559 * t2 - 0.00000048 * t * t2;
    final l0 = 280.46645 + 36000.76983 * t + 0.0003032 * t2;
    var dl = (1.914600 - 0.004817 * t - 0.000014 * t2) * math.sin(dr * m);
    dl += (0.019993 - 0.000101 * t) * math.sin(2 * dr * m) + 0.000290 * math.sin(3 * dr * m);
    var l = (l0 + dl) * dr;
    l -= math.pi * 2 * (l / (math.pi * 2)).floor();
    return l;
  }

  static int _getNewMoonDay(int k, double timeZone) => (_newMoon(k) + 0.5 + timeZone / 24).floor();
  static int _getSunLongitude(int dayNumber, double timeZone) => (_sunLongitude(dayNumber - 0.5 - timeZone / 24) / math.pi * 6).floor();

  static int _getLunarMonth11(int yy, double timeZone) {
    final off = _jdFromDate(31, 12, yy) - 2415021;
    final k = (off / 29.530588853).floor();
    var nm = _getNewMoonDay(k, timeZone);
    final sunLong = _getSunLongitude(nm, timeZone);
    if (sunLong >= 9) nm = _getNewMoonDay(k - 1, timeZone);
    return nm;
  }

  static int _getLeapMonthOffset(int a11, double timeZone) {
    final k = ((a11 - 2415021.076998695) / 29.530588853 + 0.5).floor();
    var last = 0;
    var i = 1;
    var arc = _getSunLongitude(_getNewMoonDay(k + i, timeZone), timeZone);
    do {
      last = arc;
      i++;
      arc = _getSunLongitude(_getNewMoonDay(k + i, timeZone), timeZone);
    } while (arc != last && i < 14);
    return i - 1;
  }

  static List<int> _convertSolar2Lunar(int dd, int mm, int yy, double timeZone) {
    final dayNumber = _jdFromDate(dd, mm, yy);
    final k = ((dayNumber - 2415021.076998695) / 29.530588853).floor();
    var monthStart = _getNewMoonDay(k + 1, timeZone);
    if (monthStart > dayNumber) monthStart = _getNewMoonDay(k, timeZone);
    var a11 = _getLunarMonth11(yy, timeZone);
    var b11 = a11;
    int lunarYear;
    if (a11 >= monthStart) {
      lunarYear = yy;
      a11 = _getLunarMonth11(yy - 1, timeZone);
    } else {
      lunarYear = yy + 1;
      b11 = _getLunarMonth11(yy + 1, timeZone);
    }
    final lunarDay = dayNumber - monthStart + 1;
    final diff = ((monthStart - a11) / 29).floor();
    var lunarLeap = 0;
    var lunarMonth = diff + 11;
    if (b11 - a11 > 365) {
      final leapMonthDiff = _getLeapMonthOffset(a11, timeZone);
      if (diff >= leapMonthDiff) {
        lunarMonth = diff + 10;
        if (diff == leapMonthDiff) lunarLeap = 1;
      }
    }
    if (lunarMonth > 12) lunarMonth -= 12;
    if (lunarMonth >= 11 && diff < 4) lunarYear -= 1;
    return <int>[lunarDay, lunarMonth, lunarYear, lunarLeap];
  }

  static String _fold(String input) {
    const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const to =   'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    var out = input.toLowerCase();
    for (var i = 0; i < from.length; i++) {
      out = out.replaceAll(from[i], to[i]);
    }
    return out;
  }

  static const Map<String, String> _areaCodes = {
    '24': 'Hà Nội', '28': 'TP Hồ Chí Minh', '203': 'Quảng Ninh', '204': 'Bắc Giang', '205': 'Lạng Sơn',
    '206': 'Cao Bằng', '207': 'Tuyên Quang', '208': 'Thái Nguyên', '209': 'Bắc Kạn', '210': 'Phú Thọ',
    '211': 'Vĩnh Phúc', '212': 'Sơn La', '213': 'Lai Châu', '214': 'Lào Cai', '215': 'Điện Biên',
    '216': 'Yên Bái', '218': 'Hòa Bình', '219': 'Hà Giang', '220': 'Hải Dương', '221': 'Hưng Yên',
    '222': 'Bắc Ninh', '225': 'Hải Phòng', '226': 'Hà Nam', '227': 'Thái Bình', '228': 'Nam Định',
    '229': 'Ninh Bình', '232': 'Quảng Bình', '233': 'Quảng Trị', '234': 'Huế', '235': 'Quảng Nam',
    '236': 'Đà Nẵng', '237': 'Thanh Hóa', '238': 'Nghệ An', '239': 'Hà Tĩnh', '252': 'Bình Thuận',
    '255': 'Quảng Ngãi', '256': 'Bình Định', '257': 'Phú Yên', '258': 'Khánh Hòa', '259': 'Ninh Thuận',
    '260': 'Kon Tum', '261': 'Đồng Nai', '262': 'Đắk Lắk', '263': 'Lâm Đồng', '269': 'Gia Lai',
    '270': 'Vĩnh Long', '271': 'Bình Phước', '272': 'Long An', '273': 'Tiền Giang', '274': 'Bình Dương',
    '275': 'Bến Tre', '276': 'Tây Ninh', '277': 'Đồng Tháp', '290': 'Cà Mau', '291': 'Bạc Liêu',
    '292': 'Cần Thơ', '293': 'Hậu Giang', '294': 'Trà Vinh', '296': 'An Giang', '297': 'Kiên Giang', '299': 'Sóc Trăng',
  };

  static const Map<String, List<String>> _carrierPrefixes = {
    'Viettel': ['032','033','034','035','036','037','038','039','086','096','097','098'],
    'VinaPhone': ['081','082','083','084','085','088','091','094'],
    'MobiFone': ['070','076','077','078','079','089','090','093'],
    'Vietnamobile': ['052','056','058','092'],
    'Gmobile': ['059','099'],
    'iTel': ['087'],
  };

  static const Map<String, String> _plateCodes = {
    '11':'Cao Bằng','12':'Lạng Sơn','14':'Quảng Ninh','15':'Hải Phòng','16':'Hải Phòng','17':'Thái Bình','18':'Nam Định','19':'Phú Thọ',
    '20':'Thái Nguyên','21':'Yên Bái','22':'Tuyên Quang','23':'Hà Giang','24':'Lào Cai','25':'Lai Châu','26':'Sơn La','27':'Điện Biên','28':'Hòa Bình',
    '29':'Hà Nội','30':'Hà Nội','31':'Hà Nội','32':'Hà Nội','33':'Hà Nội','40':'Hà Nội','34':'Hải Dương','35':'Ninh Bình','36':'Thanh Hóa','37':'Nghệ An','38':'Hà Tĩnh',
    '43':'Đà Nẵng','47':'Đắk Lắk','48':'Đắk Nông','49':'Lâm Đồng','41':'TP Hồ Chí Minh','50':'TP Hồ Chí Minh','51':'TP Hồ Chí Minh','52':'TP Hồ Chí Minh','53':'TP Hồ Chí Minh','54':'TP Hồ Chí Minh','55':'TP Hồ Chí Minh','56':'TP Hồ Chí Minh','57':'TP Hồ Chí Minh','58':'TP Hồ Chí Minh','59':'TP Hồ Chí Minh',
    '60':'Đồng Nai','61':'Bình Dương','62':'Long An','63':'Tiền Giang','64':'Vĩnh Long','65':'Cần Thơ','66':'Đồng Tháp','67':'An Giang','68':'Kiên Giang','69':'Cà Mau',
    '70':'Tây Ninh','71':'Bến Tre','72':'Bà Rịa - Vũng Tàu','73':'Quảng Bình','74':'Quảng Trị','75':'Huế','76':'Quảng Ngãi','77':'Bình Định','78':'Phú Yên','79':'Khánh Hòa',
    '81':'Gia Lai','82':'Kon Tum','83':'Sóc Trăng','84':'Trà Vinh','85':'Ninh Thuận','86':'Bình Thuận','88':'Vĩnh Phúc','89':'Hưng Yên','90':'Hà Nam','92':'Quảng Nam','93':'Bình Phước','94':'Bạc Liêu','95':'Hậu Giang','97':'Bắc Kạn','98':'Bắc Giang','99':'Bắc Ninh',
  };
}
