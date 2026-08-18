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
import '../utils/response_text_sanitizer.dart';
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
typedef RealtimeMcpHandler = Future<String> Function(String query);

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
  bool _suppressIncomingAudio = false;
  Completer<void>? _suppressedTtsStopCompleter;
  RealtimeMcpHandler? _realtimeMcpHandler;
  bool _mcpBackendDetected = false;

  // v4.1 response gate: trong lúc chờ STT để Tool Router quyết định, không
  // phát ngay câu trả lời/TTS của Agent. Nếu câu là local tool thì buffer bị
  // bỏ; nếu là hội thoại thường thì mới release. Điều này loại bỏ race khiến
  // các chuỗi kiểu `% gold_price...` hoặc `% search_knowledge...` lọt ra UI.
  bool _responseGateActive = false;
  final List<Uint8List> _gatedAudioFrames = <Uint8List>[];
  final List<String> _gatedTtsSentences = <String>[];
  final List<String> _activeTtsParts = <String>[];
  Timer? _responseGateTimer;
  int _cloudAudioFramesReceived = 0;
  int _ttsFrameBaseline = 0;
  int _ttsPlayedBaseline = 0;
  String _lastUserStt = '';
  bool _pendingMcpToolResponse = false;
  bool _activeTtsIsToolResponse = false;

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

  /// Đăng ký một tool MCP tổng quát để backend Xiaozhi có thể gọi các công cụ
  /// realtime của app. Khi backend gọi tool, kết quả được trả lại cho LLM và
  /// chính Xiaozhi sẽ tổng hợp + phát bằng giọng Agent đã cấu hình trên web.
  void setRealtimeMcpHandler(RealtimeMcpHandler handler) {
    _realtimeMcpHandler = handler;
  }

  bool get isMcpBackendDetected => _mcpBackendDetected;
  int get downlinkSampleRate => AudioUtil.downlinkSampleRate;
  bool get cloudAudioPlayerReady => AudioUtil.isPlayerReady;
  int get cloudAudioFramesReceived => _cloudAudioFramesReceived;
  int get cloudAudioFramesPlayed => AudioUtil.cloudFramesPlayed;
  String get cloudAudioLastError => AudioUtil.lastPlaybackError;

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
    discardResponseGate();
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

  /// Xiaozhi official WebSocket của app này là voice/audio protocol.
  /// Không dùng `listen/detect` như general text chat vì server có thể không
  /// trả response và bản cũ sẽ chờ 15 giây rồi báo timeout.
  Future<String> sendTextMessageSilently(String message) async {
    return sendTextMessage(message);
  }

  Future<String> sendTextMessage(String message) async {
    throw UnsupportedError(
      'Xiaozhi voice protocol không hỗ trợ general text chat trong client này. '
      'Hãy dùng luồng mic/audio hoặc MiniMax/Dify cho tin nhắn gõ.',
    );
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
        discardResponseGate();
        _dispatchEvent(
          XiaozhiServiceEvent(XiaozhiServiceEventType.disconnected, null),
        );
        break;

      case XiaozhiEventType.message:
        _handleTextMessage(event.data as String);
        break;

      case XiaozhiEventType.binaryMessage:
        final audioData = Uint8List.fromList(event.data as List<int>);
        _cloudAudioFramesReceived++;
        if (_responseGateActive) {
          // Giới hạn buffer để không tăng RAM vô hạn nếu server lỗi protocol.
          if (_gatedAudioFrames.length < 320) {
            _gatedAudioFrames.add(audioData);
          }
        } else if (!_suppressIncomingAudio) {
          AudioUtil.playOpusData(audioData);
        }
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
        final audioData = Uint8List.fromList(message);
        _cloudAudioFramesReceived++;
        if (_responseGateActive) {
          if (_gatedAudioFrames.length < 320) _gatedAudioFrames.add(audioData);
        } else if (!_suppressIncomingAudio) {
          AudioUtil.playOpusData(audioData);
        }
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
          // Server có quyền thương lượng downlink sample-rate riêng (thường
          // 16 kHz, đôi khi 24 kHz). Không được decode cứng 16 kHz vì sẽ làm
          // cloud Female Voice méo hoặc im lặng trên một số backend.
          final audioParams = jsonData['audio_params'];
          if (audioParams is Map) {
            final rawRate = audioParams['sample_rate'];
            final rate = rawRate is num ? rawRate.toInt() : int.tryParse('$rawRate');
            if (rate != null && rate > 0) {
              unawaited(AudioUtil.configureDownlinkSampleRate(rate));
            }
          }
          if (_isVoiceCallActive && !_hasStartedCall) {
            _hasStartedCall = true;
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
          final String state = (jsonData['state'] ?? '').toString();
          final String text = (jsonData['text'] ?? '').toString();

          if (state == 'start') {
            _activeTtsParts.clear();
            _activeTtsIsToolResponse = _pendingMcpToolResponse;
            _pendingMcpToolResponse = false;
            _ttsFrameBaseline = _cloudAudioFramesReceived;
            _ttsPlayedBaseline = AudioUtil.cloudFramesPlayed;
            if (!_suppressIncomingAudio) {
              unawaited(AudioUtil.beginCloudTts());
            }
          }

          if (state == 'sentence_start' && text.trim().isNotEmpty) {
            print('$TAG: 收到TTS句子: $text');
            // Không tạo một bubble cho từng sentence_start. Xiaozhi thường gửi
            // 2-5 mảnh cho một câu trả lời; ghép lại ở tts:stop sẽ gọn và loại
            // được marker `% weather...` / Markdown `**`.
            if (ResponseTextSanitizer.isInternalToolCommand(text)) {
              _activeTtsIsToolResponse = true;
            } else {
              _activeTtsParts.add(text);
            }
          }

          if (state == 'stop') {
            AudioUtil.endCloudTts();
            final nativeFramesThisTurn =
                _cloudAudioFramesReceived - _ttsFrameBaseline;
            final playedFramesThisTurn =
                AudioUtil.cloudFramesPlayed - _ttsPlayedBaseline;
            if (!_suppressIncomingAudio &&
                nativeFramesThisTurn <= 0 &&
                _activeTtsParts.isNotEmpty) {
              _dispatchEvent(
                XiaozhiServiceEvent(
                  XiaozhiServiceEventType.error,
                  'Xiaozhi đã trả văn bản nhưng không gửi frame audio TTS trong lượt này. Hãy kiểm tra cấu hình voice/Agent hoặc kết nối server.',
                ),
              );
            } else if (!_suppressIncomingAudio &&
                nativeFramesThisTurn > 0 &&
                playedFramesThisTurn <= 0) {
              // WebSocket callback chỉ enqueue frame; đợi queue tiêu thụ một
              // nhịp trước khi kết luận player im lặng để tránh báo lỗi giả.
              unawaited(
                _verifyCloudPlaybackAfterTts(
                  nativeFramesThisTurn,
                  _ttsPlayedBaseline,
                ),
              );
            }
            if (_suppressedTtsStopCompleter != null &&
                !_suppressedTtsStopCompleter!.isCompleted) {
              _suppressedTtsStopCompleter!.complete();
            }

            var fullText = ResponseTextSanitizer.joinSentences(_activeTtsParts);
            if (_activeTtsIsToolResponse) {
              fullText = ResponseTextSanitizer.limitSentences(fullText);
            }
            _activeTtsParts.clear();
            _activeTtsIsToolResponse = false;
            if (fullText.isNotEmpty) {
              if (_responseGateActive) {
                _gatedTtsSentences.add(fullText);
              } else {
                _dispatchEvent(
                  XiaozhiServiceEvent(XiaozhiServiceEventType.textMessage, fullText),
                );
              }
            }
          }
          break;

        case 'stt':
          // 处理Giọng nói识别结果. Giữ nguyên câu STT mới nhất làm nguồn
          // sự thật cho MCP tool arguments; không để LLM tự đổi địa điểm
          // (ví dụ người dùng nói Đà Nẵng nhưng model truyền một nơi khác).
          final String text = jsonData['text'] ?? '';
          if (text.isNotEmpty) {
            _lastUserStt = text.trim();
            print('$TAG: 收到Giọng nói识别结果: $text');
            // 先分发用户Tin nhắn事件
            _dispatchEvent(
              XiaozhiServiceEvent(XiaozhiServiceEventType.userMessage, text),
            );
          }
          break;

        case 'mcp':
          unawaited(_handleMcpEnvelope(jsonData));
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

  Future<void> _verifyCloudPlaybackAfterTts(
    int receivedFrames,
    int playedBaseline,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (_suppressIncomingAudio) return;
    final played = AudioUtil.cloudFramesPlayed - playedBaseline;
    if (played > 0) return;
    final detail = AudioUtil.lastPlaybackError.trim();
    _dispatchEvent(
      XiaozhiServiceEvent(
        XiaozhiServiceEventType.error,
        'Đã nhận $receivedFrames frame Female Voice nhưng PCM player chưa phát được${detail.isEmpty ? "." : ": $detail"}',
      ),
    );
  }

  Future<void> _handleMcpEnvelope(Map<String, dynamic> envelope) async {
    final payload = envelope['payload'];
    if (payload is! Map) return;
    final request = Map<String, dynamic>.from(payload);
    final method = (request['method'] ?? '').toString();
    final id = request['id'];
    if (method.isEmpty) return;

    _mcpBackendDetected = true;

    if (method == 'initialize') {
      _sendMcpResult(id, {
        'protocolVersion': '2024-11-05',
        'capabilities': {'tools': <String, dynamic>{}},
        'serverInfo': {
          'name': 'AI-LHHT-Android',
          'version': '4.1.3',
        },
      });
      return;
    }

    if (method == 'tools/list') {
      // Khai báo tool cụ thể thay vì chỉ một generic lookup. Mô hình Xiaozhi
      // sẽ dễ chọn đúng tool của THIẾT BỊ hơn các legacy command kiểu
      // `% weather...`, nhờ đó dữ liệu/location do app kiểm soát và voice cuối
      // vẫn là Female Voice từ cloud.
      _sendMcpResult(id, {
        'tools': [
          _mcpTool(
            'self.realtime.lookup',
            'Tra cứu realtime tổng quát bằng công cụ của ứng dụng. Ưu tiên tool này thay vì legacy percent-command.',
            {'query': 'Nguyên câu hỏi của người dùng.'},
            const ['query'],
          ),
          _mcpTool(
            'self.weather.lookup',
            'Tra thời tiết bằng dữ liệu ứng dụng. PHẢI dùng tool này cho mọi câu hỏi thời tiết thay vì `% weather` legacy. Giữ NGUYÊN địa điểm người dùng nói; sau tool trả lời tối đa 2 câu, không Markdown, không bình luận thêm.',
            {'location': 'Địa điểm nguyên văn người dùng yêu cầu, ví dụ Hà Nội, Đà Nẵng, Chánh Hiệp.'},
            const ['location'],
          ),
          _mcpTool(
            'self.air_quality.lookup',
            'Tra AQI/chất lượng không khí bằng dữ liệu ứng dụng. Sau tool trả lời ngắn gọn, không Markdown, không thêm bình luận cá nhân.',
            {'location': 'Địa điểm cần tra.'},
            const ['location'],
          ),
          _mcpTool(
            'self.vietnam.lottery',
            'Tra kết quả xổ số Việt Nam bằng công cụ ứng dụng. Dùng dữ liệu tool, không tự đoán và không dùng legacy percent-command.',
            {'query': 'Câu hỏi xổ số nguyên văn, gồm miền/tỉnh/ngày nếu có.'},
            const ['query'],
          ),
          _mcpTool(
            'self.finance.fx',
            'Tra tỷ giá hoặc quy đổi tiền tệ bằng dữ liệu ứng dụng.',
            {'query': 'Câu hỏi tỷ giá/quy đổi nguyên văn.'},
            const ['query'],
          ),
          _mcpTool(
            'self.market.crypto',
            'Tra giá crypto bằng dữ liệu ứng dụng.',
            {'query': 'Câu hỏi crypto nguyên văn.'},
            const ['query'],
          ),
          _mcpTool(
            'self.news.latest',
            'Tra tin mới nhất bằng nguồn tin của ứng dụng. Tóm tắt ngắn gọn, không Markdown, không thêm câu trêu chọc vào dữ liệu.',
            {'query': 'Chủ đề tin tức hoặc câu hỏi nguyên văn.'},
            const ['query'],
          ),
          _mcpTool(
            'self.vietnam.carrier',
            'Tra nhà mạng/đầu số Việt Nam bằng database ứng dụng.',
            {'query': 'Số điện thoại hoặc đầu số cần tra.'},
            const ['query'],
          ),
          _mcpTool(
            'self.vietnam.plate',
            'Tra biển số xe Việt Nam bằng database ứng dụng.',
            {'query': 'Biển số hoặc mã tỉnh cần tra.'},
            const ['query'],
          ),
          _mcpTool(
            'self.gold.lookup',
            'Tra giá vàng qua provider của ứng dụng nếu đang khả dụng.',
            {'query': 'Câu hỏi giá vàng nguyên văn.'},
            const ['query'],
          ),
        ],
      });
      return;
    }

    if (method == 'tools/call') {
      final params = request['params'];
      if (params is! Map) {
        _sendMcpError(id, -32602, 'Missing params');
        return;
      }
      final name = (params['name'] ?? '').toString();
      final arguments = params['arguments'];
      final args = arguments is Map ? Map<String, dynamic>.from(arguments) : <String, dynamic>{};
      final query = _queryForMcpTool(name, args);
      if (query == null) {
        _sendMcpError(id, -32601, 'Unknown tool: $name');
        return;
      }
      if (query.trim().isEmpty) {
        _sendMcpError(id, -32602, 'Tool arguments are incomplete');
        return;
      }
      try {
        _pendingMcpToolResponse = true;
        final handler = _realtimeMcpHandler;
        if (handler == null) {
          throw StateError('Realtime tool handler is not registered.');
        }
        final resultText = ResponseTextSanitizer.clean(
          (await handler(query)).trim(),
          compact: true,
        );
        _sendMcpResult(id, {
          'content': [
            {'type': 'text', 'text': resultText.isEmpty ? 'Không có dữ liệu.' : resultText},
          ],
          'isError': false,
        });
      } catch (e) {
        _sendMcpResult(id, {
          'content': [
            {'type': 'text', 'text': 'Không tra cứu được dữ liệu lúc này: $e'},
          ],
          'isError': true,
        });
      }
      return;
    }

    if (id != null) {
      _sendMcpError(id, -32601, 'Method not implemented: $method');
    }
  }

  Map<String, dynamic> _mcpTool(
    String name,
    String description,
    Map<String, String> properties,
    List<String> required,
  ) {
    return {
      'name': name,
      'description': description,
      'inputSchema': {
        'type': 'object',
        'properties': properties.map(
          (key, value) => MapEntry(key, {'type': 'string', 'description': value}),
        ),
        'required': required,
      },
    };
  }

  String? _queryForMcpTool(String name, Map<String, dynamic> args) {
    String value(String key) => (args[key] ?? '').toString().trim();
    final spoken = _lastUserStt.trim();

    // Với tool phát sinh trực tiếp từ câu nói hiện tại, ưu tiên transcript gốc
    // thay vì tham số LLM tự suy diễn. Đây là lớp chống "query drift" cho địa
    // điểm, mã tiền, đầu số... và đặc biệt là weather.
    String preferSpoken(String fallback) => spoken.isNotEmpty ? spoken : fallback;

    switch (name) {
      case 'self.realtime.lookup':
        return preferSpoken(value('query'));
      case 'self.weather.lookup':
        return preferSpoken('thời tiết ở ${value('location')} hôm nay');
      case 'self.air_quality.lookup':
        return preferSpoken('chất lượng không khí ở ${value('location')} hiện tại');
      case 'self.vietnam.lottery':
        return preferSpoken(value('query'));
      case 'self.finance.fx':
        return preferSpoken(value('query'));
      case 'self.market.crypto':
        return preferSpoken(value('query'));
      case 'self.news.latest':
        return preferSpoken(value('query').isEmpty ? 'tin tức mới nhất hôm nay' : value('query'));
      case 'self.vietnam.carrier':
        return preferSpoken('nhà mạng ${value('query')}');
      case 'self.vietnam.plate':
        return preferSpoken('biển số ${value('query')}');
      case 'self.gold.lookup':
        return preferSpoken(value('query').isEmpty ? 'giá vàng hôm nay' : value('query'));
      default:
        return null;
    }
  }

  void _sendMcpResult(dynamic id, Map<String, dynamic> result) {
    if (id == null) return;
    _sendMcpPayload({
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    });
  }

  void _sendMcpError(dynamic id, int code, String message) {
    if (id == null) return;
    _sendMcpPayload({
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': code, 'message': message},
    });
  }

  void _sendMcpPayload(Map<String, dynamic> payload) {
    final envelope = <String, dynamic>{
      if (_sessionId != null) 'session_id': _sessionId,
      'type': 'mcp',
      'payload': payload,
    };
    _webSocketManager?.sendMessage(jsonEncode(envelope));
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

  /// Chọn đường phát tiếng. Khi true, binary TTS của Xiaozhi bị tắt và UI
  /// dùng UnifiedSpeechOutputService cho cả Agent/Tool để giữ một giọng.
  void setSuppressIncomingAudio(bool value) {
    _suppressIncomingAudio = value;
    if (value) {
      unawaited(AudioUtil.stopPlaying());
    }
  }

  /// Khóa tạm phản hồi Agent cho tới khi STT được Tool Router phân loại.
  void beginResponseGate() {
    _responseGateTimer?.cancel();
    _responseGateActive = true;
    _gatedAudioFrames.clear();
    _gatedTtsSentences.clear();
    // Fail-open: nếu STT không về do mạng, không giữ phản hồi mãi mãi.
    _responseGateTimer = Timer(const Duration(seconds: 8), () {
      unawaited(releaseResponseGate());
    });
  }

  /// Hội thoại bình thường: mở gate và phát/dispatch phần đã buffer.
  Future<void> releaseResponseGate() async {
    if (!_responseGateActive) return;
    _responseGateTimer?.cancel();
    _responseGateTimer = null;
    _responseGateActive = false;

    final sentences = List<String>.from(_gatedTtsSentences);
    final audioFrames = List<Uint8List>.from(_gatedAudioFrames);
    _gatedTtsSentences.clear();
    _gatedAudioFrames.clear();

    final fullText = ResponseTextSanitizer.joinSentences(sentences);
    if (fullText.isNotEmpty) {
      _dispatchEvent(
        XiaozhiServiceEvent(XiaozhiServiceEventType.textMessage, fullText),
      );
    }
    if (!_suppressIncomingAudio) {
      for (final frame in audioFrames) {
        await AudioUtil.playOpusData(frame);
      }
    }
  }

  /// Local tool/command đã nhận câu nói: bỏ mọi phản hồi Agent đã chạy đua
  /// phía cloud rồi mới abort session.
  void discardResponseGate() {
    _responseGateTimer?.cancel();
    _responseGateTimer = null;
    _responseGateActive = false;
    _gatedAudioFrames.clear();
    _gatedTtsSentences.clear();
    _activeTtsParts.clear();
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


  /// Ngắt câu trả lời/TTS hiện tại mà không tự khởi động lại microphone.
  /// Dùng cho chế độ phiên dịch: Xiaozhi chỉ làm ASR, sau đó app tự tạo bản dịch.
  Future<void> interruptResponse() async {
    try {
      if (_webSocketManager != null && _isConnected && _sessionId != null) {
        final abortMessage = {
          'session_id': _sessionId,
          'type': 'abort',
          'reason': 'interpreter_takeover',
        };
        _webSocketManager?.sendMessage(jsonEncode(abortMessage));
      }
      await stopPlayback();
    } catch (e) {
      print('$TAG: Không thể ngắt phản hồi hiện tại: $e');
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
