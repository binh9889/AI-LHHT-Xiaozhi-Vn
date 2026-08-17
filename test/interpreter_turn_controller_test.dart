import 'package:ai_assistant/utils/interpreter_turn_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phiên dịch Việt Trung khóa locale và tự đổi lượt', () {
    final turn = InterpreterTurnController(
      languageA: 'Tiếng Việt',
      localeA: 'vi-VN',
      languageB: '中文',
      localeB: 'zh-CN',
    );

    expect(turn.sourceLanguage, 'Tiếng Việt');
    expect(turn.sourceLocale, 'vi-VN');
    expect(turn.targetLanguage, '中文');
    expect(turn.targetLocale, 'zh-CN');

    turn.nextTurn();
    expect(turn.sourceLanguage, '中文');
    expect(turn.sourceLocale, 'zh-CN');
    expect(turn.targetLanguage, 'Tiếng Việt');
    expect(turn.targetLocale, 'vi-VN');

    turn.nextTurn();
    expect(turn.sourceLocale, 'vi-VN');
  });
}
