import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_assistant/tools/services/realtime_tool_engine.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('local lunar tool works without network', () async {
    final engine = RealtimeToolEngine();
    final result = await engine.execute('lunar_calendar', query: 'âm lịch hôm nay');
    expect(result.success, isTrue);
    expect(result.summary, contains('âm lịch'));
  });

  test('local area code and carrier tools return structured results', () async {
    final engine = RealtimeToolEngine();
    final area = await engine.execute('vn_area_code', query: '0236 là tỉnh nào');
    expect(area.success, isTrue);
    expect(area.summary.toLowerCase(), contains('đà nẵng'));

    final hanoi = await engine.execute('vn_area_code', query: '024 là tỉnh nào');
    expect(hanoi.success, isTrue);
    expect(hanoi.summary.toLowerCase(), contains('hà nội'));

    final carrier = await engine.execute('vn_carrier_lookup', query: '098 là mạng gì');
    expect(carrier.success, isTrue);
    expect(carrier.summary, contains('Viettel'));
  });
}
