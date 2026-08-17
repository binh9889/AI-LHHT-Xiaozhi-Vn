import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/tools/tool_registry.dart';

void main() {
  test('v4 registry has exactly 21 unique tools', () {
    expect(ToolRegistry.all.length, 21);
    expect(ToolRegistry.all.map((e) => e.id).toSet().length, 21);
  });
}
