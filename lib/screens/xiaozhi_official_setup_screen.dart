import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/config_provider.dart';
import '../services/xiaozhi_provisioning_service.dart';

class XiaozhiOfficialSetupScreen extends StatefulWidget {
  const XiaozhiOfficialSetupScreen({super.key});

  @override
  State<XiaozhiOfficialSetupScreen> createState() =>
      _XiaozhiOfficialSetupScreenState();
}

class _XiaozhiOfficialSetupScreenState
    extends State<XiaozhiOfficialSetupScreen> {
  bool _loading = false;
  XiaozhiProvisioningResult? _result;
  String? _error;

  Future<void> _runProvisioning() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await XiaozhiProvisioningService.provision();
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveConnection() async {
    final result = _result;
    if (result == null || !result.canConnect) return;

    await Provider.of<ConfigProvider>(context, listen: false)
        .addXiaozhiConfigWithToken(
          name: 'Robot Xiaozhi',
          websocketUrl: result.websocketUrl!,
          macAddress: result.deviceId,
          token: result.token!,
        );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã lưu cấu hình Xiaozhi.')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Kết nối Xiaozhi chính thức')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Ứng dụng sẽ gọi bước OTA/provisioning trước khi mở WebSocket, '
            'giống luồng của firmware Xiaozhi. Nếu máy chủ cấp mã 6 số, hãy '
            'nhập mã đó trong xiaozhi.me → Robot → Thiết bị.',
            style: TextStyle(fontSize: 15, height: 1.45),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : _runProvisioning,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: Text(
              _loading ? 'Đang kiểm tra...' : 'Lấy cấu hình / mã liên kết',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _InfoCard(
              title: 'Lỗi kết nối',
              color: Colors.red,
              child: SelectableText(_error!),
            ),
          ],
          if (result != null) ...[
            const SizedBox(height: 16),
            _InfoCard(
              title: 'Danh tính thiết bị',
              child: SelectableText(
                'Device-ID: ${result.deviceId}\nClient-ID: ${result.clientId}',
              ),
            ),
            if (result.hasActivationCode) ...[
              const SizedBox(height: 12),
              _InfoCard(
                title: 'MÃ LIÊN KẾT THIẾT BỊ',
                color: Colors.green,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      result.activationCode!,
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Mở xiaozhi.me → Robot → Thiết bị → Liên kết thiết bị mới '
                      'và nhập 6 số trên. Sau khi liên kết xong, quay lại đây '
                      'và bấm “Lấy cấu hình / mã liên kết” lần nữa.',
                    ),
                    if (result.activationMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(result.activationMessage!),
                    ],
                  ],
                ),
              ),
            ],
            if (result.isTestCredential) ...[
              const SizedBox(height: 12),
              const _InfoCard(
                title: 'Máy chủ đang trả tài khoản thử nghiệm',
                color: Colors.orange,
                child: Text(
                  'Máy chủ trả test-token/GID_test và không cấp mã activation. '
                  'Điều này có nghĩa điện thoại có thể thử giao thức, nhưng '
                  'chưa được máy chủ xiaozhi.me công nhận là thiết bị có thể '
                  'gắn vào Agent Robot. Đây là giới hạn phía máy chủ, không phải '
                  'lỗi microphone hay WebSocket của điện thoại.',
                ),
              ),
            ],
            if (result.canConnect) ...[
              const SizedBox(height: 12),
              _InfoCard(
                title: 'Thông tin WebSocket nhận được',
                child: SelectableText(
                  '${result.websocketUrl}\nToken: '
                  '${result.token == 'test-token' ? 'test-token' : 'đã được cấp'}',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saveConnection,
                child: Text(
                  result.isTestCredential
                      ? 'Lưu chế độ thử nghiệm'
                      : 'Lưu và sử dụng Agent',
                ),
              ),
            ],
            const SizedBox(height: 12),
            ExpansionTile(
              title: const Text('Xem phản hồi OTA để chẩn đoán'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(result.raw),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Color? color;

  const _InfoCard({required this.title, required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
