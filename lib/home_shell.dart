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
          NavigationBar(
            backgroundColor: Colors.transparent,
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
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
        ],
      ),
    );
  }
}
