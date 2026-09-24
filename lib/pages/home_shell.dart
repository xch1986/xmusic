import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../settings.dart';
import 'home_page.dart';
import 'library_page.dart';
import 'mini_player.dart';
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
  static void switchToHome() => _HomeShellState._tabRequest.value++;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  /// 跨页面（播放页"主页"按钮）请求切换 tab：值 = 目标 tab 下标。
  static final ValueNotifier<int> _tabRequest = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _tabRequest.addListener(_onTabRequest);
  }

  @override
  void dispose() {
    _tabRequest.removeListener(_onTabRequest);
    super.dispose();
  }

  void _onTabRequest() {
    if (!mounted) return;
    // _tabRequest 只服务于"回首页"：无论当前值如何，收到通知即切到首页 tab。
    setState(() => _tab = 0);
  }

  @override
  Widget build(BuildContext context) {
    // 车机识别（横屏大屏）：导航栏 label/图标放大一档，方便驾驶中远距离看清
    final mq = MediaQuery.of(context);
    final isCarScreen =
        mq.size.width > mq.size.height && mq.size.shortestSide >= 480;
    final pages = <Widget>[
      HomePage(settings: widget.settings, controller: widget.controller),
      LibraryPage(settings: widget.settings, controller: widget.controller),
      SearchPage(settings: widget.settings, controller: widget.controller),
      SettingsPage(settings: widget.settings, controller: widget.controller),
    ];

    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MiniPlayer(settings: widget.settings, controller: widget.controller),
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
            child: NavigationBarTheme(
            // [xmusic] 2026-09-24 车机图标适配：底部导航图标放大
            // NavigationBar 无 iconSize 参数，图标尺寸由 NavigationBarThemeData.iconTheme 控制
            data: NavigationBarThemeData(
              iconTheme: WidgetStateProperty.resolveWith((states) =>
                  IconThemeData(size: isCarScreen ? 30 : 24)),
            ),
            child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: isCarScreen ? 15 : 12,
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
        ],
      ),
    );
  }
}
