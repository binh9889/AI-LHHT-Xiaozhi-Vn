/// Điều khiển lượt nói cho phiên dịch hai chiều.
///
/// Không đoán ngôn ngữ từ transcript. A nói -> nhận ASR bằng locale A -> dịch
/// sang B -> đổi lượt. Sau đó B nói -> ASR locale B -> dịch sang A.
class InterpreterTurnController {
  InterpreterTurnController({
    required this.languageA,
    required this.localeA,
    required this.languageB,
    required this.localeB,
  });

  String languageA;
  String localeA;
  String languageB;
  String localeB;
  bool _turnA = true;

  bool get isTurnA => _turnA;
  String get sourceLanguage => _turnA ? languageA : languageB;
  String get sourceLocale => _turnA ? localeA : localeB;
  String get targetLanguage => _turnA ? languageB : languageA;
  String get targetLocale => _turnA ? localeB : localeA;

  void nextTurn() => _turnA = !_turnA;
  void swapTurn() => _turnA = !_turnA;
  void resetToA() => _turnA = true;

  void updatePair({
    required String newLanguageA,
    required String newLocaleA,
    required String newLanguageB,
    required String newLocaleB,
  }) {
    languageA = newLanguageA;
    localeA = newLocaleA;
    languageB = newLanguageB;
    localeB = newLocaleB;
    _turnA = true;
  }
}
