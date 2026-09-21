import 'package:flutter/material.dart';

import '../app_version.dart';
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

  void _showWebdavDialog(BuildContext context) {
    final urlCtl = TextEditingController(text: settings.webdavUrl);
    final userCtl = TextEditingController(text: settings.webdavUser);
    final passCtl = TextEditingController(text: settings.webdavPass);
    final pathCtl = TextEditingController(text: settings.webdavPath);
    final nameCtl = TextEditingController(text: settings.webdavName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('WebDAV (NAS)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlCtl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'WebDAV 地址',
                hintText: 'http://nas:5005/remote.php/dav/files/user/Music',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: userCtl,
              decoration: const InputDecoration(
                labelText: '用户名（可空）',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passCtl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码（可空）',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pathCtl,
              decoration: const InputDecoration(
                labelText: '下载路径（可空，如 /Music/）',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(
                labelText: 'NAS 名称（可空，如 飞牛）',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              settings.setWebdav(urlCtl.text, userCtl.text, passCtl.text, path: pathCtl.text, name: nameCtl.text);
              Navigator.of(ctx).pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

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

              // ---- 外网搜索 ----
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('外网搜索',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: Theme.of(context).colorScheme.primary)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _ExternalApiField(settings: settings),
              ),
              const SizedBox(height: 12),
              const Divider(),

              // ---- NAS 下载 (WebDAV) ----
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('NAS 下载',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: Theme.of(context).colorScheme.primary)),
              ),
              ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: const Text('WebDAV 地址'),
                subtitle: Text(settings.webdavConfigured
                    ? '${settings.webdavUrl}（${settings.webdavUser.isEmpty ? "无账号" : settings.webdavUser}）'
                    : '未配置，下载歌曲时上传到 NAS'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showWebdavDialog(context),
              ),
              const SizedBox(height: 12),
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
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('音素 xmusic'),
                subtitle: Text('Navidrome / Subsonic 客户端 · v$appVersion'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// External search API URL field that keeps its own controller so typing
/// is not reset when settings change.
class _ExternalApiField extends StatefulWidget {
  const _ExternalApiField({required this.settings});

  final AppSettings settings;

  @override
  State<_ExternalApiField> createState() => _ExternalApiFieldState();
}

class _ExternalApiFieldState extends State<_ExternalApiField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.settings.externalApiUrl);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.url,
      decoration: const InputDecoration(
        labelText: '外部搜索 API 地址',
        hintText: 'https://api.example.com',
        helperText: 'NeteaseCloudMusicApi 兼容服务（/search、/song/url）',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      onSubmitted: (v) => widget.settings.setExternalApiUrl(v),
    );
  }
}
