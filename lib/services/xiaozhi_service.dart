import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sound/flutter_sound.dart';
import '../services/xiaozhi_websocket_manager.dart';
import '../utils/device_util.dart';
import '../utils/audio_util.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Dịch vụ Xiaozhi事件类型
enum XiaozhiServiceEventType {
  connected,
  disconnected,
  textMessage,
  audioData,
  error,
  voiceCallStart,
  voiceCallEnd,
  userMessage,
}

/// Dịch vụ Xiaozhi事件
class XiaozhiServiceEvent {
  final XiaozhiServiceEventType type;
  final dynamic data;

  XiaozhiServiceEvent(this.type, this.data);
}

/// Dịch vụ Xiaozhi监听器
typedef XiaozhiServiceListener = void Function(XiaozhiServiceEvent event);

/// Tin nhắn监听器
typedef MessageListener = void Function(dynamic message);

/// Dịch vụ Xiaozhi
class XiaozhiService {
  static const String TAG = "XiaozhiService";
  static const String DEFAULT_SERVER = "wss://ws.xiaozhi.ai";

  final String websocketUrl;
  final String macAddress;
  final String clientId;
  final String token;
  String? _sessionId; // Cuộc trò chuyệnID将由服务器提供

  XiaozhiWebSocketManager? _webSocketManager;
  bool _isConnected = false;
  bool _isMuted = false;
  final List<XiaozhiServiceListener> _listeners = [];
  StreamSubscription? _audioStreamSubscription;
  bool _isVoiceCallActive = false;
  WebSocketChannel? _ws;
  bool _hasStartedCall = false;
  MessageListener? _messageListener;

  /// Tạo một service riêng cho mỗi cấu hình/cuộc trò chuyện.
  /// Tránh giữ singleton cũ làm app tiếp tục dùng token hoặc Agent trước đó.
  XiaozhiService({
    required this.websocketUrl,
    required this.macAddress,
    required this.clientId,
    required this.token,
    String? sessionId,
  }) {
    _sessionId = sessionId;
    _init();
  }

  /// 切换到Giọng nói通话Chế độ
  Future<void> switchToVoiceCallMode() async {
    // 如果已经在Giọng nói通话Chế độ，直接返回
    if (_isVoiceCallActive) return;

    try {
      print('$TAG: 正在切换到Giọng nói通话Chế độ');

      // 简化初始化流程，确保干净状态
      await AudioUtil.stopPlaying();
      await AudioUtil.initRecorder();
      await AudioUtil.initPlayer();

      _isVoiceCallActive = true;
      print('$TAG: 已切换到Giọng nói通话Chế độ');
    } catch (e) {
      print('$TAG: 切换到Giọng nói通话Chế độThất bại: $e');
      rethrow;
    }
  }

  /// 切换到普通聊天Chế độ
  Future<void> switchToChatMode() async {
    // 如果已经在普通聊天Chế độ，直接返回
    if (!_isVoiceCallActive) return;

    try {
      print('$TAG: 正在切换到普通聊天Chế độ');

      // 停止Giọng nói通话相关的活动
      await stopListeningCall();

      // 确保播放器停止
      await AudioUtil.stopPlaying();

      _isVoiceCallActive = false;
      print('$TAG: 已切换到普通聊天Chế độ');
    } catch (e) {
      print('$TAG: 切换到普通聊天Chế độThất bại: $e');
      _isVoiceCallActive = false;
    }
  }

  /// 初始化
  Future<void> _init() async {
    // 使用cấu hình中的Địa chỉ MAC作为设备ID
    print('$TAG: 初始化Hoàn tất，使用Địa chỉ MAC作为设备ID: $macAddress');

    // 初始化WebSocket管理器，启用 token
    _webSocketManager = XiaozhiWebSocketManager(
      deviceId: macAddress,
      clientId: clientId,
      enableToken: true,
    );

    // ThêmWebSocket事件监听
    _webSocketManager!.addListener(_onWebSocketEvent);

    // 初始化音频工具
    await AudioUtil.initRecorder();
    await AudioUtil.initPlayer();
  }

  /// Cài đặtTin nhắn监听器
  void setMessageListener(MessageListener listener) {
    _messageListener = listener;
  }

  /// Thêm事件监听器
  void addListener(XiaozhiServiceListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  /// 移除事件监听器
  void removeListener(XiaozhiServiceListener listener) {
    _listeners.remove(listener);
  }

  /// 分发事件到所有监听器
  void _dispatchEvent(XiaozhiServiceEvent event) {
    for (var listener in _listeners) {
      listener(event);
    }
  }

  /// 连接到Dịch vụ Xiaozhi
  Future<void> connect() async {
    if (_isConnected) return;

    try {
      print('$TAG: 开始连接服务器...');

      // 创建WebSocket管理器
      _webSocketManager = XiaozhiWebSocketManager(
        deviceId: macAddress,
        clientId: clientId,
        enableToken: true,
      );

      // ThêmWebSocket事件监听
      _webSocketManager!.addListener(_onWebSocketEvent);

      // 连接WebSocket
      await _webSocketManager!.connect(websocketUrl, token);
    } catch (e) {
      print('$TAG: 连接Thất bại: $e');
      _dispatchEvent(
        XiaozhiServiceEvent(XiaozhiServiceEventType.error, 'Kết nối dịch vụ Xiaozhi thất bại: $e'),
      );
    }
  }

  /// 断开Dịch vụ Xiaozhi连接
  Future<void> disconnect() async {
    if (!_isConnected || _webSocketManager == null) return;

    try {
      // Hủy音频流订阅
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // 停止音频录制
      if (AudioUtil.isRecording) {
        await AudioUtil.stopRecording();
      }

      // 断开WebSocket连接
      await _webSocketManager!.disconnect();
      _webSocketManager = null;
      _isConnected = false;
    } catch (e) {
      print('$TAG: 断开连接Thất bại: $e');
    }
  }

  /// 发送Văn bảnTin nhắn
  Future<String> sendTextMessage(String message) async {
    if (!_isConnected && _webSocketManager == null) {
      await connect();
    }

    try {
      // 创建一个Completer来等待响应
      final completer = Completer<String>();
      bool hasResponse = false;

      print('$TAG: 开始发送Văn bảnTin nhắn: $message');

      // ThêmTin nhắn监听器，监听所有可能的回复
      void onceListener(XiaozhiServiceEvent event) {
        if (event.type == XiaozhiServiceEventType.textMessage) {
          // 忽略echoTin nhắn（即我们发送的Tin nhắn）
          if (event.data == message) {
            print('$TAG: 忽略echoTin nhắn: ${event.data}');
            return;
          }

          print('$TAG: 收到服务器响应: ${event.data}');
          if (!completer.isCompleted) {
            hasResponse = true;
            completer.complete(event.data as String);
            removeListener(onceListener);
          }
        } else if (event.type == XiaozhiServiceEventType.error &&
            !completer.isCompleted) {
          print('$TAG: 收到Lỗi响应: ${event.data}');
          completer.completeError(event.data.toString());
          removeListener(onceListener);
        }
      }

      // 先Thêm监听器，确保不会错过任何Tin nhắn
      addListener(onceListener);

      // 发送Văn bản请求
      print('$TAG: 发送Văn bản请求: $message');
      _webSocketManager!.sendTextRequest(message);

      // Cài đặt超时，15秒比10秒更宽松一些
      final timeoutTimer = Timer(const Duration(seconds: 15), () {
        if (!completer.isCompleted) {
          print('$TAG: Yêu cầu hết thời gian chờ，15秒内没有收到响应');
          completer.completeError('Yêu cầu hết thời gian chờ');
          removeListener(onceListener);
        }
      });

      // 等待响应
      try {
        final result = await completer.future;
        // Hủy超时定时器
        timeoutTimer.cancel();
        return result;
      } catch (e) {
        // Hủy超时定时器
        timeoutTimer.cancel();
        rethrow;
      }
    } catch (e) {
      print('$TAG: 发送Tin nhắnThất bại: $e');
      rethrow;
    }
  }

  /// 连接Giọng nói通话
  Future<void> connectVoiceCall() async {
    try {
      // 简化流程，确保权限和音频准备就绪
      if (Platform.isIOS || Platform.isAndroid) {
        final status = await Permission.microphone.request();
        if (status != PermissionStatus.granted) {
          print('$TAG: Quyền micrô bị từ chối');
          _dispatchEvent(
            XiaozhiServiceEvent(XiaozhiServiceEventType.error, 'Quyền micrô bị từ chối'),
          );
          return;
        }
      }

      // 初始化音频系统
      await AudioUtil.stopPlaying();
      await AudioUtil.initRecorder();
      await AudioUtil.initPlayer();

      print('$TAG: 正在连接 $websocketUrl');
      print('$TAG: 设备ID: $macAddress');
      print('$TAG: Token启用: true');
      print('$TAG: Token: [đã ẩn]');

      // 使用 WebSocketManager 连接
      _webSocketManager = XiaozhiWebSocketManager(
        deviceId: macAddress,
        clientId: clientId,
        enableToken: true,
      );
      _webSocketManager!.addListener(_onWebSocketEvent);
      await _webSocketManager!.connect(websocketUrl, token);
    } catch (e) {
      print('$TAG: 连接Thất bại: $e');
      rethrow;
    }
  }

  /// 结束Giọng nói通话
  Future<void> disconnectVoiceCall() async {
    if (_webSocketManager == null) return;

    try {
      // 停止音频录制
      if (AudioUtil.isRecording) {
        await AudioUtil.stopRecording();
      }

      // 停止音频播放
      await AudioUtil.stopPlaying();

      // Hủy音频流订阅
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // 直接断开连接
      await disconnect();
    } catch (e) {
      // 忽略断开连接时的Lỗi
      print('$TAG: 结束Giọng nói通话时发生Lỗi: $e');
    }
  }

  /// 开始说话
  Future<void> startSpeaking() async {
    try {
      final message = {'type': 'speak', 'state': 'start', 'mode': 'auto'};
      _webSocketManager?.sendMessage(jsonEncode(message));
      print('$TAG: 已发送开始说话Tin nhắn');
    } catch (e) {
      print('$TAG: 开始说话Thất bại: $e');
    }
  }

  /// 停止说话
  Future<void> stopSpeaking() async {
    try {
      final message = {'type': 'speak', 'state': 'stop', 'mode': 'auto'};
      _webSocketManager?.sendMessage(jsonEncode(message));
      print('$TAG: 已发送停止说话Tin nhắn');
    } catch (e) {
      print('$TAG: 停止说话Thất bại: $e');
    }
  }

  /// 发送listenTin nhắn
  void _sendListenMessage() async {
    try {
      final listenMessage = {
        'type': 'listen',
        'session_id': _sessionId,
        'state': 'start',
        'mode': 'auto',
      };
      _webSocketManager?.sendMessage(jsonEncode(listenMessage));
      print('$TAG: 已发送listenTin nhắn');

      // 开始录音
      _isVoiceCallActive = true;
      await AudioUtil.startRecording();
    } catch (e) {
      print('$TAG: 发送listenTin nhắnThất bại: $e');
      _dispatchEvent(
        XiaozhiServiceEvent(XiaozhiServiceEventType.error, 'Không thể gửi lệnh nghe: $e'),
      );
    }
  }

  /// 开始听说（Giọng nói通话Chế độ）
  Future<void> startListeningCall() async {
    try {
      // 确保已经有Cuộc trò chuyệnID
      if (_sessionId == null) {
        print('$TAG: 没有Cuộc trò chuyệnID，无法开始监听，等待Cuộc trò chuyệnID初始化...');
        // 等待短暂时间，然后重新检查Cuộc trò chuyệnID
        await Future.delayed(const Duration(milliseconds: 500));
        if (_sessionId == null) {
          print('$TAG: Cuộc trò chuyệnID仍然为空，放弃开始监听');
          throw Exception('Phiên thoại chưa sẵn sàng để ghi âm');
        }
      }

      print('$TAG: 使用Cuộc trò chuyệnID开始录音: $_sessionId');

      // 请求麦克风权限
      if (Platform.isIOS) {
        final micStatus = await Permission.microphone.status;
        if (micStatus != PermissionStatus.granted) {
          final result = await Permission.microphone.request();
          if (result != PermissionStatus.granted) {
            print('$TAG: Quyền micrô bị từ chối');
            _dispatchEvent(
              XiaozhiServiceEvent(XiaozhiServiceEventType.error, 'Quyền micrô bị từ chối'),
            );
            return;
          }
        }

        // 确保音频Cuộc trò chuyện已初始化
        await AudioUtil.initRecorder();
      } else {
        // Android权限请求
        final status = await Permission.microphone.request();
        if (status.isDenied) {
          print('$TAG: Quyền micrô bị từ chối');
          _dispatchEvent(
            XiaozhiServiceEvent(XiaozhiServiceEventType.error, 'Quyền micrô bị từ chối'),
          );
          return;
        }
      }

      // 开始录音
      await AudioUtil.startRecording();

      // Cài đặt音频流订阅
      _audioStreamSubscription = AudioUtil.audioStream.listen((opusData) {
        // 发送音频数据
        _webSocketManager?.sendBinaryMessage(opusData);
      });

      // 发送开始监听命令
      final message = {
        'session_id': _sessionId,
        'type': 'listen',
        'state': 'start',
        'mode': 'auto',
      };
      _webSocketManager?.sendMessage(jsonEncode(message));
      print('$TAG: 已发送开始监听Tin nhắn (Giọng nói通话Chế độ)');
    } catch (e) {
      print('$TAG: 开始监听Thất bại: $e');
      throw Exception('Không thể bắt đầu nhập giọng nói: $e');
    }
  }

  /// 停止听说（Giọng nói通话Chế độ）
  Future<void> stopListeningCall() async {
    try {
      // Hủy音频流订阅
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // 停止录音
      await AudioUtil.stopRecording();

      // 发送停止监听命令
      if (_sessionId != null && _webSocketManager != null) {
        final message = {
          'session_id': _sessionId,
          'type': 'listen',
          'state': 'stop',
          'mode': 'auto',
        };
        _webSocketManager?.sendMessage(jsonEncode(message));
        print('$TAG: 已发送停止监听Tin nhắn (Giọng nói通话Chế độ)');
      }
    } catch (e) {
      print('$TAG: 停止监听Thất bại: $e');
    }
  }

  /// Hủy发送（上滑Hủy）
  Future<void> abortListening() async {
    try {
      // Hủy音频流订阅
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // 停止录音
      await AudioUtil.stopRecording();

      // 发送中止命令
      if (_sessionId != null && _webSocketManager != null) {
        final message = {'session_id': _sessionId, 'type': 'abort'};
        _webSocketManager?.sendMessage(jsonEncode(message));
        print('$TAG: 已发送中止Tin nhắn');
      }
    } catch (e) {
      print('$TAG: 中止监听Thất bại: $e');
    }
  }

  /// 切换静音状态
  void toggleMute() {
    _isMuted = !_isMuted;

    if (_webSocketManager == null || !_webSocketManager!.isConnected) return;

    try {
      final request = {'type': _isMuted ? 'voice_mute' : 'voice_unmute'};

      _webSocketManager!.sendMessage(jsonEncode(request));
    } catch (e) {
      print('$TAG: 切换静音状态Thất bại: $e');
    }
  }

  /// 处理WebSocket事件
  void _onWebSocketEvent(XiaozhiEvent event) {
    switch (event.type) {
      case XiaozhiEventType.connected:
        _isConnected = true;
        _dispatchEvent(
          XiaozhiServiceEvent(XiaozhiServiceEventType.connected, null),
        );
        break;

      case XiaozhiEventType.disconnected:
        _isConnected = false;
        _dispatchEvent(
          XiaozhiServiceEvent(XiaozhiServiceEventType.disconnected, null),
        );
        break;

      case XiaozhiEventType.message:
        _handleTextMessage(event.data as String);
        break;

      case XiaozhiEventType.binaryMessage:
        // 处理二进制音频数据 - 简化直接播放
        final audioData = event.data as List<int>;
        AudioUtil.playOpusData(Uint8List.fromList(audioData));
        break;

      case XiaozhiEventType.error:
        _dispatchEvent(
          XiaozhiServiceEvent(XiaozhiServiceEventType.error, event.data),
        );
        break;
    }
  }

  /// 处理WebSocketTin nhắn
  void _handleWebSocketMessage(dynamic message) {
    try {
      if (message is String) {
        _handleTextMessage(message);
      } else if (message is List<int>) {
        AudioUtil.playOpusData(Uint8List.fromList(message));
      }
    } catch (e) {
      print('$TAG: 处理Tin nhắnThất bại: $e');
    }
  }

  /// 处理Văn bảnTin nhắn
  void _handleTextMessage(String message) {
    print('$TAG: 收到Văn bảnTin nhắn: $message');
    try {
      final Map<String, dynamic> jsonData = json.decode(message);
      final String type = jsonData['type'] ?? '';

      // 确保首先调用Tin nhắn监听器
      if (_messageListener != null) {
        _messageListener!(jsonData);
      }

      // 更新Cuộc trò chuyệnID（服务器在helloTin nhắn中会提供新的Cuộc trò chuyệnID）
      if (jsonData['session_id'] != null) {
        _sessionId = jsonData['session_id'];
        print('$TAG: 更新Cuộc trò chuyệnID: $_sessionId');
      }

      // 根据Tin nhắn类型分发事件
      switch (type) {
        case 'hello':
          // 处理服务器的hello响应
          if (_isVoiceCallActive && !_hasStartedCall) {
            _hasStartedCall = true;
            // 发送自动说话Chế độTin nhắn
            startSpeaking();
          }
          break;

        case 'start':
          // 收到start响应后，如果是Giọng nói通话Chế độ，开始录音
          if (_isVoiceCallActive) {
            _sendListenMessage();
          }
          break;

        case 'tts':
          // TTSTin nhắn处理
          final String state = jsonData['state'] ?? '';
          final String text = jsonData['text'] ?? '';

          if (state == 'sentence_start' && text.isNotEmpty) {
            print('$TAG: 收到TTS句子: $text');
            _dispatchEvent(
              XiaozhiServiceEvent(XiaozhiServiceEventType.textMessage, text),
            );
          }
          break;

        case 'stt':
          // 处理Giọng nói识别结果
          final String text = jsonData['text'] ?? '';
          if (text.isNotEmpty) {
            print('$TAG: 收到Giọng nói识别结果: $text');
            // 先分发用户Tin nhắn事件
            _dispatchEvent(
              XiaozhiServiceEvent(XiaozhiServiceEventType.userMessage, text),
            );
          }
          break;

        case 'emotion':
          // 处理表情Tin nhắn
          final String emotion = jsonData['emotion'] ?? '';
          if (emotion.isNotEmpty) {
            print('$TAG: 收到表情Tin nhắn: $emotion');
            _dispatchEvent(
              XiaozhiServiceEvent(
                XiaozhiServiceEventType.textMessage,
                '表情: $emotion',
              ),
            );
          }
          break;

        default:
          // 对于其他类型的Tin nhắn，直接忽略
          print('$TAG: 收到未知类型Tin nhắn: $type, 原始数据: $message');
      }
    } catch (e) {
      print('$TAG: 解析Tin nhắnThất bại: $e, 原始Tin nhắn: $message');
    }
  }

  /// 开始通话
  void _startCall() {
    try {
      // 发送开始通话Tin nhắn
      final startMessage = {
        'type': 'start',
        'mode': 'auto',
        'audio_params': {
          'format': 'opus',
          'sample_rate': 16000,
          'channels': 1,
          'frame_duration': 60,
        },
      };
      _webSocketManager?.sendMessage(jsonEncode(startMessage));
      print('$TAG: 已发送开始通话Tin nhắn');
    } catch (e) {
      print('$TAG: 开始通话Thất bại: $e');
    }
  }

  /// 中断音频播放
  Future<void> stopPlayback() async {
    try {
      print('$TAG: 正在停止音频播放');

      // 简单直接地停止播放
      await AudioUtil.stopPlaying();

      print('$TAG: 音频播放已停止');
    } catch (e) {
      print('$TAG: 停止音频播放Thất bại: $e');
    }
  }

  /// 判断是否Đã kết nối
  bool get isConnected =>
      _isConnected &&
      _webSocketManager != null &&
      _webSocketManager!.isConnected;

  /// 判断是否静音
  bool get isMuted => _isMuted;

  /// 判断Giọng nói通话是否活跃
  bool get isVoiceCallActive => _isVoiceCallActive;

  /// 释放资源
  Future<void> dispose() async {
    await disconnect();
    await AudioUtil.dispose();
    _listeners.clear();
    print('$TAG: 资源已释放');
  }

  /// 开始监听（Nhấn giữ để nóiChế độ）
  Future<void> startListening({String mode = 'manual'}) async {
    if (!_isConnected || _webSocketManager == null) {
      await connect();
    }

    try {
      // 确保已经有Cuộc trò chuyệnID
      if (_sessionId == null) {
        print('$TAG: 没有Cuộc trò chuyệnID，无法开始监听');
        return;
      }

      // 开始录音
      await AudioUtil.startRecording();

      // 发送开始监听命令
      final message = {
        'session_id': _sessionId,
        'type': 'listen',
        'state': 'start',
        'mode': mode,
      };
      _webSocketManager?.sendMessage(jsonEncode(message));
      print('$TAG: 已发送开始监听Tin nhắn (Nhấn giữ để nói)');

      // Cài đặt音频流订阅
      _audioStreamSubscription = AudioUtil.audioStream.listen((opusData) {
        // 发送音频数据
        _webSocketManager?.sendBinaryMessage(opusData);
      });
    } catch (e) {
      print('$TAG: 开始监听Thất bại: $e');
      throw Exception('Không thể bắt đầu nhập giọng nói: $e');
    }
  }

  /// 停止监听（Nhấn giữ để nóiChế độ）
  Future<void> stopListening() async {
    try {
      // Hủy音频流订阅
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // 停止录音
      await AudioUtil.stopRecording();

      // 发送停止监听命令
      if (_sessionId != null && _webSocketManager != null) {
        final message = {
          'session_id': _sessionId,
          'type': 'listen',
          'state': 'stop',
        };
        _webSocketManager?.sendMessage(jsonEncode(message));
        print('$TAG: 已发送停止监听Tin nhắn');
      }
    } catch (e) {
      print('$TAG: 停止监听Thất bại: $e');
    }
  }

  /// 发送中断Tin nhắn
  Future<void> sendAbortMessage() async {
    try {
      if (_webSocketManager != null && _isConnected && _sessionId != null) {
        final abortMessage = {
          'session_id': _sessionId,
          'type': 'abort',
          'reason': 'wake_word_detected',
        };
        _webSocketManager?.sendMessage(jsonEncode(abortMessage));
        print('$TAG: 发送中断Tin nhắn: $abortMessage');

        // 如果当前正在录音，短暂停顿后继续
        if (_isSpeaking) {
          await stopListeningCall();
          await Future.delayed(const Duration(milliseconds: 500));
          await startListeningCall();
        }
      }
    } catch (e) {
      print('$TAG: 发送中断Tin nhắnThất bại: $e');
    }
  }

  /// 判断是否正在说话
  bool get _isSpeaking => _audioStreamSubscription != null;
}
