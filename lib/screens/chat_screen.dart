import 'package:flutter/material.dart';
import 'package:ai_assistant/utils/vietnamese_transcript_normalizer.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'dart:math';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ai_assistant/models/conversation.dart';
import 'package:ai_assistant/models/message.dart';
import 'package:ai_assistant/models/xiaozhi_config.dart';
import 'package:ai_assistant/models/dify_config.dart';
import 'package:ai_assistant/providers/conversation_provider.dart';
import 'package:ai_assistant/providers/config_provider.dart';
import 'package:ai_assistant/models/minimax_config.dart';
import 'package:ai_assistant/services/dify_service.dart';
import 'package:ai_assistant/services/xiaozhi_service.dart';
import 'package:ai_assistant/services/translation_service.dart';
import 'package:ai_assistant/services/native_speech_service.dart';
import 'package:ai_assistant/services/realtime_tool_service.dart';
import 'package:ai_assistant/services/unified_speech_output_service.dart';
import 'package:ai_assistant/services/voice_output_preferences.dart';
import 'package:ai_assistant/tools/services/realtime_tool_engine.dart';
import 'package:ai_assistant/utils/interpreter_turn_controller.dart';
import 'package:ai_assistant/services/minimax_service.dart';
import 'package:ai_assistant/widgets/message_bubble.dart';
import 'package:ai_assistant/screens/voice_call_screen.dart';
import 'package:ai_assistant/screens/music_player_screen.dart';
import 'dart:convert';
import 'dart:async';
import 'package:path_provider/path_provider.dart';

class ChatScreen extends StatefulWidget {
  final Conversation conversation;

  const ChatScreen({super.key, required this.conversation});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  XiaozhiService? _xiaozhiService; // 保持XiaozhiService实例
  DifyService? _difyService; // 保持DifyService实例
  MiniMaxService? _minimaxService; // 保持MiniMaxService实例
  Timer? _connectionCheckTimer; // Thêm定时器检查连接状态
  Timer? _autoReconnectTimer; // 自动重连定时器

  // v4.1 dùng một TTS duy nhất cho Agent + Tool + Interpreter khi chế độ
  // "Giọng ổn định" bật. Không còn hai engine tranh audio-focus.
  final UnifiedSpeechOutputService _speechOutput =
      UnifiedSpeechOutputService.instance;
  final VoiceOutputPreferences _voiceOutputPreferences =
      VoiceOutputPreferences();
  bool _unifiedVoiceOutput = true;
  bool _liveInterpreterMode = false;
  bool _interpreterBusy = false;
  bool _interpreterWaitingForXiaozhi = false;
  String _interpreterLanguageA = 'Tiếng Việt';
  String _interpreterLocaleA = 'vi-VN';
  String _interpreterLanguageB = 'English';
  String _interpreterLocaleB = 'en-US';
  late InterpreterTurnController _interpreterTurn;
  final NativeSpeechService _nativeSpeech = NativeSpeechService.instance;
  final RealtimeToolService _realtimeTools = RealtimeToolService();
  final RealtimeToolEngine _toolEngine = RealtimeToolEngine();
  bool _usingNativeSpeech = false;
  String _nativePartialTranscript = '';
  bool _pendingOnlineMusicSearch = false;

  // Giọng nói输入相关
  bool _isVoiceInputMode = false;
  bool _isRecording = false;
  bool _isCancelling = false;
  double _startDragY = 0.0;
  final double _cancelThreshold = 50.0; // 上滑超过这个距离认为是Hủy
  Timer? _waveAnimationTimer;
  final List<double> _waveHeights = List.filled(20, 0.0);
  double _minWaveHeight = 5.0;
  double _maxWaveHeight = 30.0;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _interpreterTurn = InterpreterTurnController(
      languageA: _interpreterLanguageA,
      localeA: _interpreterLocaleA,
      languageB: _interpreterLanguageB,
      localeB: _interpreterLocaleB,
    );
    unawaited(_nativeSpeech.initialize());
    unawaited(_initializeVoiceOutput());

    // Cài đặt状态栏为透明并使图标为黑色
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );

    // 在帧绘制后再次Cài đặt系统UI样式，避免被覆盖
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
        ),
      );

      Provider.of<ConversationProvider>(
        context,
        listen: false,
      ).markConversationAsRead(widget.conversation.id);

      // 如果是Xiaozhi对话，初始化服务
      if (widget.conversation.type == ConversationType.xiaozhi) {
        _initXiaozhiService();
        // Thêm定时器定期检查连接状态
        _connectionCheckTimer = Timer.periodic(const Duration(seconds: 2), (
          timer,
        ) {
          if (mounted && _xiaozhiService != null) {
            final wasConnected = _xiaozhiService!.isConnected;

            // 刷新UI
            setState(() {});

            // 如果状态从连接变为断开，尝试自动重连
            if (wasConnected &&
                !_xiaozhiService!.isConnected &&
                _autoReconnectTimer == null) {
              print('Phát hiện mất kết nối, chuẩn bị kết nối lại');
              _scheduleReconnect();
            }
          }
        });

        // 默认启用Giọng nói输入Chế độ (针对Xiaozhi对话)
        setState(() {
          _isVoiceInputMode = true;
        });
      } else if (widget.conversation.type == ConversationType.dify) {
        // 初始化 DifyService
        _initDifyService();
      } else if (widget.conversation.type == ConversationType.minimax) {
        // 初始化 MiniMaxService
        _initMiniMaxService();
      }
    });
  }

  Future<void> _initializeVoiceOutput() async {
    final wantsUnified = await _voiceOutputPreferences.useUnifiedVoice();
    final ttsReady = await _speechOutput.initialize(locale: 'vi-VN');
    _unifiedVoiceOutput = wantsUnified && ttsReady;
    _xiaozhiService?.setSuppressIncomingAudio(_unifiedVoiceOutput);
    if (mounted) setState(() {});
  }

  // 安排自动重连
  void _scheduleReconnect() {
    // Hủy现有重连定时器
    _autoReconnectTimer?.cancel();

    // 创建新的重连定时器，5秒后尝试重连
    _autoReconnectTimer = Timer(const Duration(seconds: 5), () async {
      print('Đang thử kết nối lại...');
      if (_xiaozhiService != null && !_xiaozhiService!.isConnected && mounted) {
        try {
          await _xiaozhiService!.disconnect();
          await _xiaozhiService!.connect();

          setState(() {});
          print('自动重连 ${_xiaozhiService!.isConnected ? "Thành công" : "Thất bại"}');

          // 如果重连Thất bại，则继续尝试重连
          if (!_xiaozhiService!.isConnected) {
            _scheduleReconnect();
          } else {
            _autoReconnectTimer = null;
          }
        } catch (e) {
          print('自动重连出错: $e');
          _scheduleReconnect(); // 出错后继续尝试
        }
      } else {
        _autoReconnectTimer = null;
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    // Hủy所有定时器
    _connectionCheckTimer?.cancel();
    _autoReconnectTimer?.cancel();
    _waveAnimationTimer?.cancel();
    _speechOutput.stop();
    _nativeSpeech.cancel();

    // 在销毁前确保停止所有音频播放
    if (_xiaozhiService != null) {
      _xiaozhiService!.stopPlayback();
      _xiaozhiService!.disconnect();
    }

    super.dispose();
  }

  // 初始化Dịch vụ Xiaozhi
  Future<void> _initXiaozhiService() async {
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    final xiaozhiConfig = configProvider.xiaozhiConfigs.firstWhere(
      (config) => config.id == widget.conversation.configId,
    );

    _xiaozhiService = XiaozhiService(
      websocketUrl: xiaozhiConfig.websocketUrl,
      macAddress: xiaozhiConfig.macAddress,
      clientId: xiaozhiConfig.clientId,
      token: xiaozhiConfig.token,
    );
    _xiaozhiService!.setSuppressIncomingAudio(_unifiedVoiceOutput);

    // ThêmTin nhắn监听器
    _xiaozhiService!.addListener(_handleXiaozhiMessage);

    // 连接服务
    await _xiaozhiService!.connect();

    // 连接后刷新UI状态
    if (mounted) {
      setState(() {});
    }
  }

  // 处理XiaozhiTin nhắn
  void _handleXiaozhiMessage(XiaozhiServiceEvent event) {
    if (!mounted) return;

    final conversationProvider = Provider.of<ConversationProvider>(
      context,
      listen: false,
    );

    if (event.type == XiaozhiServiceEventType.textMessage) {
      final content = (event.data ?? '').toString().trim();
      if (content.isEmpty) return;

      // Trong chế độ phiên dịch, câu trả lời Agent bình thường phải bị chặn.
      // Nếu chính Xiaozhi đang làm backend dịch, sendTextMessage() vẫn nhận
      // textMessage này để hoàn tất Future nhưng UI không thêm trùng bubble.
      if (_liveInterpreterMode) {
        // TranslationService dùng Xiaozhi ở silent mode; không thêm câu trả
        // lời backend vào chat và cũng không abort giữa chừng.
        return;
      }

      conversationProvider.addMessage(
        conversationId: widget.conversation.id,
        role: MessageRole.assistant,
        content: content,
      );
      if (_unifiedVoiceOutput) {
        unawaited(_speechOutput.speak(content, locale: 'vi-VN'));
      }
    } else if (event.type == XiaozhiServiceEventType.userMessage) {
      // Nhánh dự phòng khi native speech của Android không khả dụng.
      final rawContent = (event.data ?? '').toString().trim();
      if (rawContent.isEmpty || !_isVoiceInputMode || _usingNativeSpeech) return;
      Future.microtask(() => _processVoiceTranscript(rawContent, fromXiaozhiStt: true));
    } else if (event.type == XiaozhiServiceEventType.connected ||
        event.type == XiaozhiServiceEventType.disconnected) {
      setState(() {});
    } else if (event.type == XiaozhiServiceEventType.error) {
      if (_liveInterpreterMode && mounted) {
        _showCustomSnackbar('Lỗi phiên dịch/giọng nói: ${event.data}');
      }
    }
  }

  Future<void> _processVoiceTranscript(
    String rawText, {
    bool fromXiaozhiStt = false,
  }) async {
    if (!mounted) return;
    final conversationProvider = Provider.of<ConversationProvider>(
      context,
      listen: false,
    );

    // Trong phiên dịch, KHÔNG normalize câu tiếng Trung bằng luật tiếng Việt.
    // Ngôn ngữ được khóa theo lượt. Nhánh Xiaozhi ASR chỉ là fallback.
    final text = _liveInterpreterMode
        ? rawText.trim()
        : VietnameseTranscriptNormalizer.normalize(rawText).normalized.trim();
    if (text.isEmpty) {
      _xiaozhiService?.discardResponseGate();
      return;
    }

    if (await _handleInterpreterVoiceCommand(text, conversationProvider)) {
      _xiaozhiService?.discardResponseGate();
      return;
    }
    if (_liveInterpreterMode) {
      _xiaozhiService?.discardResponseGate();
      await _handleLiveInterpreterTurn(text, conversationProvider);
      return;
    }

    await conversationProvider.addMessage(
      conversationId: widget.conversation.id,
      role: MessageRole.user,
      content: text,
    );
    _scrollToBottom();

    if (await _handleLocalDeviceInfo(text, conversationProvider)) {
      _xiaozhiService?.discardResponseGate();
      return;
    }
    if (await _handleRealtimeTool(text, conversationProvider)) {
      _xiaozhiService?.discardResponseGate();
      return;
    }

    // Đây là hội thoại Agent thật. Chỉ bây giờ mới mở response gate để text
    // và audio Agent được phép đi ra. Nhờ vậy local tool không còn chạy đua
    // với `% gold_price...`, `% search_knowledge...` từ cloud.
    await _xiaozhiService?.releaseResponseGate();
    return;
  }

  Future<bool> _handleRealtimeTool(
    String text,
    ConversationProvider conversationProvider,
  ) async {
    // v4: Realtime Tool Engine được chạy TRƯỚC Agent. Những câu về thời tiết,
    // tỷ giá, crypto, tin tức, xổ số… không còn bị đẩy bừa lên Xiaozhi.
    final toolResult = await _toolEngine.handle(text);
    if (toolResult != null) {
      _pendingOnlineMusicSearch = false;
      _xiaozhiService?.discardResponseGate();
      await _xiaozhiService?.interruptResponse();
      final message = toolResult.success
          ? toolResult.summary
          : (toolResult.userMessage ?? toolResult.summary);
      await conversationProvider.addMessage(
        conversationId: widget.conversation.id,
        role: MessageRole.assistant,
        content: message,
      );
      _scrollToBottom();
      await _speakInterpreter(message, 'vi-VN');
      return true;
    }

    // Music vẫn là engine riêng vì nó cần mở trình phát in-app.
    final result = await _realtimeTools.handle(
      text,
      forceMusic: _pendingOnlineMusicSearch,
    );
    if (result == null) return false;

    _xiaozhiService?.discardResponseGate();
    _pendingOnlineMusicSearch =
        result.kind == RealtimeToolKind.music && result.requiresFollowUp;
    await _xiaozhiService?.interruptResponse();

    await conversationProvider.addMessage(
      conversationId: widget.conversation.id,
      role: MessageRole.assistant,
      content: result.text,
    );
    _scrollToBottom();
    await _speakInterpreter(result.text, 'vi-VN');

    if (result.kind == RealtimeToolKind.music &&
        result.externalUri != null &&
        mounted &&
        !result.requiresFollowUp) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MusicPlayerScreen(
            initialUri: result.externalUri!,
            title: result.text,
          ),
        ),
      );
    }
    return true;
  }

  Future<bool> _handleLocalDeviceInfo(
    String text,
    ConversationProvider conversationProvider,
  ) async {
    final normalized = text.toLowerCase();
    final asksDevice = RegExp(
      r'(mã\s*thiết\s*bị|device\s*-?\s*id|client\s*-?\s*id|địa\s*chỉ\s*mac|mac\s*address|thông\s*tin\s*thiết\s*bị)',
      caseSensitive: false,
    ).hasMatch(normalized);
    if (!asksDevice || widget.conversation.type != ConversationType.xiaozhi) {
      return false;
    }

    final provider = Provider.of<ConfigProvider>(context, listen: false);
    XiaozhiConfig? config;
    for (final item in provider.xiaozhiConfigs) {
      if (item.id == widget.conversation.configId) {
        config = item;
        break;
      }
    }
    config ??= provider.xiaozhiConfigs.isNotEmpty ? provider.xiaozhiConfigs.first : null;
    if (config == null) return false;

    _xiaozhiService?.discardResponseGate();
    await _xiaozhiService?.interruptResponse();
    final connected = _xiaozhiService?.isConnected == true ? 'Đã kết nối' : 'Chưa kết nối';
    final answer = 'Thông tin thiết bị hiện tại:\n'
        'Device-ID/MAC: ${config.macAddress}\n'
        'Client-ID: ${config.clientId}\n'
        'WebSocket: ${config.websocketUrl}\n'
        'Trạng thái: $connected';
    await conversationProvider.addMessage(
      conversationId: widget.conversation.id,
      role: MessageRole.assistant,
      content: answer,
    );
    _scrollToBottom();
    await _speakInterpreter(answer, 'vi-VN');
    return true;
  }

  Future<bool> _handleInterpreterVoiceCommand(
    String text,
    ConversationProvider conversationProvider,
  ) async {
    final normalized = text.toLowerCase().replaceAll(RegExp(r'[^a-zà-ỹ\s]'), ' ');
    final wantsStop = normalized.contains('tắt phiên dịch') ||
        normalized.contains('dừng phiên dịch') ||
        normalized.contains('thoát phiên dịch') ||
        normalized.contains('kết thúc phiên dịch');

    if (wantsStop) {
      await _xiaozhiService?.interruptResponse();
      if (mounted) {
        setState(() {
          _liveInterpreterMode = false;
          _interpreterBusy = false;
          _interpreterWaitingForXiaozhi = false;
          _interpreterTurn.resetToA();
        });
      }
      await conversationProvider.addMessage(
        conversationId: widget.conversation.id,
        role: MessageRole.user,
        content: text,
      );
      await conversationProvider.addMessage(
        conversationId: widget.conversation.id,
        role: MessageRole.assistant,
        content: 'Đã tắt phiên dịch trực tiếp.',
      );
      await _speakInterpreter('Đã tắt phiên dịch trực tiếp.', 'vi-VN');
      return true;
    }

    final asksInterpreter = normalized.contains('phiên dịch') ||
        normalized.contains('dịch trực tiếp') ||
        normalized.contains('chế độ dịch');
    if (!asksInterpreter) return false;

    final pair = _parseInterpreterPair(normalized);
    if (pair != null) {
      _interpreterLanguageA = pair.$1;
      _interpreterLocaleA = pair.$2;
      _interpreterLanguageB = pair.$3;
      _interpreterLocaleB = pair.$4;
      _interpreterTurn.updatePair(
        newLanguageA: _interpreterLanguageA,
        newLocaleA: _interpreterLocaleA,
        newLanguageB: _interpreterLanguageB,
        newLocaleB: _interpreterLocaleB,
      );
    } else {
      _interpreterTurn.resetToA();
    }

    await _xiaozhiService?.interruptResponse();
    if (mounted) {
      setState(() => _liveInterpreterMode = true);
    }
    await conversationProvider.addMessage(
      conversationId: widget.conversation.id,
      role: MessageRole.user,
      content: text,
    );
    final confirmation =
        'Đã bật phiên dịch trực tiếp $_interpreterLanguageA ↔ $_interpreterLanguageB. '
        'Lượt đầu mình nghe $_interpreterLanguageA, dịch và nói $_interpreterLanguageB. '
        'Sau đó tự chuyển sang lượt $_interpreterLanguageB. Nếu cần, bấm Đổi lượt.';
    await conversationProvider.addMessage(
      conversationId: widget.conversation.id,
      role: MessageRole.assistant,
      content: confirmation,
    );
    await _speakInterpreter(confirmation, 'vi-VN');
    return true;
  }

  (String, String, String, String)? _parseInterpreterPair(String text) {
    const languages = <String, (String, String)>{
      'việt': ('Tiếng Việt', 'vi-VN'),
      'vietnam': ('Tiếng Việt', 'vi-VN'),
      'anh': ('English', 'en-US'),
      'english': ('English', 'en-US'),
      'trung': ('中文', 'zh-CN'),
      'chinese': ('中文', 'zh-CN'),
      'nhật': ('日本語', 'ja-JP'),
      'japanese': ('日本語', 'ja-JP'),
      'hàn': ('한국어', 'ko-KR'),
      'korean': ('한국어', 'ko-KR'),
      'pháp': ('Français', 'fr-FR'),
      'french': ('Français', 'fr-FR'),
      'đức': ('Deutsch', 'de-DE'),
      'german': ('Deutsch', 'de-DE'),
      'tây ban nha': ('Español', 'es-ES'),
      'spanish': ('Español', 'es-ES'),
      'thái': ('ไทย', 'th-TH'),
      'thai': ('ไทย', 'th-TH'),
    };

    final found = <(String, String)>[];
    for (final entry in languages.entries) {
      if (text.contains(entry.key) && !found.contains(entry.value)) {
        found.add(entry.value);
      }
    }
    if (found.length >= 2) {
      return (found[0].$1, found[0].$2, found[1].$1, found[1].$2);
    }
    // Người dùng chỉ nói "mở phiên dịch" thì mặc định Việt ↔ Anh.
    return ('Tiếng Việt', 'vi-VN', 'English', 'en-US');
  }

  Future<void> _handleLiveInterpreterTurn(
    String text,
    ConversationProvider conversationProvider,
  ) async {
    if (_interpreterBusy) return;
    final provider = Provider.of<ConfigProvider>(context, listen: false);
    final translation = TranslationService(provider);
    if (!translation.isAvailable) {
      _showCustomSnackbar(
        'Chưa có backend dịch khả dụng. Android sẽ dùng ML Kit trên máy; bạn cũng có thể cấu hình MiniMax/Dify.',
      );
      return;
    }

    final sourceLanguage = _interpreterTurn.sourceLanguage;
    final targetLanguage = _interpreterTurn.targetLanguage;
    final targetLocale = _interpreterTurn.targetLocale;

    _interpreterBusy = true;
    _interpreterWaitingForXiaozhi = false;
    if (mounted) setState(() {});
    try {
      await _xiaozhiService?.interruptResponse();
      await conversationProvider.addMessage(
        conversationId: widget.conversation.id,
        role: MessageRole.user,
        content: text,
      );

      final result = await translation.translate(
        text: text,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        naturalSpeech: true,
        existingXiaozhi: _xiaozhiService,
      );

      if (!mounted) return;
      await conversationProvider.addMessage(
        conversationId: widget.conversation.id,
        role: MessageRole.assistant,
        content: result.text,
      );

      // v3.3 luôn phát bản dịch bằng TTS của điện thoại với locale đích.
      // Xiaozhi backend được gọi ở silent mode trong TranslationService.
      await _speakInterpreter(result.text, targetLocale);
      _interpreterTurn.nextTurn();
      if (mounted) setState(() {});
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      await conversationProvider.addMessage(
        conversationId: widget.conversation.id,
        role: MessageRole.assistant,
        content:
            'Không thể phiên dịch lượt $sourceLanguage → $targetLanguage. Hãy nói lại chậm và rõ hơn.',
      );
      _showCustomSnackbar('Phiên dịch thất bại: $e');
    } finally {
      _interpreterBusy = false;
      _interpreterWaitingForXiaozhi = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _speakInterpreter(String text, String locale) async {
    if (text.trim().isEmpty) return;
    try {
      final available = await _speechOutput.canSpeakLocale(locale);
      if (!available) {
        if (mounted) {
          _showCustomSnackbar(
            'Máy chưa cài giọng TTS $locale. Hãy cài dữ liệu giọng nói này trong Android.',
          );
        }
        return;
      }
      await _speechOutput.speak(text, locale: locale);
    } catch (e) {
      print('Không thể phát TTS $locale: $e');
      if (mounted) _showCustomSnackbar('Không phát được giọng $locale.');
    }
  }

  Future<void> _showInterpreterPicker() async {
    if (widget.conversation.type != ConversationType.xiaozhi) return;
    final pairs = <(String, String, String, String)>[
      ('Tiếng Việt', 'vi-VN', 'English', 'en-US'),
      ('Tiếng Việt', 'vi-VN', '中文', 'zh-CN'),
      ('Tiếng Việt', 'vi-VN', '日本語', 'ja-JP'),
      ('Tiếng Việt', 'vi-VN', '한국어', 'ko-KR'),
      ('Tiếng Việt', 'vi-VN', 'Français', 'fr-FR'),
    ];
    final selected = await showModalBottomSheet<(String, String, String, String)>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Phiên dịch trực tiếp', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Chọn cặp ngôn ngữ. Bạn cũng có thể nói “mở phiên dịch Anh Việt”.'),
            ),
            ...pairs.map(
              (pair) => ListTile(
                leading: const Icon(Icons.translate_rounded),
                title: Text('${pair.$1} ↔ ${pair.$3}'),
                onTap: () => Navigator.pop(context, pair),
              ),
            ),
            if (_liveInterpreterMode)
              ListTile(
                leading: const Icon(Icons.stop_circle_outlined, color: Colors.red),
                title: const Text('Tắt phiên dịch trực tiếp'),
                onTap: () => Navigator.pop(context, ('', '', '', '')),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    if (selected.$1.isEmpty) {
      setState(() {
        _liveInterpreterMode = false;
        _interpreterTurn.resetToA();
      });
      await _xiaozhiService?.interruptResponse();
      return;
    }
    setState(() {
      _interpreterLanguageA = selected.$1;
      _interpreterLocaleA = selected.$2;
      _interpreterLanguageB = selected.$3;
      _interpreterLocaleB = selected.$4;
      _interpreterTurn.updatePair(
        newLanguageA: _interpreterLanguageA,
        newLocaleA: _interpreterLocaleA,
        newLanguageB: _interpreterLanguageB,
        newLocaleB: _interpreterLocaleB,
      );
      _liveInterpreterMode = true;
    });
    await _xiaozhiService?.interruptResponse();
  }

  // 初始化 DifyService
  Future<void> _initDifyService() async {
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    final String? configId = widget.conversation.configId;
    DifyConfig? difyConfig;

    if (configId != null && configId.isNotEmpty) {
      difyConfig =
          configProvider.difyConfigs
              .where((config) => config.id == configId)
              .firstOrNull;
    }

    if (difyConfig == null) {
      if (configProvider.difyConfigs.isEmpty) {
        throw Exception("Chưa cấu hình Dify. Hãy cấu hình Dify API trong Cài đặt trước");
      }
      difyConfig = configProvider.difyConfigs.first;
    }

    _difyService = await DifyService.create(
      apiKey: difyConfig.apiKey,
      apiUrl: difyConfig.apiUrl,
    );
  }

  // 初始化 MiniMaxService
  void _initMiniMaxService() {
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    final String? configId = widget.conversation.configId;
    MiniMaxConfig? minimaxConfig;

    if (configId != null && configId.isNotEmpty) {
      minimaxConfig =
          configProvider.minimaxConfigs
              .where((config) => config.id == configId)
              .firstOrNull;
    }

    if (minimaxConfig == null) {
      if (configProvider.minimaxConfigs.isEmpty) {
        throw Exception("Chưa cấu hình MiniMax. Hãy cấu hình MiniMax API trong Cài đặt trước");
      }
      minimaxConfig = configProvider.minimaxConfigs.first;
    }

    _minimaxService = MiniMaxService(
      apiKey: minimaxConfig.apiKey,
      model: minimaxConfig.model,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 确保状态栏Cài đặt正确
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        toolbarHeight: 70,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        actions: [
          if (widget.conversation.type == ConversationType.dify ||
              widget.conversation.type == ConversationType.minimax)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.black, size: 24),
              tooltip: 'Bắt đầu cuộc trò chuyện mới',
              onPressed: _resetConversation,
            ),
          if (widget.conversation.type == ConversationType.xiaozhi)
            IconButton(
              tooltip: _liveInterpreterMode
                  ? 'Phiên dịch đang bật'
                  : 'Bật phiên dịch trực tiếp',
              onPressed: _showInterpreterPicker,
              icon: Icon(
                Icons.translate_rounded,
                color: _liveInterpreterMode ? Colors.deepPurple : Colors.black,
              ),
            ),
          if (widget.conversation.type == ConversationType.xiaozhi)
            Container(
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _navigateToVoiceCall,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.phone, color: Colors.black, size: 16),
                    ),
                  ),
                ),
              ),
            ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 26),
          onPressed: () {
            // 返回前停止播放
            if (_xiaozhiService != null) {
              _xiaozhiService!.stopPlayback();
            }
            Navigator.of(context).pop();
          },
        ),
        title:
            widget.conversation.type == ConversationType.xiaozhi
                ? Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 0,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.grey.shade700,
                        child: const Icon(
                          Icons.mic,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.conversation.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 1,
                                spreadRadius: 0,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Text(
                            'Giọng nói',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ),
                        ],
                      ),
                    ),
                  ],
                )
                : Consumer<ConfigProvider>(
                  builder: (context, configProvider, child) {
                    final String? configId = widget.conversation.configId;
                    String configName = widget.conversation.title;
                    final bool isMinimax =
                        widget.conversation.type == ConversationType.minimax;
                    final MaterialColor themeColor =
                        isMinimax ? Colors.teal : Colors.blue;

                    // 查找此Cuộc trò chuyện对应的cấu hình
                    if (configId != null && configId.isNotEmpty) {
                      if (isMinimax) {
                        final minimaxConfig =
                            configProvider.minimaxConfigs
                                .where((config) => config.id == configId)
                                .firstOrNull;
                        if (minimaxConfig != null) {
                          configName = minimaxConfig.name;
                        }
                      } else {
                        final difyConfig =
                            configProvider.difyConfigs
                                .where((config) => config.id == configId)
                                .firstOrNull;
                        if (difyConfig != null) {
                          configName = difyConfig.name;
                        }
                      }
                    }

                    return Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: themeColor.withOpacity(0.3),
                                blurRadius: 8,
                                spreadRadius: 0,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: themeColor.shade400,
                            child: Icon(
                              isMinimax
                                  ? Icons.auto_awesome
                                  : Icons.chat_bubble_outline,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                configName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: themeColor.shade50,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.03),
                                    blurRadius: 1,
                                    spreadRadius: 0,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Text(
                                isMinimax ? 'MiniMax' : 'Văn bản',
                                style: TextStyle(
                                  color: themeColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
      ),
      body: Column(
        children: [
          if (widget.conversation.type == ConversationType.xiaozhi)
            _buildXiaozhiInfo(),
          if (_liveInterpreterMode) _buildInterpreterBanner(),
          Expanded(child: _buildMessageList()),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildXiaozhiInfo() {
    final configProvider = Provider.of<ConfigProvider>(context);
    final xiaozhiConfig = configProvider.xiaozhiConfigs.firstWhere(
      (config) => config.id == widget.conversation.configId,
      orElse: () => XiaozhiConfig(
        id: '',
        name: 'Dịch vụ không xác định',
        websocketUrl: '',
        macAddress: '',
        clientId: '',
        token: '',
      ),
    );

    final isConnected = _xiaozhiService?.isConnected ?? false;
    final statusColor = isConnected ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withOpacity(0.35),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isConnected ? 'Đã kết nối' : 'Chưa kết nối',
                style: TextStyle(
                  fontSize: 13,
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  xiaozhiConfig.websocketUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ),
            ],
          ),
          if (xiaozhiConfig.macAddress.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.devices_rounded, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Device: ${xiaozhiConfig.macAddress}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInterpreterBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2EEFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD7CCFF)),
      ),
      child: Row(
        children: [
          const Icon(Icons.translate_rounded, color: Color(0xFF6750A4)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đang nghe: ${_interpreterTurn.sourceLanguage} → nói ${_interpreterTurn.targetLanguage}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  _interpreterBusy
                      ? 'Đang dịch và phát bằng ${_interpreterTurn.targetLocale}…'
                      : 'ASR khóa ${_interpreterTurn.sourceLocale}. Dịch xong sẽ tự chuyển lượt.',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _interpreterBusy || _isRecording
                ? null
                : () {
                    setState(() {
                      _interpreterTurn.swapTurn();
                    });
                  },
            child: const Text('Đổi lượt'),
          ),
          IconButton(
            tooltip: 'Tắt phiên dịch',
            onPressed: () async {
              setState(() {
                _liveInterpreterMode = false;
                _interpreterTurn.resetToA();
              });
              await _nativeSpeech.cancel();
              await _xiaozhiService?.interruptResponse();
            },
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return Consumer<ConversationProvider>(
      builder: (context, provider, child) {
        final messages = provider.getMessages(widget.conversation.id);

        if (messages.isEmpty) {
          return Center(
            child: Text(
              'Bắt đầu cuộc trò chuyện mới',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          reverse: true,
          itemCount: messages.length + (_isLoading ? 1 : 0),
          cacheExtent: 1000.0,
          addRepaintBoundaries: true,
          addAutomaticKeepAlives: true,
          physics: const ClampingScrollPhysics(),
          itemBuilder: (context, index) {
            if (_isLoading && index == 0) {
              return MessageBubble(
                message: Message(
                  id: 'loading',
                  conversationId: '',
                  role: MessageRole.assistant,
                  content: 'Đang suy nghĩ...',
                  timestamp: DateTime.now(),
                ),
                isThinking: true,
                conversationType: widget.conversation.type,
              );
            }

            final adjustedIndex = _isLoading ? index - 1 : index;
            final message = messages[messages.length - 1 - adjustedIndex];

            return RepaintBoundary(
              child: MessageBubble(
                key: ValueKey(message.id),
                message: message,
                conversationType: widget.conversation.type,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInputArea() {
    final bool hasText = _textController.text.trim().isNotEmpty;

    // 根据状态决定显示Văn bản输入还是Giọng nói输入
    if (_isVoiceInputMode &&
        widget.conversation.type == ConversationType.xiaozhi) {
      return _buildVoiceInputArea();
    } else {
      return _buildTextInputArea(hasText);
    }
  }

  // Văn bản输入区域
  Widget _buildTextInputArea(bool hasText) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 16,
        top: 16,
        right: 16,
        bottom: 16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7F9),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.07),
                  blurRadius: 8,
                  spreadRadius: 0,
                  offset: const Offset(0, 3),
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.8),
                  blurRadius: 5,
                  spreadRadius: 0,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Nhập tin nhắn...',
                      hintStyle: TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 16,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                    ),
                    style: const TextStyle(
                      color: Color(0xFF1F2937),
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (widget.conversation.type == ConversationType.dify &&
                    !hasText)
                  IconButton(
                    icon: const Icon(
                      Icons.add_circle_outline,
                      color: Color(0xFF9CA3AF), // 使用紫色，与Xiaozhi的麦克风按钮风格一致
                      size: 24,
                    ),
                    onPressed: _showImagePickerOptions,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    constraints: const BoxConstraints(),
                    splashRadius: 22,
                  ),
                _buildSendButton(hasText),
                if (widget.conversation.type == ConversationType.xiaozhi &&
                    !hasText)
                  IconButton(
                    icon: const Icon(
                      Icons.mic,
                      color: Color.fromARGB(255, 108, 108, 112),
                      size: 24,
                    ),
                    onPressed: () {
                      setState(() {
                        _isVoiceInputMode = true;
                      });
                    },
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    constraints: const BoxConstraints(),
                    splashRadius: 22,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Giọng nói输入区域
  Widget _buildVoiceInputArea() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 16,
        top: 16,
        right: 16,
        bottom: 16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: GestureDetector(
              onLongPressStart: (details) {
                setState(() {
                  _isRecording = true;
                  _isCancelling = false;
                  _startDragY = details.globalPosition.dy;
                });
                _startRecording();
                _startWaveAnimation();
              },
              onLongPressMoveUpdate: (details) {
                // 计算垂直移动距离
                final double dragDistance =
                    _startDragY - details.globalPosition.dy;

                // 如果上滑超过阈值，标记为Hủy状态
                if (dragDistance > _cancelThreshold && !_isCancelling) {
                  setState(() {
                    _isCancelling = true;
                  });
                  // 震动反馈
                  HapticFeedback.mediumImpact();
                } else if (dragDistance <= _cancelThreshold && _isCancelling) {
                  setState(() {
                    _isCancelling = false;
                  });
                  // 震动反馈
                  HapticFeedback.lightImpact();
                }
              },
              onLongPressEnd: (details) {
                final wasRecording = _isRecording;
                final wasCancelling = _isCancelling;

                setState(() {
                  _isRecording = false;
                });

                _stopWaveAnimation();

                if (wasRecording) {
                  if (wasCancelling) {
                    _cancelRecording();
                  } else {
                    _stopRecording();
                  }
                }
              },
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  color:
                      _isRecording
                          ? _isCancelling
                              ? Colors.red.shade50
                              : Colors.blue.shade50
                          : const Color(0xFFF5F7F9),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.07),
                      blurRadius: 8,
                      spreadRadius: 0,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 波纹动画效果
                    if (_isRecording && !_isCancelling)
                      _buildWaveAnimationIndicator(),

                    // 文字提示
                    Center(
                      child: Text(
                        _isRecording
                            ? _isCancelling
                                ? "Thả tay để hủy gửi"
                                : "Thả để gửi, vuốt lên để hủy"
                            : "Nhấn giữ để nói",
                        style: TextStyle(
                          color:
                              _isRecording
                                  ? _isCancelling
                                      ? Colors.red
                                      : Colors.blue.shade700
                                  : const Color.fromARGB(255, 9, 9, 9),
                          fontSize: 16,
                          fontWeight:
                              _isRecording
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 键盘按钮 (切换回Văn bảnChế độ)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.8),
                  blurRadius: 4,
                  spreadRadius: 0,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              shape: CircleBorder(),
              child: InkWell(
                borderRadius: BorderRadius.circular(25),
                onTap: () {
                  // 如果正在录音，先Hủy录音
                  if (_isRecording) {
                    _cancelRecording();
                    _stopWaveAnimation();
                  }
                  // 切换回Văn bản输入Chế độ
                  setState(() {
                    _isVoiceInputMode = false;
                    _isRecording = false;
                    _isCancelling = false;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Icon(
                    Icons.keyboard,
                    color: Colors.grey.shade700,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendButton(bool hasText) {
    return IconButton(
      key: const ValueKey('send_button'),
      icon: Icon(
        Icons.send_rounded,
        color: hasText ? Colors.black : const Color(0xFFC4C9D2),
        size: 24,
      ),
      onPressed: hasText ? _sendMessage : null,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      constraints: const BoxConstraints(),
      splashRadius: 22,
    );
  }

  // Bắt đầu nhận giọng nói. v3.3 ưu tiên native speech có khóa locale.
  void _startRecording() async {
    if (widget.conversation.type != ConversationType.xiaozhi ||
        _xiaozhiService == null) {
      _showCustomSnackbar('Tính năng giọng nói chỉ hỗ trợ cuộc trò chuyện Xiaozhi');
      setState(() => _isVoiceInputMode = false);
      return;
    }

    try {
      HapticFeedback.mediumImpact();
      await _speechOutput.stop();
      await _xiaozhiService?.stopPlayback();

      final requestedLocale =
          _liveInterpreterMode ? _interpreterTurn.sourceLocale : 'vi-VN';

      if (_liveInterpreterMode) {
        // Phiên dịch bắt buộc native ASR khóa locale theo từng lượt.
        final nativeReady = await _nativeSpeech.initialize();
        if (!nativeReady) {
          throw Exception(
            'ASR hệ thống chưa sẵn sàng cho phiên dịch. Hãy kiểm tra dịch vụ nhận dạng giọng nói Android.',
          );
        }
        _nativePartialTranscript = '';
        _usingNativeSpeech = await _nativeSpeech.start(
          localeId: requestedLocale,
          onResult: (words, isFinal) {
            if (!mounted || words.trim().isEmpty) return;
            _nativePartialTranscript = words.trim();
            if (isFinal) setState(() {});
          },
        );
        if (!_usingNativeSpeech) {
          throw Exception(
            'Máy chưa mở được ASR $requestedLocale. Hãy cài ngôn ngữ nhận dạng tương ứng trong Android rồi thử lại.',
          );
        }
      } else {
        // Chat Xiaozhi bình thường vẫn gửi AUDIO theo protocol chính thức,
        // nhưng khóa phản hồi cloud tạm thời cho tới khi STT được Router phân
        // loại. Điều này giữ chất lượng Agent mà không để Agent tranh local tool.
        _usingNativeSpeech = false;
        _xiaozhiService!.beginResponseGate();
        await _xiaozhiService!.startListening();
      }
    } catch (e) {
      _xiaozhiService?.discardResponseGate();
      print('Không thể bắt đầu ghi âm: $e');
      _showCustomSnackbar('Không thể bắt đầu ghi âm: $e');
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isVoiceInputMode = false;
          _usingNativeSpeech = false;
        });
      }
    }
  }

  // Dừng nhận dạng rồi xử lý transcript. Native ASR trả câu về app trước,
  // vì vậy tool online và phiên dịch có thể chạy mà không phụ thuộc ASR cloud.
  void _stopRecording() async {
    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _isRecording = false;
        });
      }
      HapticFeedback.mediumImpact();

      if (_usingNativeSpeech) {
        final text = (await _nativeSpeech.stopAndGetText()).trim();
        _usingNativeSpeech = false;
        _nativePartialTranscript = '';
        if (text.isEmpty) {
          _showCustomSnackbar('Không nghe rõ câu nói. Hãy thử lại gần micro hơn.');
        } else {
          await _processVoiceTranscript(text);
        }
      } else {
        // Fallback: server sẽ phát event STT và _handleXiaozhiMessage xử lý.
        await _xiaozhiService?.stopListening();
      }
      _scrollToBottom();
    } catch (e) {
      print('Dừng ghi âm thất bại: $e');
      _showCustomSnackbar('Gửi giọng nói thất bại: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Hủy ghi âm
  void _cancelRecording() async {
    try {
      if (mounted) setState(() => _isRecording = false);
      HapticFeedback.heavyImpact();
      if (_usingNativeSpeech) {
        await _nativeSpeech.cancel();
        _usingNativeSpeech = false;
        _nativePartialTranscript = '';
      } else {
        _xiaozhiService?.discardResponseGate();
        await _xiaozhiService?.abortListening();
      }
      _showCustomSnackbar('Đã hủy gửi');
    } catch (e) {
      print('Hủy ghi âm thất bại: $e');
    }
  }

  // 显示自定义Snackbar
  void _showCustomSnackbar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final snackBar = SnackBar(
      content: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.black.withOpacity(0.7),
      duration: const Duration(seconds: 2),
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).size.height - 120,
        left: 16,
        right: 16,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  void _resetConversation() async {
    // 给用户一个清晰的提示
    _showCustomSnackbar('Đang bắt đầu cuộc trò chuyện mới...');

    final conversationProvider = Provider.of<ConversationProvider>(
      context,
      listen: false,
    );

    if (widget.conversation.type == ConversationType.minimax) {
      final sessionId = widget.conversation.id;
      _minimaxService?.clearConversation(sessionId);

      await conversationProvider.addMessage(
        conversationId: widget.conversation.id,
        role: MessageRole.system,
        content: '--- Bắt đầu cuộc trò chuyện mới ---',
      );

      _showCustomSnackbar('Đã bắt đầu cuộc trò chuyện mới');
    } else if (_difyService != null) {
      // 使用Cuộc trò chuyện的ID作为sessionId，确保与发送Tin nhắn时使用相同的标识符
      final sessionId = widget.conversation.id;

      // 清除当前Cuộc trò chuyện的conversation_id
      await _difyService!.clearConversation(sessionId);

      // Thêm系统Tin nhắn表明这是一个新对话
      await conversationProvider.addMessage(
        conversationId: widget.conversation.id,
        role: MessageRole.system,
        content: '--- Bắt đầu cuộc trò chuyện mới ---',
      );

      _showCustomSnackbar('Đã bắt đầu cuộc trò chuyện mới');
    } else {
      _showCustomSnackbar('Chưa có cấu hình phù hợp để đặt lại cuộc trò chuyện');
    }
  }

  void _sendMessage() async {
    final message = _textController.text.trim();
    if (message.isEmpty || _isLoading) return;

    _textController.clear();

    final conversationProvider = Provider.of<ConversationProvider>(
      context,
      listen: false,
    );

    if (widget.conversation.type == ConversationType.xiaozhi) {
      if (await _handleInterpreterVoiceCommand(message, conversationProvider)) {
        _scrollToBottom();
        return;
      }
      if (_liveInterpreterMode) {
        await _handleLiveInterpreterTurn(message, conversationProvider);
        _scrollToBottom();
        return;
      }
    }

    // Add user message
    await conversationProvider.addMessage(
      conversationId: widget.conversation.id,
      role: MessageRole.user,
      content: message,
    );

    if (widget.conversation.type == ConversationType.xiaozhi &&
        await _handleLocalDeviceInfo(message, conversationProvider)) {
      _scrollToBottom();
      return;
    }

    if (widget.conversation.type == ConversationType.xiaozhi &&
        await _handleRealtimeTool(message, conversationProvider)) {
      _scrollToBottom();
      return;
    }

    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      if (widget.conversation.type == ConversationType.minimax) {
        if (_minimaxService == null) {
          _initMiniMaxService();
        }

        if (_minimaxService == null) {
          throw Exception("Chưa cấu hình MiniMax. Hãy cấu hình MiniMax API trong Cài đặt trước");
        }

        final sessionId = widget.conversation.id;

        final response = await _minimaxService!.sendMessage(
          message,
          sessionId: sessionId,
          forceNewConversation: false,
        );

        if (!mounted) return;

        await conversationProvider.addMessage(
          conversationId: widget.conversation.id,
          role: MessageRole.assistant,
          content: response,
        );
      } else if (widget.conversation.type == ConversationType.dify) {
        if (_difyService == null) {
          await _initDifyService();
        }

        if (_difyService == null) {
          throw Exception("Chưa cấu hình Dify. Hãy cấu hình Dify API trong Cài đặt trước");
        }

        // 使用Cuộc trò chuyện的ID作为sessionId，使每次请求保持相同的对话上下文
        final sessionId = widget.conversation.id;

        // 使用阻塞式响应
        final response = await _difyService!.sendMessage(
          message,
          sessionId: sessionId, // 使用一致的Cuộc trò chuyệnID
          // 永远不要在普通Tin nhắn中使用forceNewConversation，除非用户明确请求Bắt đầu cuộc trò chuyện mới
          forceNewConversation: false,
        );

        if (!mounted) return; // 再次检查组件是否还在widget树中

        // Thêm助手回复
        await conversationProvider.addMessage(
          conversationId: widget.conversation.id,
          role: MessageRole.assistant,
          content: response,
        );
      } else {
        // 确保服务Đã kết nối
        if (_xiaozhiService == null) {
          await _initXiaozhiService();
        } else if (!_xiaozhiService!.isConnected) {
          // 如果Chưa kết nối，尝试重新连接
          print('聊天屏幕: 服务Chưa kết nối，尝试重新连接');
          await _xiaozhiService!.connect();

          // 如果重连Thất bại，提示用户
          if (!_xiaozhiService!.isConnected) {
            throw Exception("Không thể kết nối dịch vụ Xiaozhi. Hãy kiểm tra mạng hoặc cấu hình dịch vụ");
          }

          // 刷新UI显示连接状态
          setState(() {});
        }

        // Protocol Xiaozhi chính thức tập trung vào audio/STT/TTS và không có
        // general text-chat frame. Không dùng listen/detect để giả lập text nữa.
        // Với tin gõ, ưu tiên backend API nếu người dùng đã cấu hình; nếu chưa
        // có thì hướng dẫn dùng mic thay vì chờ 15 giây rồi báo timeout.
        final provider = Provider.of<ConfigProvider>(context, listen: false);
        String? typedResponse;
        if (provider.minimaxConfigs.isNotEmpty) {
          final config = provider.minimaxConfigs.first;
          final service = MiniMaxService(apiKey: config.apiKey, model: config.model);
          typedResponse = await service.sendMessage(
            message,
            sessionId: widget.conversation.id,
            forceNewConversation: false,
          );
        } else if (provider.difyConfigs.isNotEmpty) {
          final config = provider.difyConfigs.first;
          final service = await DifyService.create(
            apiKey: config.apiKey,
            apiUrl: config.apiUrl,
          );
          typedResponse = await service.sendMessage(
            message,
            sessionId: widget.conversation.id,
            forceNewConversation: false,
          );
        }

        if (typedResponse != null && typedResponse.trim().isNotEmpty) {
          await conversationProvider.addMessage(
            conversationId: widget.conversation.id,
            role: MessageRole.assistant,
            content: typedResponse.trim(),
          );
        } else {
          await conversationProvider.addMessage(
            conversationId: widget.conversation.id,
            role: MessageRole.assistant,
            content: 'Máy chủ Xiaozhi hiện dùng luồng thoại chính thức. '
                'Hãy giữ mic để nói; nếu muốn chat bằng bàn phím, cấu hình MiniMax hoặc Dify trong Cài đặt.',
          );
        }
      }
    } catch (e) {
      print('聊天屏幕: 发送Tin nhắnLỗi: $e');

      if (!mounted) return;

      // Add error message
      await conversationProvider.addMessage(
        conversationId: widget.conversation.id,
        role: MessageRole.assistant,
        content: 'Đã xảy ra lỗi: ${e.toString()}',
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _navigateToVoiceCall() {
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    final xiaozhiConfig = configProvider.xiaozhiConfigs.firstWhere(
      (config) => config.id == widget.conversation.configId,
    );

    // 导航前停止当前音频播放
    if (_xiaozhiService != null) {
      _xiaozhiService!.stopPlayback();
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => VoiceCallScreen(
              conversation: widget.conversation,
              xiaozhiConfig: xiaozhiConfig,
            ),
      ),
    ).then((_) {
      // 页面返回后，确保重新初始化服务以恢复正常对话功能
      if (_xiaozhiService != null &&
          widget.conversation.type == ConversationType.xiaozhi) {
        // 重新连接服务
        _xiaozhiService!.connect();
      }
    });
  }

  // 启动波形动画
  void _startWaveAnimation() {
    _waveAnimationTimer?.cancel();
    // Chỉ điều khiển UI. Không stop TTS/ASR ở đây: onLongPressEnd gọi
    // _stopWaveAnimation() ngay trước _stopRecording(); nếu stop/cancel audio
    // tại đây sẽ tạo race làm mất câu TTS mới hoặc hủy native ASR trước khi
    // stopAndGetText() đọc transcript cuối.
    _waveAnimationTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      if (_isRecording && !_isCancelling) {
        setState(() {
          for (int i = 0; i < _waveHeights.length; i++) {
            _waveHeights[i] = 0.5 + _random.nextDouble() * 0.5;
          }
        });
      }
    });
  }

  // 停止波形动画
  void _stopWaveAnimation() {
    // Animation lifecycle không được phép sở hữu audio lifecycle. Audio được
    // dừng có await ở _startRecording/_cancelRecording hoặc hoàn tất ở
    // _stopRecording. Tách hai lifecycle để tránh lỗi lúc có tiếng lúc không.
    _waveAnimationTimer?.cancel();
    _waveAnimationTimer = null;
  }

  // 构建波形动画指示器
  Widget _buildWaveAnimationIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(
          16,
          (index) => AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 3,
            height: 20 * _waveHeights[index],
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.6),
              borderRadius: BorderRadius.circular(1.5),
            ),
            curve: Curves.easeInOut,
          ),
        ),
      ),
    );
  }

  // 显示图片选择器选项
  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      elevation: 20,
      barrierColor: Colors.black.withOpacity(0.5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部拖动条
              Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 1,
                      spreadRadius: 0,
                      offset: const Offset(0, 0.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Chọn từ thư viện选项
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 10,
                        spreadRadius: 0,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 6,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.1),
                              blurRadius: 4,
                              spreadRadius: 0,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.photo_library,
                          color: Colors.blue.shade600,
                          size: 24,
                        ),
                      ),
                      title: const Text(
                        'Chọn từ thư viện',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      subtitle: Text(
                        'Chọn ảnh có sẵn',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        _pickImage(true);
                      },
                    ),
                  ),
                ),
              ),

              // Chụp ảnh选项
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 10,
                        spreadRadius: 0,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 6,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.1),
                              blurRadius: 4,
                              spreadRadius: 0,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.camera_alt,
                          color: Colors.green.shade600,
                          size: 24,
                        ),
                      ),
                      title: const Text(
                        'Chụp ảnh',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      subtitle: Text(
                        'Chụp ảnh mới',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        _pickImage(false);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(bool fromGallery) async {
    if (widget.conversation.type != ConversationType.dify) {
      _showCustomSnackbar('Tải ảnh chỉ hỗ trợ cuộc trò chuyện Dify');
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      if (_difyService == null) {
        await _initDifyService();
      }

      if (_difyService == null) {
        throw Exception("Chưa cấu hình Dify. Hãy cấu hình Dify API trong Cài đặt trước");
      }

      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(
        source: fromGallery ? ImageSource.gallery : ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1500,
      );

      if (pickedFile == null) {
        _showCustomSnackbar('Đã hủy lựa chọn');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // 获取应用的文档目录
      final appDir = await getApplicationDocumentsDirectory();
      final conversationDir = Directory(
        '${appDir.path}/conversations/${widget.conversation.id}/images',
      );
      await conversationDir.create(recursive: true);

      // 生成唯一的文件名
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = pickedFile.path.split('.').last;
      final fileName = 'image_$timestamp.$extension';
      final localPath = '${conversationDir.path}/$fileName';

      // 复制图片到永久存储
      final File imageFile = File(pickedFile.path);
      await imageFile.copy(localPath);

      print('图片已Lưu到永久存储: $localPath');

      final sessionId = widget.conversation.id;

      // 在Tin nhắn列表中显示用户上传的图片Tin nhắn
      final conversationProvider = Provider.of<ConversationProvider>(
        context,
        listen: false,
      );

      // Thêm用户Tin nhắn，使用永久存储的路径
      await conversationProvider.addMessage(
        conversationId: widget.conversation.id,
        role: MessageRole.user,
        content: "[Đang tải ảnh lên...]",
        isImage: true,
        imageLocalPath: localPath,
      );

      _scrollToBottom();

      // 上传图片到Dify API
      final response = await _difyService!.uploadFile(File(localPath));

      if (response.containsKey('id')) {
        final fileId = response['id'];
        final messageContent = "";

        // 更新最后一条用户Tin nhắn为实际的图片Tin nhắn
        await conversationProvider.updateLastUserMessage(
          conversationId: widget.conversation.id,
          content: messageContent,
          fileId: fileId,
          isImage: true,
          imageLocalPath: localPath,
        );

        final textPrompt = "Phân tích ảnh này";
        final chatResponse = await _difyService!.sendMessage(
          textPrompt,
          sessionId: sessionId,
          fileIds: [fileId],
        );

        await conversationProvider.addMessage(
          conversationId: widget.conversation.id,
          role: MessageRole.assistant,
          content: chatResponse,
        );
      } else {
        throw Exception("Tải lên thành công nhưng máy chủ không trả về file ID: $response");
      }

      _showCustomSnackbar('Tải ảnh lên thành công');
    } catch (e) {
      print('Tải ảnh lên thất bại: $e');

      final conversationProvider = Provider.of<ConversationProvider>(
        context,
        listen: false,
      );
      await conversationProvider.addMessage(
        conversationId: widget.conversation.id,
        role: MessageRole.assistant,
        content: 'Tải ảnh lên thất bại: ${e.toString()}',
      );

      _showCustomSnackbar('Tải ảnh lên thất bại: ${e.toString()}');
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }
}
