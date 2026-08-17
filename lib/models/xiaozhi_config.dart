class XiaozhiConfig {
  final String id;
  final String name;
  final String websocketUrl;
  final String macAddress;
  final String clientId;
  final String token;

  XiaozhiConfig({
    required this.id,
    required this.name,
    required this.websocketUrl,
    required this.macAddress,
    required this.clientId,
    required this.token,
  });

  factory XiaozhiConfig.fromJson(Map<String, dynamic> json) {
    final mac = (json['macAddress'] ?? '').toString();
    return XiaozhiConfig(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      websocketUrl: (json['websocketUrl'] ?? '').toString(),
      macAddress: mac,
      // Empty means this config was saved before v2.2.0; ConfigProvider migrates it.
      clientId: (json['clientId'] ?? '').toString(),
      token: (json['token'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'websocketUrl': websocketUrl,
      'macAddress': macAddress,
      'clientId': clientId,
      'token': token,
    };
  }

  XiaozhiConfig copyWith({
    String? name,
    String? websocketUrl,
    String? macAddress,
    String? clientId,
    String? token,
  }) {
    return XiaozhiConfig(
      id: id,
      name: name ?? this.name,
      websocketUrl: websocketUrl ?? this.websocketUrl,
      macAddress: macAddress ?? this.macAddress,
      clientId: clientId ?? this.clientId,
      token: token ?? this.token,
    );
  }
}
