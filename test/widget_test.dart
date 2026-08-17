import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/widgets/discovery_screen.dart';

void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DiscoveryScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Discovery UI fits 360x640 without overflow', (tester) async {
    await pumpAt(tester, const Size(360, 640));
    expect(find.text('Phiên dịch AI'), findsOneWidget);
    expect(find.text('Chẩn đoán Voice'), findsOneWidget);
  });

  testWidgets('Discovery UI fits 412x915 without overflow', (tester) async {
    await pumpAt(tester, const Size(412, 915));
    expect(find.text('Khám phá'), findsOneWidget);
    expect(find.text('Tool / MCP'), findsOneWidget);
  });
}
