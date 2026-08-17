import 'package:ai_assistant/tools/models/tool_models.dart';

class ToolCacheEntry {
  const ToolCacheEntry(this.result, this.expiresAt);
  final ToolResult result;
  final DateTime expiresAt;

  bool get isValid => DateTime.now().isBefore(expiresAt);
}

class ToolCache {
  final Map<String, ToolCacheEntry> _items = <String, ToolCacheEntry>{};

  ToolResult? get(String key) {
    final item = _items[key];
    if (item == null) return null;
    if (!item.isValid) {
      _items.remove(key);
      return null;
    }
    return item.result.copyWith(freshness: ToolResultFreshness.cached);
  }

  void put(String key, ToolResult result, Duration ttl) {
    _items[key] = ToolCacheEntry(result, DateTime.now().add(ttl));
  }

  void clear() => _items.clear();
}
