import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' show imageCache;
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
/// 防止后台重试与播放前兜底并发调用 AudioService.init。
bool _audioInitInFlight = false;

/// 系统 AudioService 重建 handler 后，把已挂好的状态迁到新实例：
/// allowPlay 与 next/prev 回调原先只挂在旧 handler 上，不迁移会导致
/// 重建后方向盘/通知栏 play 被吞、切歌回调丢失。
void _adoptNewHandler(MyAudioHandler h) {
  final old = audioHandler;
  h.allowPlay = old.allowPlay;
  h.onSkipNext = old.onSkipNext;
  h.onSkipPrevious = old.onSkipPrevious;
  audioHandler = h;
}

/// 重新初始化系统音频服务：后台重试与播放前兜底都走这里。
/// 播放路径一律 unawaited 调用，绝不让 MediaSession 就绪成为播放的前置条件。
Future<void> ensureSystemAudioHandler() async {
  if (audioServiceReady || _audioInitInFlight) return;
  _audioInitInFlight = true;
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
    ).timeout(const Duration(seconds: 8));
    _adoptNewHandler(h);
    audioServiceReady = true;
    debugPrint('AudioService init OK');
  } catch (e) {
    debugPrint('AudioService init failed: $e');
  } finally {
    _audioInitInFlight = false;
  }
}

/// AudioService 初始化失败后的后台持续重试：车机性能弱时 init 可能超时，
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
  // 车机内存有限：Flutter 默认图片缓存可达 100MB / 1000 张，长列表滚动后
  // 会常驻大量解码位图。配合封面按显示尺寸解码，这里再兜一个总量上限。
  imageCache
    ..maximumSizeBytes = 48 << 20
    ..maximumSize = 80;
  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  } catch (_) {}

  // 上电冷启动修复：先给一个立即可用的本地 handler，再 runApp。
  // 原实现把 AudioService.init().timeout(30s) 放在 runApp 之前 await，
  // 车机上电时音频服务慢会让整个界面最长卡 30 秒（白屏 / 点不动）。
  audioHandler = MyAudioHandler();
  audioServiceReady = false;

  final settings = AppSettings();
  await settings.load();
  runApp(MyApp(settings: settings));

  // 系统级 MediaSession 改为首帧之后在后台初始化，不阻塞界面与播放；
  // 失败时由 _retryAudioServiceUntilReady 每 10 秒重试，直到迪友能枚举到。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(ensureSystemAudioHandler());
    // 首次后台初始化失败时，挂一条每 10 秒的守护重试链，直到 MediaSession 就绪。
    // 重试循环本身会在 audioServiceReady 变 true 后自行停止，只有一条链。
    _retryAudioServiceUntilReady();
  });
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
            // 大屏（横竖）整体放大：车机横屏 1.5x / 竖屏大屏 1.3x，手机保持收敛区间
            // 注意：车机放大必须用乘法(raw*系数)，否则 raw≈1.0 会被 clamp 只抬到下限 1.15，字号依旧偏小。
            final isBig = size.shortestSide >= 480;
            final isLand = size.width > size.height;
            final raw = mq.textScaler.scale(14);
            final scale = isBig
                ? (raw * (isLand ? 1.5 : 1.6)).clamp(1.2, 2.2)
                : raw.clamp(0.9, 1.2);
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
    // 启动权限申请：必须等首帧渲染完（Activity 处于 resume）再请求。
    // 上电冷启动修复：不再用模态对话框——它会吃掉刚进 App 的第一次点击，
    // 表现为「刚进去那首歌点播放没反应」。改为非模态 SnackBar，点击不阻断。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      try {
        if (!await notificationGranted()) {
          if (!mounted) return;
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 12),
              content: const Text('开启通知权限后，车机桌面才能识别音素并显示播放控制'),
              action: SnackBarAction(
                label: '去授权',
                onPressed: () => ensureAppPermissions(),
              ),
            ),
          );
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
      // 未配置 Navidrome：保留/创建占位 controller（client=null），
      // 首页榜单/歌单广场/搜索/ID歌单/本地仍可用；播放与 NAS 歌单需先配置（首次进入弹窗引导）。
      if (_client != null) {
        _controller?.dispose();
        _controller = null;
        _client = null;
      }
      _controller ??= PlayerController(null, s);
    } else if (_client == null) {
      if (_controller != null) _controller!.dispose(); // 替换占位 controller
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
    // 未配置 Navidrome 时也进入首页（占位 controller），首次进入会弹窗引导配置。
    return HomeShell(settings: widget.settings, controller: controller);
  }
}
