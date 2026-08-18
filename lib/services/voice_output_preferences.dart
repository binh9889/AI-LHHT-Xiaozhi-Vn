import 'package:shared_preferences/shared_preferences.dart';

/// Cấu hình đầu ra giọng nói v4.1.3.
///
/// Mặc định LUÔN ưu tiên audio TTS do Xiaozhi cloud gửi về. Đây chính là
/// giọng đã chọn cho Agent trên xiaozhi.me (ví dụ "Giọng nữ / Female Voice").
/// TTS Android chỉ còn là fallback cho phiên dịch hoặc khi người dùng chủ động
/// bật chế độ local; nó không được phép âm thầm thay giọng của Agent.
class VoiceOutputPreferences {
  static const String _nativeXiaozhiKey = 'voice_output_xiaozhi_native_v412';
  static const String _unifiedVoiceKey = 'voice_output_unified_local_v41';
  static const String _preferredVoicePrefix = 'voice_output_preferred_voice_';

  Future<bool> useXiaozhiNativeVoice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_nativeXiaozhiKey) ?? true;
  }

  Future<void> setUseXiaozhiNativeVoice(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_nativeXiaozhiKey, value);
  }

  Future<bool> useUnifiedVoice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_unifiedVoiceKey) ?? false;
  }

  Future<void> setUseUnifiedVoice(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_unifiedVoiceKey, value);
  }

  Future<String?> preferredVoiceFor(String locale) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_preferredVoicePrefix${_languageKey(locale)}');
  }

  Future<void> setPreferredVoiceFor(String locale, String voiceName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_preferredVoicePrefix${_languageKey(locale)}',
      voiceName,
    );
  }

  String _languageKey(String locale) {
    return locale.toLowerCase().split(RegExp('[-_]')).first;
  }
}
