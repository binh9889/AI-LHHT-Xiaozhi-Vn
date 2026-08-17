import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:ai_assistant/providers/theme_provider.dart';
import 'package:ai_assistant/providers/config_provider.dart';
import 'package:ai_assistant/providers/conversation_provider.dart';
import 'package:ai_assistant/screens/home_screen.dart';
import 'package:ai_assistant/screens/settings_screen.dart';
import 'package:ai_assistant/screens/test_screen.dart';
import 'package:ai_assistant/utils/app_theme.dart';
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;
import 'package:opus_dart/opus_dart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:ui';
import 'package:ai_assistant/utils/audio_util.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

// 是否启用调试工具
const bool enableDebugTools = true;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cài đặt全局沉浸式导航栏
  await _setupSystemUI();

  // Cài đặt状态栏颜色变化监听器，确保状态栏样式始终如一
  SystemChannels.lifecycle.setMessageHandler((msg) async {
    if (msg == AppLifecycleState.resumed.toString()) {
      // 应用回到前台时重新应用系统UICài đặt
      await _setupSystemUI();
    }
    return null;
  });

  // Cài đặt高性能渲染
  if (Platform.isAndroid || Platform.isIOS) {
    // 启用SkSL预热，提高首次渲染性能
    await Future.delayed(const Duration(milliseconds: 50));
    PaintingBinding.instance.imageCache.maximumSize = 1000;
    // 增加图像缓存容量
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        100 * 1024 * 1024; // 100 MB
  }

  // 请求录音和存储权限
  await [
    Permission.microphone,
    Permission.storage,
    if (Platform.isAndroid) Permission.bluetoothConnect,
  ].request();

  // Thêm中Văn bản地化支持
  timeago.setLocaleMessages('zh', timeago.ZhMessages());
  timeago.setDefaultLocale('zh');

  // 在Android上Cài đặt高刷新率
  if (Platform.isAndroid) {
    try {
      // 获取所有支持的显示Chế độ
      final modes = await FlutterDisplayMode.supported;
      print('支持的显示Chế độ: ${modes.length}');
      modes.forEach((mode) => print('Chế độ: $mode'));

      // 获取当前活跃的Chế độ
      final current = await FlutterDisplayMode.active;
      print('当前Chế độ: $current');

      // Cài đặt为高刷新率Chế độ
      await FlutterDisplayMode.setHighRefreshRate();

      // 确认Cài đặtThành công
      final afterSet = await FlutterDisplayMode.active;
      print('Cài đặt后Chế độ: $afterSet');
    } catch (e) {
      print('Cài đặt高刷新率Thất bại: $e');
    }
  }

  // 初始化Opus库
  try {
    initOpus(await opus_flutter.load());
    print('Opus初始化Thành công: ${getOpusVersion()}');
  } catch (e) {
    print('Opus初始化Thất bại: $e');
  }

  // 初始化录音和播放器
  try {
    await AudioUtil.initRecorder();
    await AudioUtil.initPlayer();
    print('音频系统初始化Thành công');
  } catch (e) {
    print('音频系统初始化Thất bại: $e');
  }

  // 初始化cấu hình管理
  final configProvider = ConfigProvider();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider.value(value: configProvider),
        ChangeNotifierProvider(create: (_) => ConversationProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

// Cài đặt系统UI沉浸式效果
Future<void> _setupSystemUI() async {
  // Cài đặt状态栏和导航栏透明
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

  if (Platform.isAndroid) {
    // 启用边缘到边缘显示Chế độ，实现真正的全面屏效果
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  } else if (Platform.isIOS) {
    // iOS上Cài đặt为全屏显示但保留状态栏
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'AI-LHHT',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      home: const HomeScreen(),
      routes: {
        // ThêmKiểm tra界面路由
        '/test': (context) => const TestScreen(),
      },
      // Thêm平滑滚动Cài đặt
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        // 启用物理滚动
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        // 确保所有平台都有滚动条和弹性效果
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.stylus,
          PointerDeviceKind.unknown,
        },
      ),
    );
  }
}
