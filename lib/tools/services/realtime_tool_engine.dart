import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_assistant/tools/models/tool_models.dart';
import 'package:ai_assistant/tools/providers/public_data_providers.dart';
import 'package:ai_assistant/tools/services/tool_cache.dart';
import 'package:ai_assistant/tools/services/tool_intent_router.dart';
import 'package:ai_assistant/tools/services/tool_provider_config.dart';

class RealtimeToolEngine {
  RealtimeToolEngine({
    ToolIntentRouter? router,
    PublicDataProviders? providers,
    ToolCache? cache,
    ToolProviderConfigStore? configStore,
  })  : _router = router ?? const ToolIntentRouter(),
        _providers = providers ?? PublicDataProviders(),
        _cache = cache ?? ToolCache(),
        _configStore = configStore ?? ToolProviderConfigStore();

  final ToolIntentRouter _router;
  final PublicDataProviders _providers;
  final ToolCache _cache;
  final ToolProviderConfigStore _configStore;

  Future<ToolResult?> handle(String query) async {
    final route = _router.route(query);
    if (route == null || route.confidence < .72) return null;
    return executeRoute(query, route);
  }

  Future<ToolResult> execute(
    String toolId, {
    String query = '',
    Map<String, String> parameters = const <String, String>{},
  }) {
    return executeRoute(
      query.isEmpty ? toolId : query,
      ToolRoute(toolId: toolId, confidence: 1, parameters: parameters),
    );
  }

  Future<ToolResult> executeRoute(String query, ToolRoute route) async {
    final cacheKey = '${route.toolId}|${route.parameters}|${query.trim().toLowerCase()}';
    final cached = _cache.get(cacheKey);
    if (cached != null) return cached;

    final config = _isLocalTool(route.toolId)
        ? const ToolProviderConfig()
        : await _configStore.load();
    final result = await _providers.execute(
      route.toolId,
      query,
      route.parameters,
      config,
    );
    if (result.success) {
      _cache.put(cacheKey, result, _ttlFor(route.toolId));
    }
    await _saveHistory(query, result);
    return result;
  }

  bool _isLocalTool(String toolId) {
    switch (toolId) {
      case 'lunar_calendar':
      case 'vn_area_code':
      case 'vn_carrier_lookup':
      case 'vn_plate_lookup':
        return true;
      default:
        return false;
    }
  }

  Duration _ttlFor(String toolId) {
    switch (toolId) {
      case 'crypto_price':
        return const Duration(seconds: 25);
      case 'weather':
      case 'air_quality':
        return const Duration(minutes: 7);
      case 'fx_rate':
      case 'currency_converter':
        return const Duration(minutes: 5);
      case 'news_latest':
      case 'sports_score':
        return const Duration(minutes: 3);
      case 'gold_price':
        return const Duration(minutes: 3);
      case 'lunar_calendar':
      case 'vn_area_code':
      case 'vn_carrier_lookup':
      case 'vn_plate_lookup':
        return const Duration(hours: 24);
      default:
        return const Duration(minutes: 2);
    }
  }

  Future<void> _saveHistory(String query, ToolResult result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList('v4_tool_history') ?? <String>[];
      final item = jsonEncode(<String, dynamic>{
        'toolId': result.toolId,
        'query': query,
        'summary': result.summary,
        'success': result.success,
        'timestamp': result.timestamp.toIso8601String(),
        'latencyMs': result.latencyMs,
      });
      final updated = <String>[item, ...existing].take(30).toList();
      await prefs.setStringList('v4_tool_history', updated);
    } catch (_) {
      // History is non-critical. Never fail a realtime lookup because local
      // preferences are temporarily unavailable.
    }
  }

  Future<List<Map<String, dynamic>>> history() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('v4_tool_history') ?? <String>[];
    return raw.map((item) {
      try {
        return Map<String, dynamic>.from(jsonDecode(item) as Map);
      } catch (_) {
        return <String, dynamic>{};
      }
    }).where((item) => item.isNotEmpty).toList();
  }

  void clearCache() => _cache.clear();
}
