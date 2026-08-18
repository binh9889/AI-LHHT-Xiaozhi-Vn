import 'package:shared_preferences/shared_preferences.dart';

/// Cấu hình đầu ra giọng nói v4.1.
///
/// Mặc định dùng một TTS hệ thống ổn định cho cả Agent, Tool và Interpreter
/// để tránh tình trạng mỗi loại câu trả lời dùng một giọng khác nhau.
class VoiceOutputPreferences {
  static const String _unifiedVoiceKey = 'voice_output_unified_local_v41';
  static const String _preferredVoicePrefix = 'voice_output_preferred_voice_';

  Future<bool> useUnifiedVoice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_unifiedVoiceKey) ?? true;
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
