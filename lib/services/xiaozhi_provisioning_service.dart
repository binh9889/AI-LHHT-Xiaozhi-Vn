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
  final bool isTestCredential;
  final Map<String, dynamic> raw;

  const XiaozhiProvisioningResult({
    required this.deviceId,
    required this.clientId,
    required this.otaUrl,
    required this.websocketUrl,
    required this.token,
    required this.activationCode,
    required this.activationMessage,
    required this.isTestCredential,
    required this.raw,
  });

  bool get hasActivationCode =>
      activationCode != null && activationCode!.trim().isNotEmpty;

  bool get canConnect =>
      websocketUrl != null && websocketUrl!.trim().isNotEmpty &&
      token != null && token!.trim().isNotEmpty;
}

/// Provisioning layer for Xiaozhi-compatible OTA endpoints.
///
/// The official ESP32 firmware obtains the communication server and, for new
/// devices, an activation code from the OTA step before opening WebSocket.
/// The public server may deliberately return test credentials for unsupported
/// device identities; the app exposes that state instead of pretending the
/// phone is already bound to an agent.
class XiaozhiProvisioningService {
  static const String officialOtaUrl =
      'https://api.tenclass.net/xiaozhi/ota/';

  static Future<XiaozhiProvisioningResult> provision({
    String otaUrl = officialOtaUrl,
  }) async {
    final deviceId = await DeviceUtil.getStableMacAddress();
    final clientId = await DeviceUtil.getStableClientId();
    final model = await DeviceUtil.getDeviceModel();
    final os = await DeviceUtil.getOsVersion();

    final uri = Uri.parse(otaUrl);
    final response = await http
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            'Accept-Language': 'vi-VN,vi;q=0.9,en;q=0.8',
            'User-Agent': 'xiaozhi-android-client/2.1.0 ($model; $os)',
            'Device-Id': deviceId,
            'Client-Id': clientId,
          },
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'OTA HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Phản hồi OTA không phải JSON object hợp lệ.');
    }

    final websocket = _asMap(decoded['websocket']);
    final activation = _asMap(decoded['activation']);

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

    final mqtt = _asMap(decoded['mqtt']);
    final mqttClientId = _readString(mqtt, ['client_id']) ?? '';
    final isTest = token == 'test-token' || mqttClientId.contains('GID_test');

    return XiaozhiProvisioningResult(
      deviceId: deviceId,
      clientId: clientId,
      otaUrl: otaUrl,
      websocketUrl: wsUrl,
      token: token,
      activationCode: activationCode,
      activationMessage: activationMessage,
      isTestCredential: isTest,
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
}
