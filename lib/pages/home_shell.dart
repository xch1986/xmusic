import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cover_glass.dart';
import '../player_controller.dart';
import '../settings.dart';
import 'home_page.dart';
import 'library_page.dart';
import 'mini_player.dart';
import 'player_page.dart';
import 'search_page.dart';
import 'settings_page.dart';

/// Main shell with bottom navigation: 首页 / 音乐库 / 搜索 / 设置.
/// The mini player sits above the navigation bar.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.settings, required this.controller});

  final AppSettings settings;
  final PlayerController controller;

  /// 播放页「主页」按钮调用：pop 回壳后切到首页 tab。
  /// 用 ++ 而不是直接赋值 0：ValueNotifier 同值不通知，若上次已是 0 会失效。
  static void switchToHome() => switchToTab(0);

  /// 跨页面请求切换到指定 tab（0 首页 / 1 音乐库 / 2 搜索 / 3 设置）。
  /// 播放页"主页"调 switchToHome；首次进入的"前往配置"弹窗调 switchToTab(3)。
  static void switchToTab(int tab) {
    _HomeShellState._tabRequest.value = tab;
    _HomeShellState._tabPing.value++; // 触发通知（同值切换也生效）
  }

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  /// [xmusic] 打开 App 默认进入播放界面：冷启动首次挂载时自动 push 播放页（仅一次）。
  bool _autoOpened = false;
  /// 跨页面（播放页"主页"按钮）请求切换 tab：值 = 目标 tab 下标。
  static final ValueNotifier<int> _tabRequest = ValueNotifier<int>(0);
  /// 触发计数器：每次 switchToTab 递增，保证同值请求也能通知到监听者。
  static final ValueNotifier<int> _tabPing = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _tabRequest.addListener(_onTabRequest);
    _tabPing.addListener(_onTabRequest);
    // [xmusic] 冷启动默认进播放页：首帧渲染后 push 一次（不重复）。
    // 未配置 Navidrome 时不自动进播放页（无播放队列），改为弹"前往配置"提醒。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _autoOpened) return;
      _autoOpened = true;
      if (!widget.settings.hasLogin) {
        _maybeShowNavidromeHint();
        return;
      }
      openPlayerPage(
        context, settings: widget.settings, controller: widget.controller,
      );
    });
  }

  /// 首次进入且未配置 Navidrome：弹窗提醒前往设置配置；可勾选"下次不再提醒"。
  void _maybeShowNavidromeHint() {
    if (widget.settings.navHintDismissed) return;
    var dontAsk = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('欢迎使用音素音乐'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('配置 Navidrome 服务器后即可获得完整功能体验：个人歌单、NAS 同步与完整播放。现在可以先浏览榜单、歌单广场和搜索。'),
              const SizedBox(height: 4),
              CheckboxListTile(
                value: dontAsk,
                onChanged: (v) => setDlgState(() => dontAsk = v ?? false),
                title: const Text('下次不再提醒'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('我知道了'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('前往配置'),
            ),
          ],
        ),
      ),
    ).then((go) async {
      if (!mounted) return;
      if (dontAsk) await widget.settings.setNavHintDismissed(true);
      if (go == true) HomeShell.switchToTab(3);
    });
  }

  @override
  void dispose() {
    _tabRequest.removeListener(_onTabRequest);
    _tabPing.removeListener(_onTabRequest);
    super.dispose();
  }

  void _onTabRequest() {
    if (!mounted) return;
    // 收到 tab 请求即切到目标 tab（播放页"主页"=0；"前往配置"=3）。
    setState(() => _tab = _tabRequest.value);
  }

  @override
  Widget build(BuildContext context) {
    // 车机识别（横屏大屏）：导航栏 label/图标放大一档，方便驾驶中远距离看清
    final mq = MediaQuery.of(context);
    // [xmusic] 2026-09-28 大屏判定扩展到车机竖屏（最短边>=480dp），导航图标/字号一并放大
    final isCarScreen = mq.size.shortestSide >= 480;
    // 横屏：真正全屏沉浸（immersiveSticky），隐藏顶部状态栏+底部导航条，额头下巴都收掉
    final isLandscape = mq.size.width > mq.size.height;
    SystemChrome.setEnabledSystemUIMode(
      isLandscape
          ? SystemUiMode.immersiveSticky
          : SystemUiMode.manual,
      overlays: isLandscape ? const [] : SystemUiOverlay.values,
    );
    final pages = <Widget>[
      HomePage(settings: widget.settings, controller: widget.controller),
      LibraryPage(settings: widget.settings, controller: widget.controller),
      SearchPage(settings: widget.settings, controller: widget.controller),
      SettingsPage(settings: widget.settings, controller: widget.controller),
    ];

    final cs = Theme.of(context).colorScheme;
    final coverBg = widget.settings.coverColorBg;
    return PageBackground(
        controller: widget.controller,
        settings: widget.settings,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: (Theme.of(context).brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark)
          .copyWith(
              statusBarColor: coverBg ? Colors.transparent : cs.surfaceContainer),
      child: Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: EdgeInsets.only(
          top: isCarScreen && isLandscape ? 28 : 0,
        ),
        child: IndexedStack(index: _tab, children: pages),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MediaQuery(
            data: mq.copyWith(
              textScaler: TextScaler.linear(
                // 横屏播放控制栏整体压缩（0.85），竖屏按车机放大
                isLandscape
                    ? 0.85
                    : (mq.size.shortestSide >= 480 ? 1.25 : 1.0),
              ),
            ),
            child: MiniPlayer(settings: widget.settings, controller: widget.controller),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              // 柔和上投光 + 细边：导航栏浮在壁纸上的玻璃质感（不遮挡壁纸）
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, -4),
                ),
              ],
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 0.5,
                ),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: isCarScreen && isLandscape ? 60 : 0,
              ),
              child: NavigationBarTheme(
            // [xmusic] 2026-09-24 车机图标适配：底部导航图标放大
            // NavigationBar 无 iconSize 参数，图标尺寸由 NavigationBarThemeData.iconTheme 控制
            data: NavigationBarThemeData(
              backgroundColor:
                  coverBg ? Colors.transparent : cs.surfaceContainer,
              height: isCarScreen ? (isLandscape ? 64 : 84) : (isLandscape ? 56 : 64),
              iconTheme: WidgetStateProperty.resolveWith((states) =>
                  IconThemeData(size: isCarScreen ? 34 : 24)),
            ),
            child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: isCarScreen ? 17 : 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            )),

            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: '首页',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music_rounded),
                label: '音乐库',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_rounded),
                selectedIcon: Icon(Icons.search_rounded),
                label: '搜索',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: '设置',
              ),
            ],
          ),
          ),
          ),
          ),
        ],
      ),
      ),
      ),
    );
  }
}
