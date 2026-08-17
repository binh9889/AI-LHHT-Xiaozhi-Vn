import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/device_util.dart';

class XiaozhiProvisioningResult {
  final String deviceId;
  final String clientId;
  final String otaUrl;
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

  bool get canConnect =>
      websocketUrl != null &&
      websocketUrl!.trim().isNotEmpty &&
      token != null &&
      token!.trim().isNotEmpty;
}

/// Xiaozhi official OTA/provisioning client for a phone-class device.
///
/// Important protocol choice:
/// - Official ESP32 firmware sends Activation-Version=2 ONLY when it owns a
///   factory serial number backed by the ESP32 HMAC/eFuse key.
/// - A normal Android phone does not have that Xiaozhi factory HMAC identity.
/// - Therefore this client deliberately uses Activation-Version=1 and DOES NOT
///   invent a Serial-Number or HMAC key. This is the closest legitimate match
///   to the official firmware's non-serial-number activation path.
class XiaozhiProvisioningService {
  static const String officialOtaUrl =
      'https://api.tenclass.net/xiaozhi/ota/';
  static const String appVersion = '2.2.0';

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
      'Accept-Language': 'vi-VN',
      'User-Agent': 'xiaozhi-android-client/$appVersion ($model; $os)',
      'Activation-Version': '1',
      'Device-Id': deviceId,
      'Client-Id': clientId,
      'Content-Type': 'application/json',
    };

    // Mirrors the structure of Board::GetSystemInfoJson() where it makes sense
    // on Android. ESP-only values are represented conservatively rather than
    // fabricated as real flash/heap/eFuse values.
    final payload = <String, dynamic>{
      'version': 2,
      'language': 'vi-VN',
      'flash_size': 0,
      'minimum_free_heap_size': '0',
      'mac_address': deviceId,
      'uuid': clientId,
      'chip_model_name': 'android',
      'chip_info': <String, dynamic>{
        'model': 0,
        'cores': 0,
        'revision': 0,
        'features': 0,
      },
      'application': <String, dynamic>{
        'name': 'ai_assistant',
        'version': appVersion,
        'compile_time': DateTime.now().toUtc().toIso8601String(),
        'idf_version': 'android',
        'elf_sha256': '',
      },
      'partition_table': <dynamic>[],
      'ota': <String, dynamic>{'label': 'android'},
      'display': <String, dynamic>{
        'monochrome': false,
        'width': 0,
        'height': 0,
      },
      'board': <String, dynamic>{
        'type': 'android',
        'device_model': model,
        'os_version': os,
      },
    };

    // Keep logs useful without exposing access tokens.
    print('XiaozhiProvisioning: POST $uri');
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
    final isTest = token == 'test-token' || mqttClientId.contains('GID_test');
    final isHealth = decoded['status']?.toString() == 'ok' &&
        decoded['message']?.toString().toLowerCase().contains('server is working') ==
            true &&
        websocket.isEmpty &&
        activation.isEmpty;

    return XiaozhiProvisioningResult(
      deviceId: deviceId,
      clientId: clientId,
      otaUrl: otaUrl,
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
