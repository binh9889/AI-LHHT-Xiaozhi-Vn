import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:collection';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:opus_dart/opus_dart.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:audio_session/audio_session.dart';
import 'package:collection/collection.dart';
import 'package:flutter_pcm_player/flutter_pcm_player.dart';
import 'pcm_frame_buffer.dart';

/// 音频工具类，用于处理Opus音频编解码和录制播放
class AudioUtil {
  static const String TAG = "AudioUtil";
  static const int SAMPLE_RATE = 16000;
  static const int OUTPUT_SAMPLE_RATE = 16000;
  static const int CHANNELS = 1;
  static const int FRAME_DURATION = 60; // 毫秒

  static final AudioRecorder _audioRecorder = AudioRecorder();
  static ja.AudioPlayer? _player;
  static bool _isRecorderInitialized = false;
  static bool _isPlayerInitialized = false;
  static bool _isRecording = false;
  static bool _isPlaying = false;
  static int _downlinkSampleRate = SAMPLE_RATE;
  static int _playbackGeneration = 0;
  static int _cloudFramesPlayed = 0;
  static String _lastPlaybackError = '';
  static Future<void> _playbackTail = Future<void>.value();
  static Future<void>? _playerInitFuture;
  static final StreamController<Uint8List> _audioStreamController =
      StreamController<Uint8List>.broadcast();
  static String? _tempFilePath;
  static Timer? _audioProcessingTimer;
  static StreamSubscription<Uint8List>? _recorderStreamSubscription;
  static final PcmFrameBuffer _pcmFrames = PcmFrameBuffer(
    frameBytes: SAMPLE_RATE * FRAME_DURATION ~/ 1000 * 2,
  );

  // Opus相关
  static final _encoder = SimpleOpusEncoder(
    sampleRate: SAMPLE_RATE,
    channels: CHANNELS,
    application: Application.voip,
  );
  static SimpleOpusDecoder _decoder = SimpleOpusDecoder(
    sampleRate: SAMPLE_RATE,
    channels: CHANNELS,
  );

  static int get downlinkSampleRate => _downlinkSampleRate;
  static bool get isPlayerReady => _isPlayerInitialized && _pcmPlayer != null;
  static int get cloudFramesPlayed => _cloudFramesPlayed;
  static String get lastPlaybackError => _lastPlaybackError;

  /// Xiaozhi server có thể trả downlink 16 kHz hoặc 24 kHz trong server hello.
  /// Decoder phải bám đúng sample-rate đã thương lượng; sau decode app resample
  /// về OUTPUT_SAMPLE_RATE cho PCM player hiện tại.
  static Future<void> configureDownlinkSampleRate(int sampleRate) async {
    const supported = <int>{8000, 12000, 16000, 24000, 48000};
    final effective = supported.contains(sampleRate) ? sampleRate : SAMPLE_RATE;
    if (_downlinkSampleRate == effective) return;
    _downlinkSampleRate = effective;
    _decoder = SimpleOpusDecoder(sampleRate: effective, channels: CHANNELS);
    // KHÔNG stop/re-create PCM player tại server hello. Player luôn nhận PCM
    // 16 kHz sau bước resample; việc dừng player đúng lúc hello có thể chạy
    // đua với `tts:start` và làm mất toàn bộ câu Female Voice đầu tiên.
    print('$TAG: Downlink Opus sample rate = $effective Hz; playback output = $OUTPUT_SAMPLE_RATE Hz');
  }

  // FlutterPcmPlayer实例
  static FlutterPcmPlayer? _pcmPlayer;

  /// 获取音频流
  static Stream<Uint8List> get audioStream => _audioStreamController.stream;

  /// 初始化音频录制器
  static Future<void> initRecorder() async {
    if (_isRecorderInitialized) return;

    print('$TAG: 开始初始化录音器');

    // 更积极地请求所有可能需要的权限
    if (Platform.isAndroid) {
      print('$TAG: 请求Android所需的所有权限');
      Map<Permission, PermissionStatus> statuses =
          await [
            Permission.microphone,
            Permission.storage,
            Permission.manageExternalStorage,
            Permission.bluetooth,
            Permission.bluetoothConnect,
            Permission.bluetoothScan,
          ].request();

      print('$TAG: 权限状态:');
      statuses.forEach((permission, status) {
        print('$TAG: $permission: $status');
      });

      if (statuses[Permission.microphone] != PermissionStatus.granted) {
        print('$TAG: Quyền micrô bị từ chối');
        throw Exception('Cần quyền truy cập micrô');
      }
    } else {
      // iOS/其他平台只请求麦克风权限
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        print('$TAG: Quyền micrô bị từ chối');
        throw Exception('Cần quyền truy cập micrô');
      }
    }

    // 检查是否可用
    print('$TAG: 检查PCM16编码是否支持');
    final isAvailable = await _audioRecorder.isEncoderSupported(
      AudioEncoder.pcm16bits,
    );
    print('$TAG: PCM16编码支持状态: $isAvailable');

    // Cài đặt音频Chế độ - 参考Android原生实现
    print('$TAG: cấu hình音频Cuộc trò chuyện');
    final session = await AudioSession.instance;

    // 使用与原生Android实现更接近的cấu hình
    if (Platform.isAndroid) {
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
            flags: AndroidAudioFlags.audibilityEnforced,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientExclusive,
          androidWillPauseWhenDucked: false,
        ),
      );
    } else {
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
        ),
      );
      await session.setActive(true);
    }

    _isRecorderInitialized = true;
    print('$TAG: 录音器初始化Thành công');
  }

  /// 初始化音频播放器. Có guard để nhiều Opus frame đến cùng lúc không
  /// cùng re-create player và tự stop lẫn nhau.
  static Future<void> initPlayer() async {
    if (_isPlayerInitialized && _pcmPlayer != null) return;
    final inFlight = _playerInitFuture;
    if (inFlight != null) return inFlight;

    final completer = Completer<void>();
    _playerInitFuture = completer.future;
    try {
      print('$TAG: Khởi tạo PCM player cho Xiaozhi cloud TTS');
      final session = await AudioSession.instance;
      try {
        await session.setActive(true);
      } catch (e) {
        print('$TAG: Không lấy được audio focus trước playback: $e');
      }

      final old = _pcmPlayer;
      _pcmPlayer = null;
      _isPlayerInitialized = false;
      if (old != null) {
        try {
          await old.stop();
        } catch (_) {}
      }

      final player = FlutterPcmPlayer();
      await player.initialize();
      await player.play();
      _pcmPlayer = player;
      _isPlayerInitialized = true;
      _isPlaying = true;
      print('$TAG: PCM player sẵn sàng');
      completer.complete();
    } catch (e, st) {
      print('$TAG: PCM player khởi tạo thất bại: $e');
      print(st);
      _isPlayerInitialized = false;
      _isPlaying = false;
      if (!completer.isCompleted) completer.completeError(e, st);
      rethrow;
    } finally {
      _playerInitFuture = null;
    }
  }

  /// Chuẩn bị trước khi server gửi các binary Opus frame. Làm ở `tts:start`
  /// để frame đầu tiên không bị mất vì khởi tạo player quá muộn.
  static Future<void> beginCloudTts() async {
    try {
      await initPlayer();
      _isPlaying = true;
    } catch (e) {
      print('$TAG: Không chuẩn bị được cloud TTS: $e');
    }
  }

  /// WebSocket callbacks đến rất nhanh và không await nhau. Mọi frame phải đi
  /// qua một hàng đợi duy nhất, nếu không nhiều frame đầu có thể đồng thời gọi
  /// initPlayer() rồi stop/re-create player làm cả câu bị im lặng.
  static Future<void> playOpusData(Uint8List opusData) {
    if (opusData.isEmpty) return Future<void>.value();
    final generation = _playbackGeneration;
    _playbackTail = _playbackTail.then((_) async {
      if (generation != _playbackGeneration) return;
      await _playOpusFrame(opusData);
    }).catchError((Object e, StackTrace st) {
      print('$TAG: Hàng đợi playback lỗi: $e');
      print(st);
    });
    return _playbackTail;
  }

  static Future<void> _playOpusFrame(Uint8List opusData) async {
    try {
      await initPlayer();
      final Int16List decoded = _decoder.decode(input: opusData);
      final Int16List pcmData = _downlinkSampleRate == OUTPUT_SAMPLE_RATE
          ? decoded
          : _resampleLinear(decoded, _downlinkSampleRate, OUTPUT_SAMPLE_RATE);

      final Uint8List pcmBytes = Uint8List(pcmData.length * 2);
      final bytes = ByteData.view(pcmBytes.buffer);
      for (int i = 0; i < pcmData.length; i++) {
        bytes.setInt16(i * 2, pcmData[i], Endian.little);
      }
      final player = _pcmPlayer;
      if (player != null) {
        await player.feed(pcmBytes);
        _cloudFramesPlayed++;
        _lastPlaybackError = '';
        _isPlaying = true;
      } else {
        _lastPlaybackError = 'PCM player null sau init';
      }
    } catch (e, st) {
      _lastPlaybackError = '$e';
      print('$TAG: Phát Opus cloud thất bại: $e');
      print(st);
      // Không stop/re-init ngay trong cùng frame vì sẽ phá cả queue. Frame sau
      // sẽ tự init lại nếu player thực sự không còn dùng được.
      _isPlayerInitialized = false;
      _isPlaying = false;
    }
  }

  static Int16List _resampleLinear(Int16List input, int fromRate, int toRate) {
    if (input.isEmpty || fromRate <= 0 || toRate <= 0 || fromRate == toRate) {
      return input;
    }
    final outLength = ((input.length * toRate) / fromRate).round();
    if (outLength <= 1) return Int16List.fromList(input);
    final output = Int16List(outLength);
    final scale = fromRate / toRate;
    for (var i = 0; i < outLength; i++) {
      final sourcePos = i * scale;
      final left = sourcePos.floor().clamp(0, input.length - 1).toInt();
      final right = (left + 1).clamp(0, input.length - 1).toInt();
      final frac = sourcePos - left;
      final value = input[left] + (input[right] - input[left]) * frac;
      output[i] = value.round().clamp(-32768, 32767).toInt();
    }
    return output;
  }

  /// `tts:stop` chỉ đánh dấu hết câu. Không stop player lập tức vì vẫn có thể
  /// còn PCM đã feed trong native buffer.
  static void endCloudTts() {
    _isPlaying = false;
  }

  /// 停止播放
  static Future<void> stopPlaying() async {
    _playbackGeneration++;
    final player = _pcmPlayer;
    _pcmPlayer = null;
    _isPlayerInitialized = false;
    _isPlaying = false;
    if (player != null) {
      try {
        await player.stop();
        print('$TAG: Player đã dừng');
      } catch (e) {
        print('$TAG: Dừng player thất bại: $e');
      }
    }
  }

  /// 释放资源
  static Future<void> dispose() async {
    await _recorderStreamSubscription?.cancel();
    _recorderStreamSubscription = null;
    _pcmFrames.clear();
    _audioStreamController.close();
    print('$TAG: 资源已释放');
  }

  /// 开始录音
  static Future<void> startRecording() async {
    if (!_isRecorderInitialized) {
      await initRecorder();
    }

    if (_isRecording) return;

    try {
      print('$TAG: 尝试启动录音');

      // 确保麦克风权限已获取 - 使用不同方式检查权限
      final status = await Permission.microphone.status;
      print('$TAG: 麦克风权限状态: $status');

      if (status != PermissionStatus.granted) {
        final result = await Permission.microphone.request();
        print('$TAG: 请求麦克风权限结果: $result');
        if (result != PermissionStatus.granted) {
          print('$TAG: Quyền micrô bị từ chối');
          return;
        }
      }

      // 尝试直接使用音频流
      try {
        print('$TAG: 尝试启动流式录音');
        final stream = await _audioRecorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: SAMPLE_RATE,
            numChannels: CHANNELS,
            // Android record 5.x hỗ trợ các hiệu ứng này khi thiết bị có.
            // Auto-gain + noise suppression giúp tín hiệu thoại ổn định hơn;
            // echo cancellation giảm tiếng loa lọt lại mic trong voice chat.
            autoGain: true,
            noiseSuppress: true,
            echoCancel: true,
          ),
        );

        _isRecording = true;
        print('$TAG: 流式录音启动Thành công');

        // Record.startStream() không bảo đảm mỗi chunk đúng 60 ms.
        // Bản cũ encode từng chunk và chỉ lấy 960 sample đầu tiên, vì vậy
        // có thể làm RƠI phần lớn audio hoặc chèn silence khi chunk ngắn.
        // Điều đó làm ASR nghe sai dù microphone phần cứng vẫn tốt.
        _pcmFrames.clear();
        await _recorderStreamSubscription?.cancel();
        _recorderStreamSubscription = stream.listen(
          (data) {
            if (data.isEmpty) return;
            _consumePcmBytes(data);
          },
          onError: (error) {
            print('$TAG: Lỗi luồng audio: $error');
            _isRecording = false;
          },
          onDone: () {
            print('$TAG: Luồng audio đã kết thúc');
          },
        );
      } catch (e) {
        print('$TAG: 流式录音Thất bại: $e');
        _isRecording = false;
        rethrow;
      }
    } catch (e, stackTrace) {
      print('$TAG: 启动录音Thất bại: $e');
      print(stackTrace);
      _isRecording = false;
    }
  }

  /// 停止录音
  static Future<String?> stopRecording() async {
    if (!_isRecorderInitialized || !_isRecording) return null;

    // Hủy定时器
    _audioProcessingTimer?.cancel();

    // 停止录音
    try {
      final path = await _audioRecorder.stop();
      await _recorderStreamSubscription?.cancel();
      _recorderStreamSubscription = null;
      _pcmFrames.clear();
      _isRecording = false;
      print('$TAG: Đã dừng ghi âm: $path');
      return path;
    } catch (e) {
      print('$TAG: 停止录音Thất bại: $e');
      _isRecording = false;
      return null;
    }
  }

  /// Tích lũy PCM16 little-endian và chỉ encode khi đủ đúng 60 ms.
  /// 16 kHz * 60 ms = 960 sample = 1920 byte mono PCM16.
  static void _consumePcmBytes(Uint8List data) {
    for (final frame in _pcmFrames.add(data)) {
      final opusData = _encodeExactPcmFrame(frame);
      if (opusData != null && opusData.isNotEmpty) {
        _audioStreamController.add(opusData);
      }
    }
  }

  static Uint8List? _encodeExactPcmFrame(Uint8List pcmData) {
    try {
      final int samplesPerFrame = (SAMPLE_RATE * FRAME_DURATION) ~/ 1000;
      if (pcmData.length != samplesPerFrame * 2) return null;

      final pcmInt16 = Int16List(samplesPerFrame);
      final byteData = ByteData.sublistView(pcmData);
      for (int i = 0; i < samplesPerFrame; i++) {
        pcmInt16[i] = byteData.getInt16(i * 2, Endian.little);
      }

      return Uint8List.fromList(_encoder.encode(input: pcmInt16));
    } catch (e, stackTrace) {
      print('$TAG: Opus frame encode lỗi: $e');
      print(stackTrace);
      return null;
    }
  }

  /// Giữ API cũ nhưng KHÔNG pad silence hoặc cắt bỏ audio.
  static Future<Uint8List?> encodeToOpus(Uint8List pcmData) async {
    const int bytesPerFrame = SAMPLE_RATE * FRAME_DURATION ~/ 1000 * 2;
    if (pcmData.length != bytesPerFrame) {
      return null;
    }
    return _encodeExactPcmFrame(pcmData);
  }

  /// 检查是否正在录音
  static bool get isRecording => _isRecording;

  /// 检查是否正在播放
  static bool get isPlaying => _isPlaying;
}
