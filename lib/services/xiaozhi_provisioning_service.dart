import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/device_util.dart';

class XiaozhiProvisioningResult {
  final String deviceId;
  final String clientId;
  final String otaUrl;
  final String requestProfile;
  final String? websocketUrl;
  final String? token;
  final String? activationCode;
  final String? activationMessage;
  final String? activationChallenge;
  final int? activationTimeoutMs;
  final bool isTestCredential;
  final bool isHealthResponse;
  final int httpStatus;
  final String finalUrl;
  final Map<String, dynamic> raw;

  const XiaozhiProvisioningResult({
    required this.deviceId,
    required this.clientId,
    required this.otaUrl,
    required this.requestProfile,
    required this.websocketUrl,
    required this.token,
    required this.activationCode,
    required this.activationMessage,
    required this.activationChallenge,
    required this.activationTimeoutMs,
    required this.isTestCredential,
    required this.isHealthResponse,
    required this.httpStatus,
    required this.finalUrl,
    required this.raw,
  });

  bool get hasActivationCode =>
      activationCode != null && activationCode!.trim().isNotEmpty;

  bool get hasActivationChallenge =>
      activationChallenge != null && activationChallenge!.trim().isNotEmpty;

  bool get hasWebSocket =>
      websocketUrl != null && websocketUrl!.trim().isNotEmpty;

  bool get hasUsableToken =>
      token != null && token!.trim().isNotEmpty && token != 'test-token';

  /// Chỉ coi là cấu hình production khi server cấp WebSocket + token thật.
  bool get canConnectProduction => hasWebSocket && hasUsableToken;

  /// Dùng cho chẩn đoán giao thức. Không nên lưu thành cấu hình Agent chính.
  bool get canConnectDiagnostic =>
      hasWebSocket && token != null && token!.trim().isNotEmpty;
}

/// OTA/provisioning client cho Android theo hình dạng request mà server
/// Xiaozhi mã nguồn mở công bố: POST JSON với hai khối `application` và
/// `board`, kèm Device-Id/Client-Id.
///
/// Android không có serial/HMAC eFuse của thiết bị ESP32 nên không giả mạo
/// Serial-Number hoặc HMAC. Activation-Version=1 được dùng cho nhánh không có
/// danh tính phần cứng nhà máy.
class XiaozhiProvisioningService {
  static const String officialOtaUrl =
      'https://api.tenclass.net/xiaozhi/ota/';
  static const String appVersion = '3.1.0';

  static Future<XiaozhiProvisioningResult> provision({
    String otaUrl = officialOtaUrl,
  }) async {
    final deviceId = await DeviceUtil.getStableMacAddress();
    final clientId = await DeviceUtil.getStableClientId();
    final model = await DeviceUtil.getDeviceModel();
    final os = await DeviceUtil.getOsVersion();

    final uri = Uri.parse(otaUrl);
    final headers = <String, String>{
      'Accept': 'application/json',
      'Accept-Language': 'vi-VN,vi;q=0.9,en;q=0.8',
      'User-Agent': 'AI-LHHT-Android/$appVersion ($model; $os)',
      'Activation-Version': '1',
      'Device-Id': deviceId,
      'Client-Id': clientId,
      'Content-Type': 'application/json',
    };

    // Hình dạng request tối thiểu bám tài liệu OTA server mã nguồn mở.
    // elf_sha256='1' là giá trị probe tương thích được tài liệu server dùng
    // trong ví dụ curl để kiểm tra luồng OTA; app không tuyên bố đây là hash
    // firmware ESP32 thật.
    final payload = <String, dynamic>{
      'application': <String, dynamic>{
        'name': 'AI-LHHT-Android',
        'version': appVersion,
        'elf_sha256': '1',
      },
      'board': <String, dynamic>{
        'type': 'android',
        'name': model,
        'mac': deviceId,
        'uuid': clientId,
        'os_version': os,
      },
    };

    const requestProfile = 'official-minimal-application-board-v1';

    // Log không chứa token/secret.
    print('XiaozhiProvisioning: POST $uri');
    print('XiaozhiProvisioning: profile=$requestProfile');
    print('XiaozhiProvisioning: Device-Id=$deviceId Client-Id=$clientId');
    print('XiaozhiProvisioning: Activation-Version=1');
    print('XiaozhiProvisioning: body=${jsonEncode(payload)}');

    final response = await http
        .post(uri, headers: headers, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 20));

    final bodyText = utf8.decode(response.bodyBytes);
    final finalUrl = response.request?.url.toString() ?? otaUrl;
    print(
      'XiaozhiProvisioning: HTTP ${response.statusCode} finalUrl=$finalUrl',
    );
    print('XiaozhiProvisioning: raw=$bodyText');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('OTA HTTP ${response.statusCode}: $bodyText');
    }

    final dynamic decodedDynamic;
    try {
      decodedDynamic = jsonDecode(bodyText);
    } catch (_) {
      throw Exception('Phản hồi OTA không phải JSON hợp lệ: $bodyText');
    }

    if (decodedDynamic is! Map) {
      throw Exception('Phản hồi OTA không phải JSON object hợp lệ.');
    }
    final decoded = decodedDynamic.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );

    final websocket = _asMap(decoded['websocket']);
    final activation = _asMap(decoded['activation']);
    final mqtt = _asMap(decoded['mqtt']);

    final wsUrl = _readString(websocket, ['url', 'endpoint']);
    final token = _readString(websocket, ['token', 'access_token']);
    final activationCode = _readString(
      activation,
      ['code', 'activation_code', 'verification_code'],
    );
    final activationMessage = _readString(
      activation,
      ['message', 'text', 'instruction'],
    );
    final activationChallenge = _readString(activation, ['challenge']);
    final activationTimeoutMs = _readInt(activation, ['timeout_ms']);

    final mqttClientId = _readString(mqtt, ['client_id']) ?? '';
    final mqttUsername = _readString(mqtt, ['username']) ?? '';
    final isTest = token == 'test-token' ||
        mqttClientId.contains('GID_test') ||
        mqttUsername.toLowerCase().contains('test');
    final isHealth = decoded['status']?.toString() == 'ok' &&
        decoded['message']
                ?.toString()
                .toLowerCase()
                .contains('server is working') ==
            true &&
        websocket.isEmpty &&
        activation.isEmpty;

    return XiaozhiProvisioningResult(
      deviceId: deviceId,
      clientId: clientId,
      otaUrl: otaUrl,
      requestProfile: requestProfile,
      websocketUrl: wsUrl,
      token: token,
      activationCode: activationCode,
      activationMessage: activationMessage,
      activationChallenge: activationChallenge,
      activationTimeoutMs: activationTimeoutMs,
      isTestCredential: isTest,
      isHealthResponse: isHealth,
      httpStatus: response.statusCode,
      finalUrl: finalUrl,
      raw: decoded,
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return <String, dynamic>{};
  }

  static String? _readString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return null;
  }

  static int? _readInt(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }
}
