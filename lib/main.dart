import 'package:flutter/material.dart';

import 'pages/home_shell.dart';
import 'pages/login_page.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'player_controller.dart';
import 'settings.dart';
import 'subsonic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化系统级 MediaSession：车机/蓝牙耳机/锁屏/通知栏才能识别本应用并支持方向盘按键。
  // 包 try-catch + timeout：即使初始化失败也不阻塞 App 启动（避免白屏）。
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.xmusic.player.channel.audio',
      androidNotificationChannelName: '音乐播放',
      androidNotificationOngoing: true,
    ).timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('JustAudioBackground init failed: $e');
  }
  final settings = AppSettings();
  await settings.load();
  runApp(MyApp(settings: settings));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.settings});

  final AppSettings settings;

  // One fixed seed. Light/dark follows the system (or user override);
  // player colors never come from album art.
  static const _seed = Color(0xFF3D5AFE);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return MaterialApp(
          title: 'xmusic',
          debugShowCheckedModeBanner: false,
          themeMode: switch (settings.themeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          theme: ThemeData(
          scaffoldBackgroundColor: const Color(0x66FFFFFF),
            appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
            navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0x66FFFFFF), elevation: 0),
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: _seed,
              brightness: Brightness.light,
            ),
          ),
          darkTheme: ThemeData(
            scaffoldBackgroundColor: const Color(0x661A1A1A),
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: _seed,
              brightness: Brightness.dark,
            ),
          ),
          home: Root(settings: settings),
        );
      },
    );
  }
}

/// Switches between the login screen and the main shell depending on login
/// state and owns the [PlayerController] for the logged-in session.
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
