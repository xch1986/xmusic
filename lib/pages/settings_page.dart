import 'package:flutter/material.dart';

import '../app_version.dart';
import '../player_controller.dart';
import '../settings.dart';

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
              decoration: const InputDecoration(labelText: 'WebDAV 地址', isDense: true),
            ),
            TextField(controller: userCtl, decoration: const InputDecoration(labelText: '用户名', isDense: true)),
            TextField(controller: passCtl, obscureText: true, decoration: const InputDecoration(labelText: '密码', isDense: true)),
            TextField(controller: pathCtl, decoration: const InputDecoration(labelText: '下载路径（如 /Music/）', isDense: true)),
            TextField(controller: nameCtl, decoration: const InputDecoration(labelText: 'NAS 名称（如 飞牛）', isDense: true)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
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

  void _showColorPicker(BuildContext context, String title, int currentColor, ValueChanged<int> onPick) {
    int r = currentColor != 0 ? (currentColor >> 16) & 0xFF : 255;
    int g = currentColor != 0 ? (currentColor >> 8) & 0xFF : 255;
    int b = currentColor != 0 ? currentColor & 0xFF : 255;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity, height: 50,
                decoration: BoxDecoration(
                  color: Color.fromARGB(255, r, g, b),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 8),
              _rgbSlider('R', r, (v) => setD(() => r = v)),
              _rgbSlider('G', g, (v) => setD(() => g = v)),
              _rgbSlider('B', b, (v) => setD(() => b = v)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                onPick((0xFF << 24) | (r << 16) | (g << 8) | b);
                Navigator.of(ctx).pop();
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rgbSlider(String label, int value, ValueChanged<int> onChanged) {
    return Row(children: [
      SizedBox(width: 16, child: Text(label, style: const TextStyle(fontSize: 12))),
      Expanded(child: Slider(value: value.toDouble(), min: 0, max: 255, divisions: 255, onChanged: (v) => onChanged(v.round()))),
      SizedBox(width: 28, child: Text('$value', style: const TextStyle(fontSize: 11))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // ===== 主题 =====
          _sectionTitle(theme, '主题'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题模式'),
            subtitle: Text(_themeName(settings.themeMode)),
            onTap: () => _showThemeModeDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.blur_on_rounded),
            title: const Text('玻璃通透度'),
            subtitle: Text('${(settings.glassOpacity * 100).round()}% 不透明'),
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: settings.glassOpacity,
                min: 0.1, max: 1.0, divisions: 9,
                onChanged: (v) => settings.setGlassOpacity(v),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.color_lens_outlined),
            title: const Text('自定义背景色'),
            trailing: settings.bgColor != 0
                ? Container(width: 24, height: 24, decoration: BoxDecoration(color: Color(settings.bgColor), borderRadius: BorderRadius.circular(4)))
                : const Text('默认'),
            onTap: () => _showColorPicker(context, '背景色', settings.bgColor, (c) => settings.setBgColor(c)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.play_circle_outline_rounded),
            title: const Text('启动时自动播放'),
            value: settings.autoPlay,
            onChanged: (v) => settings.setAutoPlay(v),
          ),
          const Divider(),

          // ===== 源 =====
          _sectionTitle(theme, '源'),
          ListTile(
            leading: const Icon(Icons.dns_rounded),
            title: const Text('Navidrome 服务器'),
            subtitle: Text(settings.hasLogin ? '${settings.username}@${settings.serverUrl}' : '未登录'),
            trailing: settings.hasLogin
                ? TextButton(onPressed: () => settings.clearLogin(), child: const Text('退出'))
                : const Icon(Icons.chevron_right),
          ),
          ListTile(
            leading: const Icon(Icons.api_rounded),
            title: const Text('外部API地址'),
            subtitle: Text(settings.externalApiUrl),
            onTap: () => _showExternalApiDialog(context),
          ),
          const Divider(),

          // ===== 歌词 =====
          _sectionTitle(theme, '歌词'),
          ListTile(
            leading: const Icon(Icons.format_size_rounded),
            title: const Text('歌词大小'),
            subtitle: Text('${(settings.lyricScale * 100).round()}%'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.remove), onPressed: settings.canDecreaseLyric ? () => settings.decreaseLyric() : null),
                IconButton(icon: const Icon(Icons.add), onPressed: settings.canIncreaseLyric ? () => settings.increaseLyric() : null),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.volume_up_rounded, color: Colors.amber),
            title: const Text('当前行颜色'),
            onTap: () => _showColorPicker(context, '当前行颜色', settings.lyricActive, (c) => settings.setLyricColors(active: c)),
          ),
          ListTile(
            leading: const Icon(Icons.check_circle_outline, color: Colors.green),
            title: const Text('已唱行颜色'),
            onTap: () => _showColorPicker(context, '已唱行颜色', settings.lyricPast, (c) => settings.setLyricColors(past: c)),
          ),
          ListTile(
            leading: const Icon(Icons.radio_button_unchecked, color: Colors.grey),
            title: const Text('未唱行颜色'),
            onTap: () => _showColorPicker(context, '未唱行颜色', settings.lyricFuture, (c) => settings.setLyricColors(future: c)),
          ),
          const Divider(),

          // ===== 下载 =====
          _sectionTitle(theme, '下载'),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('WebDAV (NAS)'),
            subtitle: Text(settings.webdavConfigured ? settings.webdavUrl : '未配置'),
            onTap: () => _showWebdavDialog(context),
          ),
          const Divider(),

          // ===== 关于 =====
          _sectionTitle(theme, '关于'),
          const ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('音素 xmusic'),
            subtitle: Text('Navidrome / Subsonic 客户端'),
          ),
          ListTile(
            leading: const Icon(Icons.tag_rounded),
            title: const Text('版本'),
            subtitle: const Text(appVersion),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );
  }

  String _themeName(AppThemeMode m) {
    switch (m) {
      case AppThemeMode.system: return '跟随系统';
      case AppThemeMode.light: return '浅色';
      case AppThemeMode.dark: return '深色';
    }
  }

  void _showThemeModeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('主题模式'),
        children: [
          for (final m in AppThemeMode.values)
            RadioListTile<AppThemeMode>(
              value: m,
              groupValue: settings.themeMode,
              title: Text(_themeName(m)),
              onChanged: (v) {
                if (v != null) settings.setThemeMode(v);
                Navigator.of(ctx).pop();
              },
            ),
        ],
      ),
    );
  }

  void _showExternalApiDialog(BuildContext context) {
    final ctl = TextEditingController(text: settings.externalApiUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('外部API地址'),
        content: TextField(controller: ctl, decoration: const InputDecoration(hintText: 'https://music-api.gdstudio.xyz')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(onPressed: () { settings.setExternalApiUrl(ctl.text); Navigator.of(ctx).pop(); }, child: const Text('保存')),
        ],
      ),
    );
  }
}
