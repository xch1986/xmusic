import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:permission_handler/permission_handler.dart';

import 'audio_handler.dart';
import 'pages/home_shell.dart';
import 'pages/login_page.dart';
import 'player_controller.dart';
import 'settings.dart';
import 'subsonic.dart';

/// 全局 audio handler（通知栏/车机/锁屏控制）。
late MyAudioHandler audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 首次启动请求通知权限（Android 13+ 需要运行时申请）。
  try {
    await Permission.notification.request();
  } catch (_) {}
  // 初始化系统级音频服务。包 try-catch+timeout：失败不阻塞启动（避免白屏）。
  try {
    audioHandler = await AudioService.init(
      builder: () => MyAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.xmusic.player.channel.audio',
        androidNotificationChannelName: '音乐播放',
        androidNotificationChannelDescription: '音素音乐播放器',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    ).timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint('AudioService init failed: $e');
    audioHandler = MyAudioHandler();
  }
  final settings = AppSettings();
  await settings.load();
  runApp(MyApp(settings: settings));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.settings});

  final AppSettings settings;

  static const _seed = Color(0xFF4A7CF7);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final a = (settings.glassOpacity * 255).round();
        final lightBg = Color(a << 24 | 0xEAF0FA);
        final darkBg = Color(a << 24 | 0x141820);
        return MaterialApp(
          title: '音素',
          debugShowCheckedModeBanner: false,
          themeMode: switch (settings.themeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          theme: ThemeData(
            scaffoldBackgroundColor: lightBg,
            appBarTheme: const AppBarTheme(
                backgroundColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0),
            navigationBarTheme: NavigationBarThemeData(
                backgroundColor: lightBg,
                elevation: 0,
                labelTextStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12))),
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: _seed,
              brightness: Brightness.light,
              surface: const Color(0xFFEAF0FA),
              surfaceContainerHighest: const Color(0xFFD8E2F5),
            ),
          ),
          darkTheme: ThemeData(
            scaffoldBackgroundColor: darkBg,
            appBarTheme: const AppBarTheme(
                backgroundColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0),
            navigationBarTheme: NavigationBarThemeData(
                backgroundColor: darkBg,
                elevation: 0,
                labelTextStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12))),
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: _seed,
              brightness: Brightness.dark,
              surface: const Color(0xFF1E2433),
              surfaceContainerHighest: const Color(0xFF2A3145),
            ),
          ),
          home: Root(settings: settings),
        );
      },
    );
  }
}

class Root extends StatefulWidget {
  const Root({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  PlayerController? _controller;
  SubsonicClient? _client;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettings);
    _sync();
  }

  void _sync() {
    final s = widget.settings;
    if (!s.hasLogin) {
      _controller?.dispose();
      _controller = null;
      _client = null;
    } else if (_client == null) {
      _client = s.buildClient();
      _controller = PlayerController(_client!, s);
      _controller!.restoreLastState();
    }
  }

  void _onSettings() {
    setState(_sync);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettings);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return LoginPage(settings: widget.settings);
    return HomeShell(settings: widget.settings, controller: controller);
  }
}
