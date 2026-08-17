import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ai_assistant/tools/models/tool_models.dart';
import 'package:ai_assistant/tools/services/realtime_tool_engine.dart';
import 'package:ai_assistant/tools/widgets/tool_result_card.dart';

class ToolDetailScreen extends StatefulWidget {
  const ToolDetailScreen({
    super.key,
    required this.tool,
    this.initialQuery,
  });

  final ToolDefinition tool;
  final String? initialQuery;

  @override
  State<ToolDetailScreen> createState() => _ToolDetailScreenState();
}

class _ToolDetailScreenState extends State<ToolDetailScreen> {
  final RealtimeToolEngine _engine = RealtimeToolEngine();
  final FlutterTts _tts = FlutterTts();
  late final TextEditingController _controller;
  ToolResult? _result;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    _tts.awaitSpeakCompletion(true);
    if ((widget.initialQuery ?? '').trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run(widget.initialQuery!));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _run(String query) async {
    final cleaned = query.trim().isEmpty
        ? (widget.tool.examples.isNotEmpty ? widget.tool.examples.first : widget.tool.name)
        : query.trim();
    setState(() => _loading = true);
    try {
      final result = await _engine.execute(widget.tool.id, query: cleaned);
      if (!mounted) return;
      setState(() => _result = result);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _speak() async {
    final result = _result;
    if (result == null) return;
    await _tts.stop();
    await _tts.setLanguage('vi-VN');
    await _tts.speak(result.summary);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tool.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Chip(
                label: Text(widget.tool.availability.label),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 80),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Icon(widget.tool.icon, color: theme.colorScheme.onPrimaryContainer),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.tool.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 3),
                              Text(widget.tool.description, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _run,
                      decoration: InputDecoration(
                        hintText: widget.tool.examples.isNotEmpty ? widget.tool.examples.first : 'Nhập yêu cầu tra cứu',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: IconButton(
                          tooltip: 'Tra cứu',
                          onPressed: _loading ? null : () => _run(_controller.text),
                          icon: const Icon(Icons.arrow_forward_rounded),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                    ),
                    if (widget.tool.examples.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: widget.tool.examples.map((example) {
                          return ActionChip(
                            avatar: const Icon(Icons.mic_none_rounded, size: 17),
                            label: Text(example),
                            onPressed: () {
                              _controller.text = example;
                              _run(example);
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: 18),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text('Đang tra dữ liệu realtime…', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 18),
              ToolResultCard(
                result: _result!,
                onSpeak: _result!.success ? _speak : null,
                onRefresh: _loading ? null : () => _run(_controller.text),
              ),
              if (!_result!.success && _result!.errorCode == 'NEEDS_CONFIGURATION') ...[
                const SizedBox(height: 12),
                Card(
                  color: theme.colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.hub_rounded, color: theme.colorScheme.onSecondaryContainer),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tool này đã có UI, router, timeout, cache và hợp đồng kết quả nhưng cần một nguồn dữ liệu chuẩn hóa. '
                            'Bạn có thể cấu hình Realtime Bridge trong Cài đặt để dùng nguồn API riêng.',
                            style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
