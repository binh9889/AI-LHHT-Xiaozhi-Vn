import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/tools/services/tool_intent_router.dart';

void main() {
  const router = ToolIntentRouter();

  test('routes common Vietnamese realtime intents before Agent', () {
    expect(router.route('kiểm tra kết quả sổ xố miền bắc hôm nay')?.toolId, 'vn_lottery');
    expect(router.route('thời tiết Hà Nội hôm nay')?.toolId, 'weather');
    expect(router.route('AQI Hồ Chí Minh hiện tại')?.toolId, 'air_quality');
    expect(router.route('Bitcoin đang bao nhiêu')?.toolId, 'crypto_price');
    expect(router.route('giá vàng SJC hôm nay')?.toolId, 'gold_price');
    expect(router.route('tin nóng hôm nay')?.toolId, 'news_latest');
  });

  test('Vietnamese accented phrases are routed with Unicode-safe boundaries', () {
    expect(router.route('xổ số miền Bắc hôm nay')?.toolId, 'vn_lottery');
    expect(router.route('thời tiết Hà Nội')?.toolId, 'weather');
    expect(router.route('giá vàng hôm nay')?.toolId, 'gold_price');
    expect(router.route('lãi suất ngân hàng')?.toolId, 'vn_bank_interest');
    expect(router.route('tin tức mới nhất')?.toolId, 'news_latest');
  });

  test('routes carrier phrase observed from voice transcript', () {
    expect(
      router.route('số điện thoại đầu 098 là mạng nào')?.toolId,
      'vn_carrier_lookup',
    );
  });

  test('routes repaired lottery phrase observed in runtime', () {
    expect(
      router.route('kết quả sổ số miền mắt hôm nay')?.toolId,
      'vn_lottery',
    );
  });

  test('extracts crypto symbol and weather location', () {
    final crypto = router.route('Ethereum hôm nay tăng hay giảm?');
    expect(crypto?.parameters['symbol'], 'ETH');
    final weather = router.route('thời tiết Đà Nẵng hôm nay');
    expect(weather?.parameters['location']?.toLowerCase(), contains('đà nẵng'));
  });

  test('keeps explicitly spoken weather location', () {
    final ward = router.route('thời tiết ở Chánh Hiệp hôm nay');
    expect(ward?.toolId, 'weather');
    expect(ward?.parameters['location'], 'Chánh Hiệp');

    final city = router.route('thời tiết tại Đà Nẵng bây giờ');
    expect(city?.toolId, 'weather');
    expect(city?.parameters['location'], 'Đà Nẵng');
  });

  test('routes currency conversion', () {
    final route = router.route('100 USD sang VND');
    expect(route?.toolId, 'currency_converter');
    expect(route?.parameters['from'], 'USD');
    expect(route?.parameters['to'], 'VND');
  });
}
