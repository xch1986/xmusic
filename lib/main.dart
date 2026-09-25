import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:permission_handler/permission_handler.dart';

import 'audio_handler.dart';
import 'pages/home_shell.dart';
import 'pages/login_page.dart';
import 'permissions.dart';
import 'player_controller.dart';
import 'settings.dart';
import 'subsonic.dart';
import 'theme.dart';

/// 全局 audio handler（通知栏/车机/锁屏控制）。
late MyAudioHandler audioHandler;
/// 系统级 AudioService 是否就绪。init 失败（车机慢/超时）时 fallback 本地 handler，
/// 此时没有系统 MediaSession，车机桌面（迪友）枚举不到——首次播放前会重试。
bool audioServiceReady = false;

/// 重新初始化系统音频服务：仅当首次 init 失败时调用（播放前兜底）。
Future<void> ensureSystemAudioHandler() async {
  if (audioServiceReady) return;
  try {
    final h = await AudioService.init(
      builder: () => MyAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.xmusic.player.channel.audio',
        androidNotificationChannelName: '音乐播放',
        androidNotificationChannelDescription: '音素音乐播放器',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidShowNotificationBadge: true,
        androidNotificationClickStartsActivity: true,
      ),
    ).timeout(const Duration(seconds: 30));
    audioHandler = h;
    audioServiceReady = true;
    debugPrint('AudioService re-init OK');
  } catch (e) {
    debugPrint('AudioService re-init failed: $e');
  }
}

/// AudioService 初始化失败后的后台持续重试：车机性能弱时 init 常 30s 超时，
/// 若长期 fallback 本地 handler 则没有系统 MediaSession/通知栏媒体通知，
/// 迪友等车机桌面枚举不到播放器。每 10 秒重试直到成功（成功即停）。
void _retryAudioServiceUntilReady() {
  Future.delayed(const Duration(seconds: 10), () async {
    if (audioServiceReady) return;
    await ensureSystemAudioHandler();
    if (!audioServiceReady) _retryAudioServiceUntilReady();
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 显式允许所有四个方向（空列表在部分 Android/Flutter 版本上不生效或反而锁方向），
  // 播放页支持横竖屏切换（车机/手机），跟随系统自动旋转。
  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  } catch (_) {}

  // 初始化系统级音频服务。包 try-catch+timeout：失败不阻塞启动（避免白屏）。
  // 车机性能弱/启动慢：超时放宽到 30s，仍失败则 fallback + 后台持续重试，
  // 保证服务常驻激活（MediaSession + 媒体通知），迪友车机桌面才能枚举到。
  try {
    audioHandler = await AudioService.init(
      builder: () => MyAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.xmusic.player.channel.audio',
        androidNotificationChannelName: '音乐播放',
        androidNotificationChannelDescription: '音素音乐播放器',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidShowNotificationBadge: true,
        androidNotificationClickStartsActivity: true,
      ),
    ).timeout(const Duration(seconds: 30));
    audioServiceReady = true;
  } catch (e) {
    debugPrint('AudioService init failed: $e');
    audioHandler = MyAudioHandler();
    // 车机慢导致 init 超时的场景：后台持续重试，直到 MediaSession 注册成功。
    _retryAudioServiceUntilReady();
  }
  final settings = AppSettings();
  await settings.load();
  runApp(MyApp(settings: settings));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return MaterialApp(
          title: '音素音乐',
          debugShowCheckedModeBanner: false,
          themeMode: switch (settings.themeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          theme: AppTheme.light(settings),
          darkTheme: AppTheme.dark(settings),
          // 文字缩放：手机保持收敛区间（防车机/系统字体过大撑高列表行）；
          // 车机（横屏大屏）单独适配——物理屏大、观看距离远，基础字号放大一档。
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final size = mq.size;
            final isCarScreen = size.width > size.height && size.shortestSide >= 480;
            final raw = mq.textScaler.scale(14);
            final scale = isCarScreen ? raw.clamp(1.15, 1.3) : raw.clamp(0.9, 1.2);
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            );
          },
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

class _RootState extends State<Root> with WidgetsBindingObserver {
  PlayerController? _controller;
  SubsonicClient? _client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settings.addListener(_onSettings);
    _sync();
    // 启动权限申请：必须等首帧渲染完（Activity 处于 resume）再请求，
    // main() 里 runApp 前请求会被系统忽略（0.3.96 实测不弹框）。
    // 逐项弹系统勾选框：通知(Android 13+)/音频/图片/存储——通知权限缺失时
    // 媒体通知不显示，迪友(通知监听)识别不到播放器。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      try {
        // 通知未授予时先弹 App 内引导框，用户点"去授权"再走系统请求；
        // 保证一定出现"申请权限"界面（部分 ROM/Android 16 上直接 request 不弹框）。
        if (!await notificationGranted()) {
          if (!mounted) return;
          final go = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('需要通知权限'),
              content: const Text(
                  '用于在通知栏显示播放控制，以及让车机（迪友）识别音素为音乐播放器。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('稍后'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('去授权'),
                ),
              ],
            ),
          );
          if (go == true) await ensureAppPermissions();
        } else {
          await ensureAppPermissions();
        }
      } catch (_) {}
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切后台/退出/强制清后台前，保存最新播放状态（曲目+进度+队列），
    // 避免重启后恢复的是最初点开的那首歌而不是退出时正在播的。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _controller?.saveLastState();
    }
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
    WidgetsBinding.instance.removeObserver(this);
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
