import 'package:flutter/material.dart';
import 'package:ai_assistant/providers/config_provider.dart';
import 'package:ai_assistant/services/dify_service.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math' as math;

class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  TestScreenState createState() => TestScreenState();
}

class TestScreenState extends State<TestScreen> {
  final _logs = <String>[];
  bool _isTesting = false;
  final ScrollController _scrollController = ScrollController();
  static const String _conversationMapKey = 'dify_conversation_map';

  void _addLog(String log) {
    setState(() {
      _logs.add('${DateTime.now().toString().substring(11, 19)}: $log');
      // 限制日志行数
      if (_logs.length > 100) {
        _logs.removeRange(0, _logs.length - 100);
      }
    });

    // 滚动到底部
    Future.delayed(const Duration(milliseconds: 10), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _testConsistentSession() async {
    final config = Provider.of<ConfigProvider>(context, listen: false);

    if (config.difyConfig == null) {
      _addLog('Lỗi: Cấu hình Dify APIChưa thiết lập!');
      return;
    }

    setState(() {
      _isTesting = true;
      _logs.clear();
    });

    _addLog('开始Kiểm tra tính nhất quán cuộc trò chuyện...');

    try {
      // 创建一个Kiểm traCuộc trò chuyệnID
      final sessionId = const Uuid().v4();
      _addLog('使用Cuộc trò chuyệnID: $sessionId');

      final difyService = await DifyService.create(
        apiKey: config.difyConfig!.apiKey,
        apiUrl: config.difyConfig!.apiUrl,
      );

      // 发送第一条Tin nhắn
      _addLog('发送第一条Tin nhắn');
      final response1 = await difyService.sendMessage(
        '这是Kiểm traTin nhắn1',
        sessionId: sessionId,
      );
      _addLog(
        '收到回复: ${response1.substring(0, math.min(20, response1.length))}...',
      );
      await _printCurrentSessions();

      // 等待一秒
      await Future.delayed(const Duration(seconds: 1));

      // 发送第二条Tin nhắn
      _addLog('发送第二条Tin nhắn');
      final response2 = await difyService.sendMessage(
        '这是Kiểm traTin nhắn2',
        sessionId: sessionId,
      );
      _addLog(
        '收到回复: ${response2.substring(0, math.min(20, response2.length))}...',
      );
      await _printCurrentSessions();

      // 等待一秒
      await Future.delayed(const Duration(seconds: 1));

      // 发送第三条Tin nhắn
      _addLog('发送第三条Tin nhắn');
      final response3 = await difyService.sendMessage(
        '这是Kiểm traTin nhắn3',
        sessionId: sessionId,
      );
      _addLog(
        '收到回复: ${response3.substring(0, math.min(20, response3.length))}...',
      );

      // 打印结果
      await _printCurrentSessions();

      _addLog('Kiểm traHoàn tất');
    } catch (e) {
      _addLog('Kiểm traThất bại: $e');
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _testResetSession() async {
    final config = Provider.of<ConfigProvider>(context, listen: false);

    if (config.difyConfig == null) {
      _addLog('Lỗi: Cấu hình Dify APIChưa thiết lập!');
      return;
    }

    setState(() {
      _isTesting = true;
      _logs.clear();
    });

    _addLog('开始Kiểm tra đặt lại cuộc trò chuyện...');

    try {
      // 创建一个Kiểm traCuộc trò chuyệnID
      final sessionId = const Uuid().v4();
      _addLog('使用Cuộc trò chuyệnID: $sessionId');

      final difyService = await DifyService.create(
        apiKey: config.difyConfig!.apiKey,
        apiUrl: config.difyConfig!.apiUrl,
      );

      // 先发送一条Tin nhắn
      _addLog('发送đặt lại前Tin nhắn');
      final response1 = await difyService.sendMessage(
        '这是đặt lại前的Tin nhắn',
        sessionId: sessionId,
      );
      _addLog(
        '收到回复: ${response1.substring(0, math.min(20, response1.length))}...',
      );

      // 打印当前Cuộc trò chuyệnID
      await _printCurrentSessions();

      // Đặt lại cuộc trò chuyện
      _addLog('Đặt lại cuộc trò chuyện');
      await difyService.clearConversation(sessionId);

      // 打印đặt lại后的Cuộc trò chuyệnID
      await _printCurrentSessions();

      // 发送đặt lại后的Tin nhắn
      _addLog('发送đặt lại后Tin nhắn');
      final response2 = await difyService.sendMessage(
        '这是đặt lại后的Tin nhắn',
        sessionId: sessionId,
      );
      _addLog(
        '收到回复: ${response2.substring(0, math.min(20, response2.length))}...',
      );

      // 打印最终Cuộc trò chuyệnID
      await _printCurrentSessions();

      _addLog('Kiểm traHoàn tất');
    } catch (e) {
      _addLog('Kiểm traThất bại: $e');
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _printStoredSessions() async {
    setState(() {
      _isTesting = true;
      _logs.clear();
    });

    _addLog('获取存储的Cuộc trò chuyệnID...');

    try {
      await _printCurrentSessions();
      _addLog('Hoàn tất');
    } catch (e) {
      _addLog('Thất bại: $e');
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _printCurrentSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final mapJson = prefs.getString(_conversationMapKey);
    if (mapJson == null || mapJson.isEmpty) {
      _addLog('没有存储的Cuộc trò chuyệnID');
      return;
    }

    final Map<String, dynamic> loadedMap = jsonDecode(mapJson);
    _addLog('存储的Cuộc trò chuyệnID:');
    loadedMap.forEach((sessionId, conversationId) {
      _addLog('- Cuộc trò chuyện: $sessionId => 对话ID: $conversationId');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kiểm tra ID cuộc trò chuyện Dify'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed:
                _logs.isEmpty ? null : () => setState(() => _logs.clear()),
            tooltip: 'Xóa nhật ký',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isTesting ? null : _testConsistentSession,
                    child: const Text('Kiểm tra tính nhất quán cuộc trò chuyện'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isTesting ? null : _testResetSession,
                    child: const Text('Kiểm tra đặt lại cuộc trò chuyện'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isTesting ? null : _printStoredSessions,
                    child: const Text('Xem cuộc trò chuyện đã lưu'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(child: _buildLogView()),
        ],
      ),
    );
  }

  Widget _buildLogView() {
    if (_logs.isEmpty) {
      return const Center(child: Text('Chưa có nhật ký. Hãy chạy kiểm tra để xem kết quả.'));
    }

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView.builder(
            controller: _scrollController,
            itemCount: _logs.length,
            itemBuilder: (context, index) {
              return Text(
                _logs[index],
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: _getLogColor(_logs[index]),
                ),
              );
            },
          ),
        ),
        if (_isTesting)
          const Positioned.fill(
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Color _getLogColor(String log) {
    if (log.contains('Lỗi') || log.contains('Thất bại')) {
      return Colors.red;
    } else if (log.contains('Hoàn tất') || log.contains('Thành công')) {
      return Colors.green;
    } else if (log.contains('Cuộc trò chuyện') || log.contains('对话ID')) {
      return Colors.blue;
    } else {
      return Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;
    }
  }
}
