import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:web_socket_channel/web_socket_channel.dart';

enum XiaozhiEventType { connected, disconnected, message, error, binaryMessage }

class XiaozhiEvent {
  final XiaozhiEventType type;
  final dynamic data;

  XiaozhiEvent({required this.type, this.data});
}

typedef XiaozhiWebSocketListener = void Function(XiaozhiEvent event);

/// WebSocket manager bám sát protocol v1 của Xiaozhi:
/// - Header auth nằm trong HTTP WebSocket handshake.
/// - Sau khi transport mở, client gửi `hello`.
/// - CHỈ coi là connected khi server trả `hello` hợp lệ.
///
/// Bản cũ đánh dấu connected ngay sau khi tạo channel nên UI có thể báo kết nối
/// dù server chưa xác nhận protocol. Bản này loại bỏ false-positive đó.
class XiaozhiWebSocketManager {
  static const String TAG = 'XiaozhiWebSocket';
  static const int RECONNECT_DELAY = 3000;
  static const Duration HELLO_TIMEOUT = Duration(seconds: 10);

  WebSocketChannel? _channel;
  String? _serverUrl;
  String? _deviceId;
  String? _clientId;
  String? _token;
  final bool _enableToken;

  final List<XiaozhiWebSocketListener> _listeners = [];
  bool _isReconnecting = false;
  bool _protocolReady = false;
  bool _manualDisconnect = false;
  Timer? _reconnectTimer;
  StreamSubscription? _streamSubscription;
  Completer<void>? _helloCompleter;

  XiaozhiWebSocketManager({
    required String deviceId,
    required String clientId,
    bool enableToken = false,
  })  : _deviceId = deviceId,
        _clientId = clientId,
        _enableToken = enableToken;

  void addListener(XiaozhiWebSocketListener listener) {
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  void removeListener(XiaozhiWebSocketListener listener) {
    _listeners.remove(listener);
  }

  void _dispatchEvent(XiaozhiEvent event) {
    for (final listener in List<XiaozhiWebSocketListener>.from(_listeners)) {
      listener(event);
    }
  }

  Future<void> connect(String url, String token) async {
    if (url.trim().isEmpty) {
      throw Exception('Địa chỉ WebSocket đang trống.');
    }

    _serverUrl = url.trim();
    _token = token.trim();
    _manualDisconnect = false;
    _protocolReady = false;

    if (_channel != null) {
      await _closeChannel(dispatchDisconnected: false);
    }

    final uri = Uri.parse(_serverUrl!);
    final headers = <String, dynamic>{
      'Device-Id': _deviceId ?? '',
      'Client-Id': _clientId ?? '',
      'Protocol-Version': '1',
    };
    if (_enableToken && _token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${_token!}';
    }

    print('$TAG: connecting=$uri');
    print('$TAG: Device-Id=$_deviceId');
    print('$TAG: Client-Id=$_clientId');
    print('$TAG: Authorization=${_enableToken && _token!.isNotEmpty ? 'enabled' : 'disabled'}');

    try {
      // Android/iOS/Desktop path. Official cloud requires handshake headers;
      // sending header text AFTER opening a socket is not equivalent and has
      // therefore been removed.
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: headers,
        pingInterval: const Duration(seconds: 20),
        connectTimeout: const Duration(seconds: 10),
      );

      _helloCompleter = Completer<void>();
      _streamSubscription = _channel!.stream.listen(
        _onMessage,
        onDone: _onDisconnected,
        onError: _onError,
        cancelOnError: false,
      );

      // web_socket_channel >=2.3 exposes `ready`; wait for the HTTP upgrade
      // instead of guessing with an arbitrary delay.
      await _channel!.ready;
      _sendHelloMessage();

      await _helloCompleter!.future.timeout(
        HELLO_TIMEOUT,
        onTimeout: () {
          throw TimeoutException(
            'WebSocket đã mở nhưng Xiaozhi không trả hello trong 10 giây.',
          );
        },
      );

      _protocolReady = true;
      _dispatchEvent(XiaozhiEvent(type: XiaozhiEventType.connected));
      print('$TAG: protocol ready');
    } catch (e) {
      _protocolReady = false;
      await _closeChannel(dispatchDisconnected: false);
      final message = 'Kết nối Xiaozhi thất bại: $e';
      _dispatchEvent(XiaozhiEvent(type: XiaozhiEventType.error, data: message));
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _isReconnecting = false;
    await _closeChannel(dispatchDisconnected: true);
  }

  Future<void> _closeChannel({required bool dispatchDisconnected}) async {
    _protocolReady = false;
    if (_helloCompleter != null && !_helloCompleter!.isCompleted) {
      _helloCompleter!.completeError(
        StateError('Kênh WebSocket đóng trước khi server hello.'),
      );
    }
    _helloCompleter = null;

    await _streamSubscription?.cancel();
    _streamSubscription = null;

    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        await channel.sink.close(status.normalClosure);
      } catch (_) {}
    }

    if (dispatchDisconnected) {
      _dispatchEvent(XiaozhiEvent(type: XiaozhiEventType.disconnected));
    }
  }

  void _sendHelloMessage() {
    final hello = {
      'type': 'hello',
      'version': 1,
      'features': {'mcp': true},
      'transport': 'websocket',
      'audio_params': {
        'format': 'opus',
        'sample_rate': 16000,
        'channels': 1,
        'frame_duration': 60,
      },
    };
    _sendRaw(jsonEncode(hello));
  }

  void _sendRaw(dynamic message) {
    final channel = _channel;
    if (channel == null) {
      throw StateError('WebSocket transport chưa được tạo.');
    }
    channel.sink.add(message);
  }

  void sendMessage(String message) {
    if (!isConnected) {
      print('$TAG: send blocked - protocol not ready');
      return;
    }
    _sendRaw(message);
  }

  void sendBinaryMessage(List<int> data) {
    if (!isConnected) {
      print('$TAG: binary send blocked - protocol not ready');
      return;
    }
    try {
      _sendRaw(data);
    } catch (e) {
      _dispatchEvent(
        XiaozhiEvent(type: XiaozhiEventType.error, data: 'Không gửi được audio: $e'),
      );
    }
  }

  void sendTextRequest(String text) {
    if (!isConnected) return;
    final jsonMessage = {
      'type': 'listen',
      'state': 'detect',
      'text': text,
      'source': 'text',
    };
    sendMessage(jsonEncode(jsonMessage));
  }

  void _onMessage(dynamic message) {
    if (message is String) {
      try {
        final decoded = jsonDecode(message);
        if (decoded is Map &&
            decoded['type'] == 'hello' &&
            decoded['transport'] == 'websocket') {
          if (_helloCompleter != null && !_helloCompleter!.isCompleted) {
            _helloCompleter!.complete();
          }
        }
      } catch (_) {
        // Non-JSON text is still forwarded to the service for diagnostics.
      }

      _dispatchEvent(
        XiaozhiEvent(type: XiaozhiEventType.message, data: message),
      );
    } else if (message is List<int>) {
      _dispatchEvent(
        XiaozhiEvent(type: XiaozhiEventType.binaryMessage, data: message),
      );
    }
  }

  void _onDisconnected() {
    final wasReady = _protocolReady;
    _protocolReady = false;
    if (_helloCompleter != null && !_helloCompleter!.isCompleted) {
      _helloCompleter!.completeError(
        StateError('Server đóng kết nối trước khi hoàn tất hello.'),
      );
    }

    _dispatchEvent(XiaozhiEvent(type: XiaozhiEventType.disconnected));

    if (!_manualDisconnect &&
        wasReady &&
        !_isReconnecting &&
        _serverUrl != null &&
        _token != null) {
      _isReconnecting = true;
      _reconnectTimer = Timer(
        const Duration(milliseconds: RECONNECT_DELAY),
        () async {
          _isReconnecting = false;
          if (_manualDisconnect || _serverUrl == null || _token == null) return;
          try {
            await connect(_serverUrl!, _token!);
          } catch (_) {
            // Connection owner may schedule a longer backoff.
          }
        },
      );
    }
  }

  void _onError(Object error) {
    if (_helloCompleter != null && !_helloCompleter!.isCompleted) {
      _helloCompleter!.completeError(error);
    }
    _protocolReady = false;
    _dispatchEvent(
      XiaozhiEvent(type: XiaozhiEventType.error, data: error.toString()),
    );
  }

  bool get isConnected => _protocolReady && _channel != null;
}
