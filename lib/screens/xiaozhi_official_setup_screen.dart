import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/config_provider.dart';
import '../services/xiaozhi_provisioning_service.dart';
import '../services/xiaozhi_websocket_manager.dart';

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
  bool _verifyingWebSocket = false;
  bool _protocolHandshakeOk = false;
  String? _protocolStatus;

  Future<void> _runProvisioning() async {
    setState(() {
      _loading = true;
      _error = null;
      _protocolHandshakeOk = false;
      _protocolStatus = null;
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

  Future<void> _verifyWebSocketProtocol() async {
    final result = _result;
    if (result == null || !result.canConnectDiagnostic) return;

    setState(() {
      _verifyingWebSocket = true;
      _protocolHandshakeOk = false;
      _protocolStatus = 'Đang mở WebSocket và chờ server hello...';
    });

    final manager = XiaozhiWebSocketManager(
      deviceId: result.deviceId,
      clientId: result.clientId,
      enableToken: true,
    );

    try {
      await manager.connect(result.websocketUrl!, result.token!);
      if (!mounted) return;
      setState(() {
        _protocolHandshakeOk = true;
        _protocolStatus =
            'PASS: máy chủ đã trả hello hợp lệ. Đây là kết nối giao thức thật, không phải chỉ HTTP 200.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _protocolHandshakeOk = false;
        _protocolStatus = 'FAIL: $e';
      });
    } finally {
      await manager.disconnect();
      if (mounted) setState(() => _verifyingWebSocket = false);
    }
  }

  Future<void> _saveConnection() async {
    final result = _result;
    if (result == null || !_protocolHandshakeOk || !result.canConnectDiagnostic) return;

    await Provider.of<ConfigProvider>(context, listen: false)
        .addXiaozhiConfigWithToken(
          name: 'Robot Xiaozhi',
          websocketUrl: result.websocketUrl!,
          macAddress: result.deviceId,
          clientId: result.clientId,
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
                'Device-ID: ${result.deviceId}\nClient-ID: ${result.clientId}\nHTTP: ${result.httpStatus}\nURL: ${result.finalUrl}\nRequest: ${result.requestProfile}',
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
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            result.activationCode!,
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 8,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Sao chép mã',
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: result.activationCode!),
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Đã sao chép mã 6 số.')),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded),
                        ),
                      ],
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
            if (result.isHealthResponse) ...[
              const SizedBox(height: 12),
              const _InfoCard(
                title: 'Máy chủ chưa trả cấu hình OTA',
                color: Colors.orange,
                child: Text(
                  'Máy chủ chỉ trả trạng thái hoạt động, chưa trả activation/websocket. '
                  'Bản v3.2 dùng POST theo cấu trúc application + board và Activation-Version=1 '
                  'theo nhánh firmware chính thức không có Serial-Number/HMAC eFuse.',
                ),
              ),
            ],
            if (result.hasActivationChallenge && !result.hasActivationCode) ...[
              const SizedBox(height: 12),
              const _InfoCard(
                title: 'Máy chủ yêu cầu kích hoạt HMAC',
                color: Colors.orange,
                child: Text(
                  'Máy chủ trả activation challenge nhưng không trả mã 6 số. '
                  'Android không giả mạo Serial-Number/HMAC eFuse của phần cứng ESP32. '
                  'Hãy dùng luồng Activation-Version=1 hoặc thiết bị Xiaozhi có khóa HMAC thật.',
                ),
              ),
            ],
            if (result.isTestCredential) ...[
              const SizedBox(height: 12),
              const _InfoCard(
                title: 'OTA vẫn trả test-token / GID_test',
                color: Colors.orange,
                child: Text(
                  'Đây là hành vi phía api.tenclass.net đã được ghi nhận cả trên client/firmware Xiaozhi: '
                  'sau OTA có thể vẫn nhận test-token/GID_test. Bản v3.2 không còn kết luận thất bại chỉ '
                  'dựa vào tên token. Thay vào đó app sẽ mở WebSocket với đúng Device-ID + Client-ID và '
                  'chỉ cho lưu khi server trả hello hợp lệ trong 10 giây.',
                ),
              ),
            ],
            if (result.canConnectDiagnostic) ...[
              const SizedBox(height: 12),
              _InfoCard(
                title: result.isTestCredential
                    ? 'WebSocket do OTA cấp'
                    : 'WebSocket production',
                color: result.isTestCredential ? Colors.orange : Colors.green,
                child: SelectableText(
                  '${result.websocketUrl}\nToken: đã ẩn',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _verifyingWebSocket ? null : _verifyWebSocketProtocol,
                icon: _verifyingWebSocket
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cable_rounded),
                label: Text(
                  _verifyingWebSocket
                      ? 'Đang chờ server hello...'
                      : 'Kiểm tra kết nối Agent thật',
                ),
              ),
              if (_protocolStatus != null) ...[
                const SizedBox(height: 10),
                _InfoCard(
                  title: _protocolHandshakeOk
                      ? 'WebSocket protocol: PASS'
                      : 'WebSocket protocol',
                  color: _protocolHandshakeOk ? Colors.green : Colors.orange,
                  child: Text(_protocolStatus!),
                ),
              ],
              if (_protocolHandshakeOk) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saveConnection,
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('Lưu kết nối đã xác minh và sử dụng Agent'),
                ),
              ],
            ],
            if (result.hasActivationCode) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading ? null : _runProvisioning,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Đã nhập mã trên xiaozhi.me – kiểm tra lại'),
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
