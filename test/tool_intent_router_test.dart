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

  test('extracts crypto symbol and weather location', () {
    final crypto = router.route('Ethereum hôm nay tăng hay giảm?');
    expect(crypto?.parameters['symbol'], 'ETH');
    final weather = router.route('thời tiết Đà Nẵng hôm nay');
    expect(weather?.parameters['location']?.toLowerCase(), contains('đà nẵng'));
  });

  test('routes currency conversion', () {
    final route = router.route('100 USD sang VND');
    expect(route?.toolId, 'currency_converter');
    expect(route?.parameters['from'], 'USD');
    expect(route?.parameters['to'], 'VND');
  });
}
