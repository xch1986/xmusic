import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../settings.dart';

/// Settings page: theme mode, lyric size, server info and logout.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.controller,
  });

  final AppSettings settings;
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // ---- 外观 ----
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('外观',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: Theme.of(context).colorScheme.primary)),
              ),
              ListTile(
                leading: const Icon(Icons.brightness_auto_rounded),
                title: const Text('主题模式'),
                subtitle: const Text('跟随系统 / 浅色 / 深色'),
                trailing: DropdownButton<AppThemeMode>(
                  value: settings.themeMode,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                      value: AppThemeMode.system,
                      child: Text('跟随系统'),
                    ),
                    DropdownMenuItem(
                      value: AppThemeMode.light,
                      child: Text('浅色'),
                    ),
                    DropdownMenuItem(
                      value: AppThemeMode.dark,
                      child: Text('深色'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) settings.setThemeMode(v);
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.text_fields_rounded),
                title: const Text('歌词字号'),
                subtitle: Text('${(settings.lyricScale * 100).round()}%'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '减小',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: settings.canDecreaseLyric
                          ? settings.decreaseLyric
                          : null,
                    ),
                    IconButton(
                      tooltip: '增大',
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: settings.canIncreaseLyric
                          ? settings.increaseLyric
                          : null,
                    ),
                  ],
                ),
              ),
              const Divider(),

              // ---- 账号 ----
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('账号',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: Theme.of(context).colorScheme.primary)),
              ),
              ListTile(
                leading: const Icon(Icons.dns_rounded),
                title: const Text('服务器'),
                subtitle: Text(settings.serverUrl.isEmpty
                    ? '未配置'
                    : settings.serverUrl),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('用户名'),
                subtitle: Text(settings.username.isEmpty ? '-' : settings.username),
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('退出登录'),
                subtitle: const Text('清除服务器登录信息'),
                onTap: () => showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('退出登录'),
                    content: const Text('确定要退出当前账号吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          settings.clearLogin();
                        },
                        child: const Text('退出'),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),

              // ---- 关于 ----
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('关于',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: Theme.of(context).colorScheme.primary)),
              ),
              const ListTile(
                leading: Icon(Icons.info_outline_rounded),
                title: Text('My Player'),
                subtitle: Text('Navidrome / Subsonic 客户端 · v0.2.0'),
              ),
            ],
          );
        },
      ),
    );
  }
}
