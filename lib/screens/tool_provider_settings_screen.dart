import 'package:flutter/material.dart';
import 'package:ai_assistant/tools/services/tool_provider_config.dart';

class ToolProviderSettingsScreen extends StatefulWidget {
  const ToolProviderSettingsScreen({super.key});

  @override
  State<ToolProviderSettingsScreen> createState() => _ToolProviderSettingsScreenState();
}

class _ToolProviderSettingsScreenState extends State<ToolProviderSettingsScreen> {
  final ToolProviderConfigStore _store = ToolProviderConfigStore();
  final TextEditingController _bridgeUrl = TextEditingController();
  final TextEditingController _bridgeToken = TextEditingController();
  final TextEditingController _sportsKey = TextEditingController();
  bool _loading = true;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await _store.load();
    _bridgeUrl.text = config.bridgeUrl;
    _bridgeToken.text = config.bridgeToken;
    _sportsKey.text = config.sportsDbKey;
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _bridgeUrl.dispose();
    _bridgeToken.dispose();
    _sportsKey.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await _store.save(
      ToolProviderConfig(
        bridgeUrl: _bridgeUrl.text,
        bridgeToken: _bridgeToken.text,
        sportsDbKey: _sportsKey.text,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã lưu nguồn dữ liệu realtime.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nguồn dữ liệu realtime')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 80),
              children: [
                const _InfoCard(),
                const SizedBox(height: 16),
                TextField(
                  controller: _bridgeUrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Realtime Bridge URL',
                    hintText: 'https://your-server.example/api/tools',
                    prefixIcon: Icon(Icons.hub_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bridgeToken,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Bridge token (nếu có)',
                    prefixIcon: const Icon(Icons.key_rounded),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _sportsKey,
                  decoration: const InputDecoration(
                    labelText: 'TheSportsDB API key',
                    helperText: 'Mặc định 123 dành cho API v1 miễn phí trong giai đoạn phát triển.',
                    prefixIcon: Icon(Icons.sports_soccer_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Lưu cấu hình'),
                ),
                const SizedBox(height: 24),
                const Text('Hợp đồng Realtime Bridge', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const SelectableText(
                  'GET <bridge>?toolId=vn_market_index&q=VNIndex%20hôm%20nay\n\n'
                  'Response JSON:\n'
                  '{\n'
                  '  "success": true,\n'
                  '  "title": "VNIndex",\n'
                  '  "summary": "VNIndex ...",\n'
                  '  "source": "Provider name",\n'
                  '  "timestamp": "2026-08-18T01:00:00+07:00",\n'
                  '  "data": {"Điểm": "...", "Thay đổi": "..."}\n'
                  '}',
                  style: TextStyle(fontFamily: 'monospace', height: 1.35),
                ),
              ],
            ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: colors.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'v4 có nguồn không-key tích hợp sẵn cho thời tiết, AQI, FX, quy đổi tiền, crypto, tin tức, một phần xổ số và thể thao. '
                'Các dữ liệu tài chính Việt Nam chưa có API công khai ổn định được nối qua một Realtime Bridge chuẩn hóa thay vì hard-code hoặc bịa số.',
                style: TextStyle(color: colors.onPrimaryContainer, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
