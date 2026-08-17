import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:ai_assistant/models/xiaozhi_config.dart';
import 'package:ai_assistant/models/dify_config.dart';
import 'package:ai_assistant/models/minimax_config.dart';
import 'package:ai_assistant/utils/device_util.dart';

class ConfigProvider extends ChangeNotifier {
  List<XiaozhiConfig> _xiaozhiConfigs = [];
  List<DifyConfig> _difyConfigs = [];
  List<MiniMaxConfig> _minimaxConfigs = [];
  bool _isLoaded = false;

  List<XiaozhiConfig> get xiaozhiConfigs => _xiaozhiConfigs;
  List<DifyConfig> get difyConfigs => _difyConfigs;
  List<MiniMaxConfig> get minimaxConfigs => _minimaxConfigs;
  DifyConfig? get difyConfig =>
      _difyConfigs.isNotEmpty ? _difyConfigs.first : null;
  bool get isLoaded => _isLoaded;

  ConfigProvider() {
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Xiaozhi configs
    final xiaozhiConfigsJson = prefs.getStringList('xiaozhiConfigs') ?? [];
    _xiaozhiConfigs =
        xiaozhiConfigsJson
            .map((json) => XiaozhiConfig.fromJson(jsonDecode(json)))
            .toList();

    // Migrate v2.1.x Xiaozhi configs that did not persist Client-Id.
    if (_xiaozhiConfigs.any((config) => config.clientId.trim().isEmpty)) {
      final stableClientId = await DeviceUtil.getStableClientId();
      _xiaozhiConfigs = _xiaozhiConfigs
          .map(
            (config) => config.clientId.trim().isEmpty
                ? config.copyWith(clientId: stableClientId)
                : config,
          )
          .toList();
      await prefs.setStringList(
        'xiaozhiConfigs',
        _xiaozhiConfigs.map((config) => jsonEncode(config.toJson())).toList(),
      );
    }

    // 加载多个Cấu hình Dify
    final difyConfigsJson = prefs.getStringList('difyConfigs') ?? [];
    _difyConfigs =
        difyConfigsJson
            .map((json) => DifyConfig.fromJson(jsonDecode(json)))
            .toList();

    // Load MiniMax configs
    final minimaxConfigsJson = prefs.getStringList('minimaxConfigs') ?? [];
    _minimaxConfigs =
        minimaxConfigsJson
            .map((json) => MiniMaxConfig.fromJson(jsonDecode(json)))
            .toList();

    // 向后兼容：加载旧版单个Cấu hình Dify
    final oldDifyConfigJson = prefs.getString('difyConfig');
    if (oldDifyConfigJson != null && _difyConfigs.isEmpty) {
      final oldConfig = DifyConfig.fromJson(jsonDecode(oldDifyConfigJson));
      // ThêmID和名称，转换为新格式
      final updatedConfig = DifyConfig(
        id: const Uuid().v4(),
        name: "Dify mặc định",
        apiUrl: oldConfig.apiUrl,
        apiKey: oldConfig.apiKey,
      );
      _difyConfigs.add(updatedConfig);

      // Lưu为新格式并Xóa旧数据
      await _saveConfigs();
      await prefs.remove('difyConfig');
    }

    _isLoaded = true;
    notifyListeners();
  }

  Future<void> _saveConfigs() async {
    final prefs = await SharedPreferences.getInstance();

    // Save Xiaozhi configs
    final xiaozhiConfigsJson =
        _xiaozhiConfigs.map((config) => jsonEncode(config.toJson())).toList();
    await prefs.setStringList('xiaozhiConfigs', xiaozhiConfigsJson);

    // Lưu多个Cấu hình Dify
    final difyConfigsJson =
        _difyConfigs.map((config) => jsonEncode(config.toJson())).toList();
    await prefs.setStringList('difyConfigs', difyConfigsJson);

    // Save MiniMax configs
    final minimaxConfigsJson =
        _minimaxConfigs.map((config) => jsonEncode(config.toJson())).toList();
    await prefs.setStringList('minimaxConfigs', minimaxConfigsJson);
  }

  Future<void> addXiaozhiConfig(
    String name,
    String websocketUrl, {
    String? customMacAddress,
    String? customToken,
  }) async {
    final macAddress = customMacAddress ?? await DeviceUtil.getStableMacAddress();
    final clientId = await DeviceUtil.getStableClientId();

    final newConfig = XiaozhiConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      websocketUrl: websocketUrl,
      macAddress: macAddress,
      clientId: clientId,
      token: (customToken != null && customToken.trim().isNotEmpty)
          ? customToken.trim()
          : '',
    );

    _xiaozhiConfigs.add(newConfig);
    await _saveConfigs();
    notifyListeners();
  }

  Future<void> addXiaozhiConfigWithToken({
    required String name,
    required String websocketUrl,
    required String macAddress,
    required String clientId,
    required String token,
  }) async {
    final existingIndex = _xiaozhiConfigs.indexWhere(
      (c) => c.name == name || c.macAddress == macAddress,
    );
    final config = XiaozhiConfig(
      id: existingIndex >= 0
          ? _xiaozhiConfigs[existingIndex].id
          : DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      websocketUrl: websocketUrl,
      macAddress: macAddress,
      clientId: clientId,
      token: token,
    );
    if (existingIndex >= 0) {
      _xiaozhiConfigs[existingIndex] = config;
    } else {
      _xiaozhiConfigs.add(config);
    }
    await _saveConfigs();
    notifyListeners();
  }

  Future<void> updateXiaozhiConfig(XiaozhiConfig updatedConfig) async {
    final index = _xiaozhiConfigs.indexWhere(
      (config) => config.id == updatedConfig.id,
    );
    if (index != -1) {
      _xiaozhiConfigs[index] = updatedConfig;
      await _saveConfigs();
      notifyListeners();
    }
  }

  Future<void> deleteXiaozhiConfig(String id) async {
    _xiaozhiConfigs.removeWhere((config) => config.id == id);
    await _saveConfigs();
    notifyListeners();
  }

  // Thêm cấu hình Dify
  Future<void> addDifyConfig(String name, String apiKey, String apiUrl) async {
    final newConfig = DifyConfig(
      id: const Uuid().v4(),
      name: name,
      apiUrl: apiUrl,
      apiKey: apiKey,
    );

    _difyConfigs.add(newConfig);
    await _saveConfigs();
    notifyListeners();
  }

  // 更新Cấu hình Dify
  Future<void> updateDifyConfig(DifyConfig updatedConfig) async {
    final index = _difyConfigs.indexWhere(
      (config) => config.id == updatedConfig.id,
    );
    if (index != -1) {
      _difyConfigs[index] = updatedConfig;
      await _saveConfigs();
      notifyListeners();
    }
  }

  // Xóa cấu hình Dify
  Future<void> deleteDifyConfig(String id) async {
    _difyConfigs.removeWhere((config) => config.id == id);
    await _saveConfigs();
    notifyListeners();
  }

  // Thêm cấu hình MiniMax
  Future<void> addMiniMaxConfig(
    String name,
    String apiKey, {
    String model = 'MiniMax-M2.7',
  }) async {
    final newConfig = MiniMaxConfig(
      id: const Uuid().v4(),
      name: name,
      apiKey: apiKey,
      model: model,
    );

    _minimaxConfigs.add(newConfig);
    await _saveConfigs();
    notifyListeners();
  }

  // 更新MiniMaxcấu hình
  Future<void> updateMiniMaxConfig(MiniMaxConfig updatedConfig) async {
    final index = _minimaxConfigs.indexWhere(
      (config) => config.id == updatedConfig.id,
    );
    if (index != -1) {
      _minimaxConfigs[index] = updatedConfig;
      await _saveConfigs();
      notifyListeners();
    }
  }

  // Xóa cấu hình MiniMax
  Future<void> deleteMiniMaxConfig(String id) async {
    _minimaxConfigs.removeWhere((config) => config.id == id);
    await _saveConfigs();
    notifyListeners();
  }

  // 向后兼容的旧方法，Cài đặt第一个Cấu hình Dify
  Future<void> setDifyConfig(String apiKey, String apiUrl) async {
    if (_difyConfigs.isEmpty) {
      await addDifyConfig("Dify mặc định", apiKey, apiUrl);
    } else {
      final updated = _difyConfigs.first.copyWith(
        apiKey: apiKey,
        apiUrl: apiUrl,
      );
      await updateDifyConfig(updated);
    }
  }

  // 简化版的设备ID获取方法，不依赖上下文
  Future<String> _getSimpleDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    String deviceId = '';

    try {
      // 简单地尝试获取Android或iOS设备ID，不依赖平台判断
      try {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } catch (_) {
        try {
          final iosInfo = await deviceInfo.iosInfo;
          deviceId = iosInfo.identifierForVendor ?? '';
        } catch (_) {
          final webInfo = await deviceInfo.webBrowserInfo;
          deviceId = webInfo.userAgent ?? '';
        }
      }
    } catch (e) {
      // 出现任何Lỗi，使用时间戳
      deviceId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    // 如果ID为空，使用时间戳
    if (deviceId.isEmpty) {
      deviceId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    return deviceId;
  }

  String _generateMacFromDeviceId(String deviceId) {
    final bytes = utf8.encode(deviceId);
    final digest = md5.convert(bytes);
    final hash = digest.toString();

    // Format as MAC address (XX:XX:XX:XX:XX:XX)
    final List<String> macParts = [];
    for (int i = 0; i < 6; i++) {
      macParts.add(hash.substring(i * 2, i * 2 + 2));
    }

    return macParts.join(':');
  }

  // 获取设备Địa chỉ MAC
  Future<String> _getDeviceMacAddress() async {
    final deviceId = await _getSimpleDeviceId();

    // 如果设备ID本身就是Địa chỉ MAC格式，直接使用
    if (_isMacAddress(deviceId)) {
      return deviceId;
    }

    // 否则生成一个Địa chỉ MAC
    return _generateMacFromDeviceId(deviceId);
  }

  // 检查字符串是否是Địa chỉ MAC格式
  bool _isMacAddress(String str) {
    final macRegex = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');
    return macRegex.hasMatch(str);
  }
}
