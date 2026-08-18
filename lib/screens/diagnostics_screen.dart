import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/providers/config_provider.dart';
import 'package:ai_assistant/services/xiaozhi_service.dart';
import 'package:ai_assistant/services/native_speech_service.dart';
import 'package:ai_assistant/tools/services/realtime_tool_engine.dart';
import 'package:ai_assistant/services/unified_speech_output_service.dart';
import 'package:ai_assistant/services/voice_output_preferences.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  bool _testing = false;
  String _xiaozhiStatus = 'Chưa kiểm tra';
  String _latency = '--';
  String _nativeAsrStatus = 'Chưa kiểm tra';
  String _toolStatus = 'Chưa kiểm tra';
  String _ttsStatus = 'Chưa kiểm tra';
  bool _testingTools = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_testNativeAsr);
    Future.microtask(_testStableTts);
  }

  Future<void> _testNativeAsr() async {
    final speech = NativeSpeechService.instance;
    final ready = await speech.initialize();
    if (!ready) {
      if (mounted) setState(() => _nativeAsrStatus = 'Không khả dụng: ${speech.lastError}');
      return;
    }
    final vi = await speech.supportsLocale('vi-VN');
    final zh = await speech.supportsLocale('zh-CN');
    if (mounted) {
      setState(() {
        _nativeAsrStatus = 'Tiếng Việt: ${vi ? "PASS" : "thiếu"} • 中文: ${zh ? "PASS" : "thiếu"}';
      });
    }
  }

  Future<void> _testStableTts() async {
    final speech = UnifiedSpeechOutputService.instance;
    final prefs = VoiceOutputPreferences();
    final unified = await prefs.useUnifiedVoice();
    final ready = await speech.initialize(locale: 'vi-VN');
    if (!mounted) return;
    setState(() {
      _ttsStatus = ready
          ? '${unified ? "Một giọng: BẬT" : "Một giọng: TẮT"} • vi-VN PASS • ${speech.lastVoice.isEmpty ? "voice hệ thống" : speech.lastVoice}'
          : 'TTS vi-VN không khả dụng';
    });
  }

  Future<void> _testTools() async {
    setState(() {
      _testingTools = true;
      _toolStatus = 'Đang kiểm tra…';
    });
    final engine = RealtimeToolEngine();
    var passed = 0;
    final failures = <String>[];
    final cases = <(String, String, Map<String, String>)>[
      ('lunar_calendar', 'Âm lịch hôm nay', const {}),
      ('fx_rate', 'Tỷ giá USD VND', const {'from': 'USD', 'to': 'VND'}),
      ('crypto_price', 'Giá Bitcoin', const {'symbol': 'BTC'}),
      ('weather', 'Thời tiết Hà Nội', const {'location': 'Hà Nội'}),
    ];
    for (final item in cases) {
      try {
        final result = await engine.execute(item.$1, query: item.$2, parameters: item.$3);
        if (result.success) {
          passed++;
        } else {
          failures.add(item.$1);
        }
      } catch (_) {
        failures.add(item.$1);
      }
    }
    if (!mounted) return;
    setState(() {
      _testingTools = false;
      _toolStatus = failures.isEmpty
          ? 'PASS $passed/${cases.length} core tools'
          : 'PASS $passed/${cases.length} • lỗi: ${failures.join(', ')}';
    });
  }

  Future<void> _testXiaozhi() async {
    final provider = Provider.of<ConfigProvider>(context, listen: false);
    if (provider.xiaozhiConfigs.isEmpty) {
      setState(() => _xiaozhiStatus = 'Chưa có cấu hình Xiaozhi');
      return;
    }
    setState(() {
      _testing = true;
      _xiaozhiStatus = 'Đang kết nối...';
      _latency = '--';
    });

    final config = provider.xiaozhiConfigs.first;
    final service = XiaozhiService(
      websocketUrl: config.websocketUrl,
      macAddress: config.macAddress,
      clientId: config.clientId,
      token: config.token,
    );
    final started = DateTime.now();
    try {
      await service.connect().timeout(const Duration(seconds: 12));
      await Future.delayed(const Duration(milliseconds: 350));
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      if (!mounted) return;
      setState(() {
        _xiaozhiStatus = service.isConnected ? 'Đã kết nối' : 'Kết nối chưa sẵn sàng';
        _latency = '${elapsed} ms';
      });
    } on TimeoutException {
      if (mounted) setState(() => _xiaozhiStatus = 'Hết thời gian chờ');
    } catch (e) {
      if (mounted) setState(() => _xiaozhiStatus = 'Lỗi: $e');
    } finally {
      await service.disconnect();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ConfigProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Chẩn đoán hệ thống')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Voice Pipeline',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _PipelineCard(
              items: [
                _PipelineItem('MIC', 'Thu âm từ thiết bị', Icons.mic_rounded, true),
                _PipelineItem('VAD', 'Điều khiển bởi phiên Xiaozhi', Icons.multiline_chart_rounded, provider.xiaozhiConfigs.isNotEmpty),
                _PipelineItem('ASR', 'Native locale-locked + Xiaozhi fallback', Icons.record_voice_over_rounded, true),
                _PipelineItem('AGENT', 'Xiaozhi / Dify / MiniMax', Icons.smart_toy_outlined, provider.xiaozhiConfigs.isNotEmpty || provider.difyConfigs.isNotEmpty || provider.minimaxConfigs.isNotEmpty),
                _PipelineItem('TTS', 'Unified TTS v4.1 • một hàng đợi • một voice', Icons.volume_up_rounded, !_ttsStatus.contains('không khả dụng')),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Dịch vụ AI',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            _StatusTile(
              icon: Icons.record_voice_over_rounded,
              title: 'ASR ngôn ngữ',
              subtitle: _nativeAsrStatus,
              trailing: TextButton(onPressed: _testNativeAsr, child: const Text('Kiểm tra')),
            ),
            _StatusTile(
              icon: Icons.volume_up_rounded,
              title: 'Voice Stability / TTS',
              subtitle: _ttsStatus,
              trailing: TextButton(onPressed: _testStableTts, child: const Text('Kiểm tra')),
            ),
            _StatusTile(
              icon: Icons.travel_explore_rounded,
              title: 'Realtime Tool Engine v4',
              subtitle: _toolStatus,
              trailing: _testingTools
                  ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(onPressed: _testTools, child: const Text('Kiểm tra')),
            ),
            _StatusTile(
              icon: Icons.hub_outlined,
              title: 'Xiaozhi',
              subtitle: '${provider.xiaozhiConfigs.length} cấu hình • $_xiaozhiStatus',
              trailing: _testing
                  ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(onPressed: _testXiaozhi, child: const Text('Kiểm tra')),
            ),
            _StatusTile(
              icon: Icons.chat_bubble_outline,
              title: 'Dify',
              subtitle: '${provider.difyConfigs.length} cấu hình',
              ok: provider.difyConfigs.isNotEmpty,
            ),
            _StatusTile(
              icon: Icons.auto_awesome_rounded,
              title: 'MiniMax',
              subtitle: '${provider.minimaxConfigs.length} cấu hình',
              ok: provider.minimaxConfigs.isNotEmpty,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Thông tin kết nối', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _InfoRow(label: 'WebSocket', value: provider.xiaozhiConfigs.isEmpty ? '--' : provider.xiaozhiConfigs.first.websocketUrl),
                    _InfoRow(label: 'Device ID', value: provider.xiaozhiConfigs.isEmpty ? '--' : provider.xiaozhiConfigs.first.macAddress),
                    _InfoRow(label: 'Client ID', value: provider.xiaozhiConfigs.isEmpty ? '--' : provider.xiaozhiConfigs.first.clientId),
                    _InfoRow(label: 'Độ trễ test', value: _latency),
                    _InfoRow(label: 'Token', value: provider.xiaozhiConfigs.isEmpty ? '--' : '••••••••'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Mẹo v4.1: Realtime Tool Engine phải PASS các core tool trước khi kiểm tra Agent. Với phiên dịch Việt ↔ Trung, mục ASR ngôn ngữ cần PASS cho cả vi-VN và zh-CN. Nếu thiếu zh-CN, cài dịch vụ/giọng nhận dạng tiếng Trung trên Android. Realtime tools và nhạc online được xử lý trong APK trước khi gửi Agent.',
                  style: TextStyle(height: 1.45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PipelineItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool ok;
  const _PipelineItem(this.title, this.subtitle, this.icon, this.ok);
}

class _PipelineCard extends StatelessWidget {
  final List<_PipelineItem> items;
  const _PipelineCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    child: Icon(items[i].icon, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(items[i].title, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(items[i].subtitle, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Icon(items[i].ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded, color: items[i].ok ? Colors.green : Colors.orange),
                ],
              ),
              if (i != items.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Container(width: 2, height: 22, color: Theme.of(context).dividerColor),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool? ok;
  const _StatusTile({required this.icon, required this.title, required this.subtitle, this.trailing, this.ok});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: trailing ?? Icon(ok == true ? Icons.check_circle_rounded : Icons.info_outline_rounded, color: ok == true ? Colors.green : null),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 92, child: Text(label, style: const TextStyle(color: Colors.grey))),
          const SizedBox(width: 8),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis, maxLines: 2)),
        ],
      ),
    );
  }
}
