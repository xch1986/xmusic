import 'package:flutter/material.dart';

import '../settings.dart';
import '../subsonic.dart';
import 'mini_player.dart';
import 'home_shell.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.settings, this.controller});

  final AppSettings settings;
  final dynamic controller;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final _url = TextEditingController(text: widget.settings.serverUrl);
  late final _user = TextEditingController(text: widget.settings.username);
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final salt = SubsonicClient.randomSalt();
    final client = SubsonicClient(
      baseUrl: _url.text.trim(),
      username: _user.text.trim(),
      salt: salt,
      token: SubsonicClient.makeToken(_pass.text, salt),
    );

    try {
      await client.ping();
      await widget.settings.saveLogin(client);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '连接失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isCarScreen = mq.size.shortestSide >= 480;
    final isLandscape = mq.size.width > mq.size.height;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    shrinkWrap: true,
                    children: [
                      Text('连接到服务器',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _url,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: '服务器地址',
                          hintText: 'https://music.example.com',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _user,
                        decoration: const InputDecoration(
                          labelText: '用户名',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pass,
                        obscureText: true,
                        onSubmitted: (_) => _busy ? null : _login(),
                        decoration: const InputDecoration(
                          labelText: '密码',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _login,
                        child: _busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('登录'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 底部miniplayer+导航栏
            MiniPlayer(settings: widget.settings, controller: widget.controller),
            Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.shadow.withOpacity(0.12),
                    blurRadius: 18,
                    offset: const Offset(0, -4),
                  ),
                ],
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.35),
                    width: 0.5,
                  ),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.only(bottom: isCarScreen && isLandscape ? 60 : 0),
                child: NavigationBarTheme(
                  data: NavigationBarThemeData(
                    backgroundColor: widget.settings.coverColorBg
                        ? Colors.transparent
                        : Theme.of(context).colorScheme.surfaceContainer,
                    height: isCarScreen ? (isLandscape ? 64 : 84) : (isLandscape ? 56 : 64),
                    iconTheme: WidgetStateProperty.resolveWith((states) =>
                        IconThemeData(size: isCarScreen ? 34 : 24)),
                  ),
                  child: NavigationBar(
                    selectedIndex: 0,
                    onDestinationSelected: (i) {
                      HomeShell.switchToTab(i);
                      Navigator.of(context).pop();
                    },
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
    );
  }
}
