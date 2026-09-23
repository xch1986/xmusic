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

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

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
        ],
      ),
    );
  }
}
