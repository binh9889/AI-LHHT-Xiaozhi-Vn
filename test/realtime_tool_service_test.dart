import 'package:ai_assistant/services/realtime_tool_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('nhận đúng intent xổ số kể cả lỗi phát âm sổ số', () {
    final service = RealtimeToolService();
    expect(service.isLotteryIntent('kiểm tra kết quả sổ số hôm nay'), isTrue);
    expect(service.isLotteryIntent('xổ số miền bắc'), isTrue);
    expect(service.isLotteryIntent('kết quả sổ xố miền bắc'), isTrue);
  });

  test('bật nhạc không có tên bài yêu cầu hỏi tiếp', () async {
    final service = RealtimeToolService();
    final result = await service.handle('hãy giúp tôi bật nhạc');
    expect(result, isNotNull);
    expect(result!.kind, RealtimeToolKind.music);
    expect(result.requiresFollowUp, isTrue);
  });

  test('xổ số parse CSV và giữ số 0 đầu giải bảy', () async {
    final now = DateTime.now();
    final yyyy = now.year.toString().padLeft(4, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final date = '$yyyy-$mm-$dd';
    const header = 'date,special,prize1,prize2_1,prize2_2,prize3_1,prize3_2,prize3_3,prize3_4,prize3_5,prize3_6,prize4_1,prize4_2,prize4_3,prize4_4,prize5_1,prize5_2,prize5_3,prize5_4,prize5_5,prize5_6,prize6_1,prize6_2,prize6_3,prize7_1,prize7_2,prize7_3,prize7_4';
    final row = '$date,12345,23456,34567,45678,11111,22222,33333,44444,55555,66666,1001,1002,1003,1004,2001,2002,2003,2004,2005,2006,301,302,303,1,2,3,4';
    final client = MockClient((request) async => http.Response('$header\n$row\n', 200));
    final service = RealtimeToolService(client: client);
    final result = await service.fetchNorthernLottery('xổ số hôm nay');
    expect(result.success, isTrue);
    expect(result.text, contains('Đặc biệt: 12345'));
    expect(result.text, contains('01, 02, 03, 04'));
  });

  test('xổ số chuyển nguồn khi nguồn đầu lỗi', () async {
    final now = DateTime.now();
    final yyyy = now.year.toString().padLeft(4, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final date = '$yyyy-$mm-$dd';
    const header = 'date,special,prize1,prize2_1,prize2_2,prize3_1,prize3_2,prize3_3,prize3_4,prize3_5,prize3_6,prize4_1,prize4_2,prize4_3,prize4_4,prize5_1,prize5_2,prize5_3,prize5_4,prize5_5,prize5_6,prize6_1,prize6_2,prize6_3,prize7_1,prize7_2,prize7_3,prize7_4';
    final row = '$date,54321,23456,34567,45678,11111,22222,33333,44444,55555,66666,1001,1002,1003,1004,2001,2002,2003,2004,2005,2006,301,302,303,1,2,3,4';
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls <= 2) return http.Response('temporary', 503);
      return http.Response('$header\n$row\n', 200);
    });
    final service = RealtimeToolService(client: client);
    final result = await service.fetchNorthernLottery('xổ số hôm nay');
    expect(result.success, isTrue);
    expect(result.text, contains('Đặc biệt: 54321'));
  });

  test('music search trả link web player để mở trong app', () async {
    final client = MockClient((request) async => http.Response(
          '{"resultCount":1,"results":[{"trackName":"Test Song","artistName":"Test Artist"}]}',
          200,
        ));
    final service = RealtimeToolService(client: client);
    final result = await service.searchMusic('Test Artist', forceMusic: true);
    expect(result.externalUri, isNotNull);
    expect(result.externalUri!.host, 'm.youtube.com');
    expect(result.text, contains('ngay trong AI-LHHT'));
  });
}
