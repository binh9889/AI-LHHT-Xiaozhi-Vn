import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

enum RealtimeToolKind { lottery, music }

class RealtimeToolResult {
  const RealtimeToolResult({
    required this.kind,
    required this.text,
    this.externalUri,
    this.requiresFollowUp = false,
    this.success = true,
  });

  final RealtimeToolKind kind;
  final String text;

  /// URI online được mở BÊN TRONG ứng dụng bởi MusicPlayerScreen.
  /// Tên field được giữ để tương thích source cũ.
  final Uri? externalUri;
  final bool requiresFollowUp;
  final bool success;
}

/// Router công cụ realtime chạy ngay trong APK.
///
/// Các intent được hỗ trợ không phụ thuộc Agent Xiaozhi có plugin tương ứng
/// hay không. Điều này tránh tình trạng Agent trả lời "không có công cụ".
class RealtimeToolService {
  RealtimeToolService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static final RegExp _lotteryIntent = RegExp(
    r'(xổ\s*số|sổ\s*xố|sổ\s*số|xổ\s*xố|xsmb|kết\s*quả.{0,20}miền\s*bắc|miền\s*bắc.{0,20}kết\s*quả)',
    caseSensitive: false,
  );
  static final RegExp _musicIntent = RegExp(
    r'(bật\s*nhạc|mở\s*nhạc|phát\s*nhạc|nghe\s*nhạc|bài\s*hát|ca\s*sĩ|âm\s*nhạc|music)',
    caseSensitive: false,
  );

  static const List<String> _lotterySources = <String>[
    'https://raw.githubusercontent.com/khiemdoan/vietnam-lottery-xsmb-analysis/refs/heads/main/data/xsmb.csv',
    'https://raw.githubusercontent.com/AnhTuPhi/xsmb-vietnam-lottery-analysis/refs/heads/master/data/xsmb.csv',
  ];

  String? _lastLotteryText;
  DateTime? _lastLotteryFetchedAt;

  bool isLotteryIntent(String text) => _lotteryIntent.hasMatch(text);
  bool isMusicIntent(String text) => _musicIntent.hasMatch(text);

  Future<RealtimeToolResult?> handle(
    String text, {
    bool forceMusic = false,
  }) async {
    final input = text.trim();
    if (input.isEmpty) return null;
    if (isLotteryIntent(input)) return fetchNorthernLottery(input);
    if (forceMusic || isMusicIntent(input)) {
      return searchMusic(input, forceMusic: forceMusic);
    }
    return null;
  }

  Future<RealtimeToolResult> fetchNorthernLottery(String query) async {
    final requestedDate = _extractRequestedDate(query);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final wanted = requestedDate ?? today;
    Object? lastError;

    for (final source in _lotterySources) {
      try {
        final response = await _getWithRetry(Uri.parse(source));
        if (response.statusCode != 200 || response.body.trim().isEmpty) {
          throw Exception('HTTP ${response.statusCode}');
        }

        final result = _parseLotteryCsv(
          response.body,
          wanted: wanted,
          requestedDate: requestedDate,
          today: today,
        );
        if (result != null) {
          _lastLotteryText = result.text;
          _lastLotteryFetchedAt = DateTime.now();
          return result;
        }
      } catch (e) {
        lastError = e;
      }
    }

    // Nếu mạng chập chờn trong cùng phiên app, giữ kết quả online gần nhất
    // thay vì trả lỗi trắng. Luôn ghi rõ đây là cache để không gây hiểu lầm.
    final cached = _lastLotteryText;
    final cachedAt = _lastLotteryFetchedAt;
    if (requestedDate == null && cached != null && cachedAt != null) {
      return RealtimeToolResult(
        kind: RealtimeToolKind.lottery,
        success: true,
        text: 'Mạng đang không ổn định. Đây là kết quả trực tuyến gần nhất app đã lấy lúc '
            '${DateFormat('HH:mm').format(cachedAt)}:\n$cached',
      );
    }

    return RealtimeToolResult(
      kind: RealtimeToolKind.lottery,
      success: false,
      text: 'Không lấy được kết quả xổ số miền Bắc trực tuyến lúc này. '
          'App đã thử ${_lotterySources.length} nguồn. Hãy kiểm tra mạng rồi thử lại. '
          '(${_shortError(lastError)})',
    );
  }

  Future<http.Response> _getWithRetry(Uri uri) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client.get(
          uri,
          headers: const {
            'Accept': 'text/csv,*/*;q=0.8',
            'User-Agent': 'AI-LHHT/3.4 Android',
            'Cache-Control': 'no-cache',
          },
        ).timeout(const Duration(seconds: 9));
        if (response.statusCode >= 500 && attempt == 0) {
          lastError = Exception('HTTP ${response.statusCode}');
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
        return response;
      } catch (e) {
        lastError = e;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
      }
    }
    throw Exception('Không thể tải nguồn: $lastError');
  }

  RealtimeToolResult? _parseLotteryCsv(
    String csv, {
    required String wanted,
    required String? requestedDate,
    required String today,
  }) {
    final lines = const LineSplitter()
        .convert(csv)
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) throw Exception('Nguồn xổ số chưa có dữ liệu.');

    final headers = _splitCsvLine(lines.first);
    List<String>? selected;
    for (var i = lines.length - 1; i >= 1; i--) {
      final row = _splitCsvLine(lines[i]);
      if (row.isNotEmpty && row.first.trim() == wanted) {
        selected = row;
        break;
      }
    }

    var stale = false;
    if (selected == null && requestedDate == null) {
      selected = _splitCsvLine(lines.last);
      stale = selected.isNotEmpty && selected.first.trim() != today;
    }
    if (selected == null || selected.isEmpty) {
      return RealtimeToolResult(
        kind: RealtimeToolKind.lottery,
        success: false,
        text: 'Nguồn trực tuyến chưa có kết quả xổ số miền Bắc ngày ${_displayDate(wanted)}.',
      );
    }

    final row = <String, String>{};
    for (var i = 0; i < headers.length && i < selected.length; i++) {
      row[headers[i].trim()] = selected[i].trim();
    }

    final date = row['date'] ?? wanted;
    final special = _pad(row['special'], 5);
    final p1 = _pad(row['prize1'], 5);
    final p2 = _join(row, 'prize2_', 2, 5);
    final p3 = _join(row, 'prize3_', 6, 5);
    final p4 = _join(row, 'prize4_', 4, 4);
    final p5 = _join(row, 'prize5_', 6, 4);
    final p6 = _join(row, 'prize6_', 3, 3);
    final p7 = _join(row, 'prize7_', 4, 2);

    final prefix = stale
        ? 'Nguồn chưa cập nhật kỳ hôm nay. Kết quả miền Bắc mới nhất đang có là ngày ${_displayDate(date)}:'
        : 'Kết quả xổ số miền Bắc ngày ${_displayDate(date)}:';
    final text = '$prefix\n'
        'Đặc biệt: $special\n'
        'Giải nhất: $p1\n'
        'Giải nhì: $p2\n'
        'Giải ba: $p3\n'
        'Giải tư: $p4\n'
        'Giải năm: $p5\n'
        'Giải sáu: $p6\n'
        'Giải bảy: $p7';
    return RealtimeToolResult(kind: RealtimeToolKind.lottery, text: text);
  }

  /// Parser đơn giản nhưng tôn trọng dấu phẩy nằm trong chuỗi quoted.
  List<String> _splitCsvLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    result.add(buffer.toString());
    return result;
  }

  Future<RealtimeToolResult> searchMusic(
    String input, {
    bool forceMusic = false,
  }) async {
    final query = _extractMusicQuery(input, forceMusic: forceMusic);
    if (query.isEmpty) {
      return const RealtimeToolResult(
        kind: RealtimeToolKind.music,
        requiresFollowUp: true,
        text: 'Bạn muốn nghe ca sĩ hoặc bài hát nào? Nói tên bài hoặc tên ca sĩ, mình sẽ mở trình phát trực tuyến ngay trong app.',
      );
    }

    var effectiveQuery = query;
    var label = query;

    // Catalog chỉ dùng để chuẩn hóa tên bài/ca sĩ. Playback thực tế ở màn
    // hình web player trong app, không tải/giải mã audio từ YouTube.
    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': query,
        'country': 'VN',
        'media': 'music',
        'entity': 'song',
        'limit': '5',
        'explicit': 'No',
      });
      final response = await _client.get(uri).timeout(const Duration(seconds: 7));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map &&
            decoded['results'] is List &&
            (decoded['results'] as List).isNotEmpty) {
          final first = (decoded['results'] as List).first;
          if (first is Map) {
            final track = (first['trackName'] ?? '').toString().trim();
            final artist = (first['artistName'] ?? '').toString().trim();
            if (track.isNotEmpty) {
              label = artist.isEmpty ? track : '$track – $artist';
              effectiveQuery = artist.isEmpty ? track : '$track $artist';
            }
          }
        }
      }
    } catch (_) {
      // Không để lỗi catalog làm hỏng phát nhạc.
    }

    // Dùng giao diện YouTube mobile trong WebView của chính AI-LHHT.
    // Không bật ứng dụng YouTube bên ngoài và không trích xuất stream trái phép.
    final inApp = Uri.https('m.youtube.com', '/results', {
      'search_query': effectiveQuery,
    });
    return RealtimeToolResult(
      kind: RealtimeToolKind.music,
      externalUri: inApp,
      text: 'Đã tìm nhạc trực tuyến cho “$label”. Mình mở trình phát online ngay trong AI-LHHT; chọn bài trong kết quả để phát, không dùng kho 5 bài cục bộ.',
    );
  }

  String _extractMusicQuery(String input, {required bool forceMusic}) {
    var value = input.trim();
    if (forceMusic) {
      value = value.replaceFirst(
        RegExp(r'^\s*(ca\s*sĩ|bài\s*hát|bài)\s*[:\-]?\s*', caseSensitive: false),
        '',
      );
    } else {
      value = value.replaceAll(
        RegExp(
          r'\b(hãy|giúp|tôi|mình|cho|bạn|ơi|bật|mở|phát|nghe|tìm|kiếm|nhạc|bài hát|bài|ca sĩ|của)\b',
          caseSensitive: false,
        ),
        ' ',
      );
    }
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return value;
  }

  String? _extractRequestedDate(String query) {
    final dmy = RegExp(r'\b(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})\b').firstMatch(query);
    if (dmy != null) {
      final day = int.tryParse(dmy.group(1) ?? '');
      final month = int.tryParse(dmy.group(2) ?? '');
      final year = int.tryParse(dmy.group(3) ?? '');
      if (day != null && month != null && year != null) {
        return DateFormat('yyyy-MM-dd').format(DateTime(year, month, day));
      }
    }
    final iso = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b').firstMatch(query);
    if (iso != null) {
      final year = int.tryParse(iso.group(1) ?? '');
      final month = int.tryParse(iso.group(2) ?? '');
      final day = int.tryParse(iso.group(3) ?? '');
      if (day != null && month != null && year != null) {
        return DateFormat('yyyy-MM-dd').format(DateTime(year, month, day));
      }
    }
    return null;
  }

  String _join(Map<String, String> row, String prefix, int count, int width) {
    final values = <String>[];
    for (var i = 1; i <= count; i++) {
      final value = row['$prefix$i'];
      if (value != null && value.trim().isNotEmpty) values.add(_pad(value, width));
    }
    return values.isEmpty ? '—' : values.join(', ');
  }

  String _pad(String? value, int width) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '—';
    return raw.padLeft(width, '0');
  }

  String _displayDate(String value) {
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(value));
    } catch (_) {
      return value;
    }
  }

  String _shortError(Object? e) {
    if (e == null) return 'không rõ nguyên nhân';
    final value = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return value.length > 100 ? '${value.substring(0, 100)}…' : value;
  }
}
