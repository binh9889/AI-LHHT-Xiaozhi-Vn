import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/services/xiaozhi_websocket_manager.dart';

void main() {
  test('connected is emitted only after valid Xiaozhi server hello', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    String? deviceHeader;
    String? clientHeader;
    String? authHeader;

    server.listen((request) async {
      deviceHeader = request.headers.value('device-id');
      clientHeader = request.headers.value('client-id');
      authHeader = request.headers.value('authorization');
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((data) {
        if (data is String) {
          final json = jsonDecode(data);
          if (json is Map && json['type'] == 'hello') {
            socket.add(jsonEncode({
              'type': 'hello',
              'transport': 'websocket',
              'session_id': 'test-session',
              'audio_params': {'format': 'opus', 'sample_rate': 16000},
            }));
          }
        }
      });
    });

    final manager = XiaozhiWebSocketManager(
      deviceId: '02:11:22:33:44:55',
      clientId: 'client-123',
      enableToken: true,
    );
    addTearDown(manager.disconnect);

    var connectedEvents = 0;
    manager.addListener((event) {
      if (event.type == XiaozhiEventType.connected) connectedEvents++;
    });

    await manager.connect(
      'ws://127.0.0.1:${server.port}/xiaozhi/v1/',
      'token-123',
    );

    expect(manager.isConnected, isTrue);
    expect(connectedEvents, 1);
    expect(deviceHeader, '02:11:22:33:44:55');
    expect(clientHeader, 'client-123');
    expect(authHeader, 'Bearer token-123');
  });
}
