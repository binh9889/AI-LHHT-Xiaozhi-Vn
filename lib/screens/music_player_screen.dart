import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Trình phát nhạc trực tuyến nằm bên trong AI-LHHT.
///
/// Màn hình này dùng WebView chính thức của Flutter để hiển thị nhà cung cấp
/// web. App không tải xuống, trích xuất hay giải mã luồng audio của nhà cung cấp.
class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({
    super.key,
    required this.initialUri,
    required this.title,
  });

  final Uri initialUri;
  final String title;

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF7F7FA))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _error = null);
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _error = 'Không tải được trình phát trực tuyến: ${error.description}';
            });
          },
        ),
      )
      ..loadRequest(widget.initialUri);
  }

  Future<void> _goBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          leading: IconButton(
            tooltip: 'Quay lại',
            onPressed: _goBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nhạc trực tuyến',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Làm mới',
              onPressed: _controller.reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (_progress < 100)
                LinearProgressIndicator(value: _progress / 100),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(.55),
                child: const Text(
                  'Chọn bài trong kết quả để phát ngay trong ứng dụng. '
                  'AI-LHHT không dùng kho 5 bài cục bộ và không mở ứng dụng YouTube bên ngoài.',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
              Expanded(
                child: _error == null
                    ? WebViewWidget(controller: _controller)
                    : _ErrorState(
                        message: _error!,
                        onRetry: () {
                          setState(() => _error = null);
                          _controller.loadRequest(widget.initialUri);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }
}
