import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/models/dify_config.dart';
import 'package:ai_assistant/models/minimax_config.dart';
import 'package:ai_assistant/models/xiaozhi_config.dart';
import 'package:ai_assistant/providers/config_provider.dart';
import 'package:ai_assistant/providers/theme_provider.dart';
import 'package:ai_assistant/screens/diagnostics_screen.dart';
import 'package:ai_assistant/screens/interpreter_screen.dart';
import 'package:ai_assistant/screens/xiaozhi_official_setup_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigProvider>();
    final theme = context.watch<ThemeProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            _SectionTitle('AI & dịch vụ'),
            _NavCard(
              icon: Icons.hub_rounded,
              title: 'Xiaozhi',
              subtitle: '${config.xiaozhiConfigs.length} cấu hình • Voice / WebSocket / OTA',
              badge: config.xiaozhiConfigs.isEmpty ? 'Chưa cấu hình' : 'Sẵn sàng',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _XiaozhiSettingsPage()),
              ),
            ),
            _NavCard(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Dify',
              subtitle: '${config.difyConfigs.length} cấu hình Agent/API',
              badge: config.difyConfigs.isEmpty ? 'Chưa cấu hình' : 'Đã cấu hình',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _DifySettingsPage()),
              ),
            ),
            _NavCard(
              icon: Icons.auto_awesome_rounded,
              title: 'MiniMax',
              subtitle: '${config.minimaxConfigs.length} cấu hình mô hình AI',
              badge: config.minimaxConfigs.isEmpty ? 'Chưa cấu hình' : 'Đã cấu hình',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _MiniMaxSettingsPage()),
              ),
            ),
            const SizedBox(height: 18),
            _SectionTitle('Giọng nói & phiên dịch'),
            _NavCard(
              icon: Icons.translate_rounded,
              title: 'Phiên dịch AI',
              subtitle: 'Dịch văn bản, giọng nói và phát TTS đa ngôn ngữ',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const InterpreterScreen()),
              ),
            ),
            _NavCard(
              icon: Icons.monitor_heart_outlined,
              title: 'Chẩn đoán Voice',
              subtitle: 'MIC → VAD → ASR → Agent → Tool → TTS',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
              ),
            ),
            const SizedBox(height: 18),
            _SectionTitle('Giao diện'),
            Card(
              child: SwitchListTile.adaptive(
                secondary: Icon(theme.isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded),
                title: const Text('Chế độ tối', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Chuyển giao diện sáng / tối'),
                value: theme.isDarkMode,
                onChanged: (_) => theme.toggleTheme(),
              ),
            ),
            const SizedBox(height: 18),
            _SectionTitle('Phiên bản'),
            const Card(
              child: ListTile(
                leading: Icon(Icons.verified_outlined),
                title: Text('AI-LHHT v3.3 Voice Pro', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('3.3.0+330 • Online Tools + Bilingual ASR'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
      );
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;
  const _NavCard({required this.icon, required this.title, required this.subtitle, this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Theme.of(context).colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (badge != null) ...[
                      const SizedBox(height: 7),
                      Text(badge!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _XiaozhiSettingsPage extends StatelessWidget {
  const _XiaozhiSettingsPage();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ConfigProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Xiaozhi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const XiaozhiOfficialSetupScreen())),
            icon: const Icon(Icons.link_rounded),
            label: const Text('Kết nối Xiaozhi chính thức'),
          ),
          const SizedBox(height: 14),
          if (provider.xiaozhiConfigs.isEmpty)
            const _EmptyCard('Chưa có cấu hình Xiaozhi. Dùng nút phía trên để provisioning chính thức.')
          else
            ...provider.xiaozhiConfigs.map((item) => _XiaozhiConfigCard(item)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showXiaozhiDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Thêm thủ công'),
      ),
    );
  }
}

class _XiaozhiConfigCard extends StatelessWidget {
  final XiaozhiConfig config;
  const _XiaozhiConfigCard(this.config);
  String _mask(String token) {
    if (token.isEmpty) return 'Chưa có';
    if (token.length <= 6) return '••••••';
    return '${token.substring(0, math.min(3, token.length))}••••••${token.substring(token.length - 2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.mic_rounded)),
                const SizedBox(width: 12),
                Expanded(child: Text(config.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17), overflow: TextOverflow.ellipsis)),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') _showXiaozhiDialog(context, existing: config);
                    if (value == 'delete') context.read<ConfigProvider>().deleteXiaozhiConfig(config.id);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa')),
                    PopupMenuItem(value: 'delete', child: Text('Xóa')),
                  ],
                ),
              ],
            ),
            const Divider(height: 24),
            _InfoLine('Server', config.websocketUrl),
            _InfoLine('Device ID', config.macAddress),
            _InfoLine('Client ID', config.clientId),
            _InfoLine('Token', _mask(config.token)),
          ],
        ),
      ),
    );
  }
}

class _DifySettingsPage extends StatelessWidget {
  const _DifySettingsPage();
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ConfigProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Dify')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (provider.difyConfigs.isEmpty)
            const _EmptyCard('Chưa có cấu hình Dify. Thêm API URL và API Key để sử dụng Agent Dify.')
          else
            ...provider.difyConfigs.map((item) => _DifyConfigCard(item)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showDifyDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Thêm Dify'),
      ),
    );
  }
}

class _DifyConfigCard extends StatelessWidget {
  final DifyConfig config;
  const _DifyConfigCard(this.config);
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: const CircleAvatar(child: Icon(Icons.chat_bubble_outline)),
          title: Text(config.name, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${config.apiUrl}\nAPI key: ${_maskSecret(config.apiKey)}', maxLines: 3, overflow: TextOverflow.ellipsis),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') _showDifyDialog(context, existing: config);
              if (value == 'delete') context.read<ConfigProvider>().deleteDifyConfig(config.id);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa')),
              PopupMenuItem(value: 'delete', child: Text('Xóa')),
            ],
          ),
        ),
      );
}

class _MiniMaxSettingsPage extends StatelessWidget {
  const _MiniMaxSettingsPage();
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ConfigProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('MiniMax')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (provider.minimaxConfigs.isEmpty)
            const _EmptyCard('Chưa có MiniMax API Key. MiniMax có thể dùng cho chat và phiên dịch AI.')
          else
            ...provider.minimaxConfigs.map((item) => _MiniMaxConfigCard(item)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showMiniMaxDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Thêm MiniMax'),
      ),
    );
  }
}

class _MiniMaxConfigCard extends StatelessWidget {
  final MiniMaxConfig config;
  const _MiniMaxConfigCard(this.config);
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: const CircleAvatar(child: Icon(Icons.auto_awesome_rounded)),
          title: Text(config.name, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${config.model}\nAPI key: ${_maskSecret(config.apiKey)}'),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') _showMiniMaxDialog(context, existing: config);
              if (value == 'delete') context.read<ConfigProvider>().deleteMiniMaxConfig(config.id);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa')),
              PopupMenuItem(value: 'delete', child: Text('Xóa')),
            ],
          ),
        ),
      );
}

class _EmptyCard extends StatelessWidget {
  final String text;
  const _EmptyCard(this.text);
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              const Icon(Icons.inbox_outlined, size: 42),
              const SizedBox(height: 10),
              Text(text, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;
  const _InfoLine(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 82, child: Text(label, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
}

String _maskSecret(String value) {
  if (value.isEmpty) return 'Chưa có';
  if (value.length <= 8) return '••••••••';
  return '${value.substring(0, 4)}••••••${value.substring(value.length - 3)}';
}

Future<void> _showDifyDialog(BuildContext context, {DifyConfig? existing}) async {
  final name = TextEditingController(text: existing?.name ?? 'Dify');
  final url = TextEditingController(text: existing?.apiUrl ?? '');
  final key = TextEditingController(text: existing?.apiKey ?? '');
  final form = GlobalKey<FormState>();
  await showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(existing == null ? 'Thêm Dify' : 'Chỉnh sửa Dify'),
      content: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Tên cấu hình'), validator: _required),
              const SizedBox(height: 10),
              TextFormField(controller: url, decoration: const InputDecoration(labelText: 'API URL'), validator: _required),
              const SizedBox(height: 10),
              TextFormField(controller: key, obscureText: true, decoration: const InputDecoration(labelText: 'API Key'), validator: _required),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Hủy')),
        FilledButton(
          onPressed: () async {
            if (!(form.currentState?.validate() ?? false)) return;
            final provider = context.read<ConfigProvider>();
            if (existing == null) {
              await provider.addDifyConfig(name.text.trim(), key.text.trim(), url.text.trim());
            } else {
              await provider.updateDifyConfig(existing.copyWith(name: name.text.trim(), apiKey: key.text.trim(), apiUrl: url.text.trim()));
            }
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          child: const Text('Lưu'),
        ),
      ],
    ),
  );
  name.dispose(); url.dispose(); key.dispose();
}

Future<void> _showMiniMaxDialog(BuildContext context, {MiniMaxConfig? existing}) async {
  final name = TextEditingController(text: existing?.name ?? 'MiniMax');
  final key = TextEditingController(text: existing?.apiKey ?? '');
  final model = TextEditingController(text: existing?.model ?? 'MiniMax-M2.7');
  final form = GlobalKey<FormState>();
  await showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(existing == null ? 'Thêm MiniMax' : 'Chỉnh sửa MiniMax'),
      content: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Tên cấu hình'), validator: _required),
              const SizedBox(height: 10),
              TextFormField(controller: key, obscureText: true, decoration: const InputDecoration(labelText: 'API Key'), validator: _required),
              const SizedBox(height: 10),
              TextFormField(controller: model, decoration: const InputDecoration(labelText: 'Model'), validator: _required),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Hủy')),
        FilledButton(
          onPressed: () async {
            if (!(form.currentState?.validate() ?? false)) return;
            final provider = context.read<ConfigProvider>();
            if (existing == null) {
              await provider.addMiniMaxConfig(name.text.trim(), key.text.trim(), model: model.text.trim());
            } else {
              await provider.updateMiniMaxConfig(existing.copyWith(name: name.text.trim(), apiKey: key.text.trim(), model: model.text.trim()));
            }
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          child: const Text('Lưu'),
        ),
      ],
    ),
  );
  name.dispose(); key.dispose(); model.dispose();
}

Future<void> _showXiaozhiDialog(BuildContext context, {XiaozhiConfig? existing}) async {
  final name = TextEditingController(text: existing?.name ?? 'Robot Xiaozhi');
  final server = TextEditingController(text: existing?.websocketUrl ?? 'wss://api.tenclass.net/xiaozhi/v1/');
  final device = TextEditingController(text: existing?.macAddress ?? '');
  final client = TextEditingController(text: existing?.clientId ?? '');
  final token = TextEditingController(text: existing?.token ?? '');
  final form = GlobalKey<FormState>();
  await showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(existing == null ? 'Thêm Xiaozhi thủ công' : 'Chỉnh sửa Xiaozhi'),
      content: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Tên'), validator: _required),
              const SizedBox(height: 10),
              TextFormField(controller: server, decoration: const InputDecoration(labelText: 'WebSocket URL'), validator: _required),
              const SizedBox(height: 10),
              TextFormField(controller: device, decoration: const InputDecoration(labelText: 'Device / MAC')),
              const SizedBox(height: 10),
              TextFormField(controller: client, decoration: const InputDecoration(labelText: 'Client ID')),
              const SizedBox(height: 10),
              TextFormField(controller: token, obscureText: true, decoration: const InputDecoration(labelText: 'Token')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Hủy')),
        FilledButton(
          onPressed: () async {
            if (!(form.currentState?.validate() ?? false)) return;
            final provider = context.read<ConfigProvider>();
            if (existing == null) {
              if (device.text.trim().isNotEmpty &&
                  client.text.trim().isNotEmpty &&
                  token.text.trim().isNotEmpty) {
                await provider.addXiaozhiConfigWithToken(
                  name: name.text.trim(),
                  websocketUrl: server.text.trim(),
                  macAddress: device.text.trim(),
                  clientId: client.text.trim(),
                  token: token.text.trim(),
                );
              } else {
                await provider.addXiaozhiConfig(
                  name.text.trim(),
                  server.text.trim(),
                  customMacAddress: device.text.trim().isEmpty ? null : device.text.trim(),
                  customToken: token.text.trim().isEmpty ? null : token.text.trim(),
                );
              }
            } else {
              await provider.updateXiaozhiConfig(existing.copyWith(
                name: name.text.trim(),
                websocketUrl: server.text.trim(),
                macAddress: device.text.trim(),
                clientId: client.text.trim(),
                token: token.text.trim(),
              ));
            }
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          child: const Text('Lưu'),
        ),
      ],
    ),
  );
  name.dispose(); server.dispose(); device.dispose(); client.dispose(); token.dispose();
}

String? _required(String? value) => (value == null || value.trim().isEmpty) ? 'Không được để trống' : null;
