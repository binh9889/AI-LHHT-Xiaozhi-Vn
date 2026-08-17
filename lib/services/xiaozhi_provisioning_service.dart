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
/// The official ESP32 firmware uses a JSON POST request to the OTA URL and
/// expects device metadata, activation version, and optional serial number.
/// This implementation mirrors that protocol while keeping Android-compatible
/// field names when the ESP32-specific fields do not exist on mobile.
class XiaozhiProvisioningService {
  static const String TAG = 'XiaozhiProvisioning';
  static const String officialOtaUrl =
      'https://api.tenclass.net/xiaozhi/ota/';

  static Future<XiaozhiProvisioningResult> provision({
    String otaUrl = officialOtaUrl,
  }) async {
    final deviceId = await DeviceUtil.getStableMacAddress();
    final clientId = await DeviceUtil.getStableClientId();
    final model = await DeviceUtil.getDeviceModel();
    final os = await DeviceUtil.getOsVersion();
    final serialNumber = _stableSerialNumber(deviceId, clientId);
    final requestBody = _buildSystemInfoPayload(
      deviceId: deviceId,
      clientId: clientId,
      model: model,
      osVersion: os,
      language: 'vi-VN',
      version: '2.1.0',
    );
    final requestJson = jsonEncode(requestBody);
    final userAgent = 'xiaozhi-android-client/2.1.0 ($model; $os)';
    final headers = <String, String>{
      'Accept': 'application/json',
      'Accept-Language': 'vi-VN,vi;q=0.9,en;q=0.8',
      'User-Agent': userAgent,
      'Device-Id': deviceId,
      'Client-Id': clientId,
      'Activation-Version': '2',
      'Serial-Number': serialNumber,
      'Content-Type': 'application/json',
    };

    final uri = Uri.parse(otaUrl);

    print('$TAG: method=POST');
    print('$TAG: url=$uri');
    print('$TAG: headers={Accept: application/json, Accept-Language: vi-VN,vi;q=0.9,en;q=0.8, User-Agent: $userAgent, Device-Id: $deviceId, Client-Id: $clientId, Activation-Version: 2, Serial-Number: $serialNumber, Content-Type: application/json}');
    print('$TAG: body=$requestJson');

    final response = await http
        .post(
          uri,
          headers: headers,
          body: requestJson,
        )
        .timeout(const Duration(seconds: 20));

    final finalUrl = response.request?.url.toString() ?? uri.toString();
    print('$TAG: status=${response.statusCode}');
    print('$TAG: final_url=$finalUrl');
    print('$TAG: response_headers=${response.headers}');
    print('$TAG: raw_response=${response.body}');

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
    final mqtt = _asMap(decoded['mqtt']);
    final firmware = _asMap(decoded['firmware']);

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
    final mqttClientId = _readString(mqtt, ['client_id']) ?? '';
    final firmwareVersion = _readString(firmware, ['version']) ??
        _readString(decoded, ['firmware_version', 'version']) ??
        '';
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

  /// Stable serial fallback used when the device has no official hardware serial.
  /// This is derived from the device/client identity and kept deterministic across
  /// app restarts so that a service can recognize the same Android device without
  /// generating a new random serial each run.
  static String _stableSerialNumber(String deviceId, String clientId) {
    final seed = '$deviceId:$clientId';
    final digest = sha256.convert(utf8.encode(seed));
    return digest.toString().substring(0, 32).toLowerCase();
  }

  static Map<String, dynamic> _buildSystemInfoPayload({
    required String deviceId,
    required String clientId,
    required String model,
    required String osVersion,
    required String language,
    required String version,
  }) {
    return <String, dynamic>{
      'version': version,
      'language': language,
      'mac_address': deviceId,
      'device_id': deviceId,
      'uuid': clientId,
      'client_id': clientId,
      'platform': 'android',
      'os_version': osVersion,
      'device_model': model,
    };
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
