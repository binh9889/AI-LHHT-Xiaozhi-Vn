import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final Uri? externalUri;
  final bool requiresFollowUp;
  final bool success;
}

/// Công cụ realtime chạy ngay trong APK.
///
/// Mục đích là không phụ thuộc việc Agent tenclass có cài plugin xổ số/nhạc
/// hay không. Những intent được hỗ trợ sẽ được app chặn trước khi gửi LLM.
class RealtimeToolService {
  RealtimeToolService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static final RegExp _lotteryIntent = RegExp(
    r'(xổ\s*số|sổ\s*xố|sổ\s*số|xsmb|kết\s*quả.{0,15}miền\s*bắc|miền\s*bắc.{0,15}kết\s*quả)',
    caseSensitive: false,
  );
  static final RegExp _musicIntent = RegExp(
    r'(bật\s*nhạc|mở\s*nhạc|phát\s*nhạc|nghe\s*nhạc|bài\s*hát|ca\s*sĩ|âm\s*nhạc|music)',
    caseSensitive: false,
  );

  bool isLotteryIntent(String text) => _lotteryIntent.hasMatch(text);
  bool isMusicIntent(String text) => _musicIntent.hasMatch(text);

  Future<RealtimeToolResult?> handle(
    String text, {
    bool forceMusic = false,
  }) async {
    final input = text.trim();
    if (input.isEmpty) return null;
    if (isLotteryIntent(input)) return fetchNorthernLottery(input);
    if (forceMusic || isMusicIntent(input)) return searchMusic(input, forceMusic: forceMusic);
    return null;
  }

  Future<RealtimeToolResult> fetchNorthernLottery(String query) async {
    const source =
        'https://raw.githubusercontent.com/khiemdoan/vietnam-lottery-xsmb-analysis/refs/heads/main/data/xsmb.csv';
    try {
      final response = await _client
          .get(Uri.parse(source), headers: const {'Accept': 'text/csv'})
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final lines = const LineSplitter()
          .convert(response.body)
          .where((line) => line.trim().isNotEmpty)
          .toList();
      if (lines.length < 2) throw Exception('Nguồn xổ số chưa có dữ liệu.');

      final headers = lines.first.split(',');
      final requestedDate = _extractRequestedDate(query);
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final wanted = requestedDate ?? today;

      List<String>? selected;
      for (var i = lines.length - 1; i >= 1; i--) {
        final row = lines[i].split(',');
        if (row.isNotEmpty && row.first.trim() == wanted) {
          selected = row;
          break;
        }
      }

      var stale = false;
      if (selected == null && requestedDate == null) {
        selected = lines.last.split(',');
        stale = selected.first.trim() != today;
      }
      if (selected == null) {
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
    } catch (e) {
      return RealtimeToolResult(
        kind: RealtimeToolKind.lottery,
        success: false,
        text: 'Không lấy được kết quả xổ số trực tuyến lúc này. Kiểm tra mạng rồi thử lại. (${_shortError(e)})',
      );
    }
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
        text: 'Bạn muốn nghe ca sĩ hoặc bài hát nào? Nói tên bài hoặc tên ca sĩ, mình sẽ tìm trực tuyến.',
      );
    }

    var effectiveQuery = query;
    var label = query;
    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': query,
        'country': 'VN',
        'media': 'music',
        'entity': 'song',
        'limit': '5',
        'explicit': 'No',
      });
      final response = await _client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['results'] is List && (decoded['results'] as List).isNotEmpty) {
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
      // Apple catalog chỉ giúp chọn kết quả đẹp hơn. Nếu lỗi vẫn mở tìm kiếm
      // trực tuyến bằng truy vấn người dùng ban đầu.
    }

    final external = Uri.https('music.youtube.com', '/search', {'q': effectiveQuery});
    return RealtimeToolResult(
      kind: RealtimeToolKind.music,
      externalUri: external,
      text: 'Mình đã tìm nhạc trực tuyến cho “$label”. Đang mở YouTube Music để phát từ nguồn online, không dùng kho 5 bài cục bộ nữa.',
    );
  }

  Future<bool> openExternal(Uri uri) async {
    try {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
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
    return List.generate(count, (index) => _pad(row['$prefix${index + 1}'], width))
        .where((value) => value.isNotEmpty)
        .join(', ');
  }

  String _pad(String? value, int width) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return '';
    return text.padLeft(width, '0');
  }

  String _displayDate(String iso) {
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  String _shortError(Object error) {
    final text = error.toString().replaceAll('\n', ' ');
    return text.length > 90 ? '${text.substring(0, 90)}…' : text;
  }
}
