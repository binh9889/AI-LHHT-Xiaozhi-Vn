import 'package:shared_preferences/shared_preferences.dart';

class ToolProviderConfig {
  const ToolProviderConfig({
    this.bridgeUrl = '',
    this.bridgeToken = '',
    this.sportsDbKey = '123',
  });

  final String bridgeUrl;
  final String bridgeToken;
  final String sportsDbKey;

  bool get hasBridge => bridgeUrl.trim().isNotEmpty;

  ToolProviderConfig copyWith({
    String? bridgeUrl,
    String? bridgeToken,
    String? sportsDbKey,
  }) {
    return ToolProviderConfig(
      bridgeUrl: bridgeUrl ?? this.bridgeUrl,
      bridgeToken: bridgeToken ?? this.bridgeToken,
      sportsDbKey: sportsDbKey ?? this.sportsDbKey,
    );
  }
}

class ToolProviderConfigStore {
  static const _bridgeUrlKey = 'v4_tools_bridge_url';
  static const _bridgeTokenKey = 'v4_tools_bridge_token';
  static const _sportsDbKey = 'v4_tools_sportsdb_key';

  Future<ToolProviderConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ToolProviderConfig(
      bridgeUrl: prefs.getString(_bridgeUrlKey) ?? '',
      bridgeToken: prefs.getString(_bridgeTokenKey) ?? '',
      sportsDbKey: prefs.getString(_sportsDbKey) ?? '123',
    );
  }

  Future<void> save(ToolProviderConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bridgeUrlKey, config.bridgeUrl.trim());
    await prefs.setString(_bridgeTokenKey, config.bridgeToken.trim());
    await prefs.setString(_sportsDbKey, config.sportsDbKey.trim().isEmpty ? '123' : config.sportsDbKey.trim());
  }
}
