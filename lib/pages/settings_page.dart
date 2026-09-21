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

  void _showColorPicker(BuildContext context, String title, int currentColor, ValueChanged<int> onPick, {bool isTheme = false}) {
    double alpha = currentColor != 0 ? (currentColor >> 24) / 255.0 : 1.0;
    HSVColor hsv = currentColor != 0 ? HSVColor.fromColor(Color(currentColor)) : HSVColor.fromColor(Colors.amber);
    final hexCtl = TextEditingController(text: currentColor != 0 ? '#${(currentColor & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0').toUpperCase()}' : '');

    // 主题色：低饱和、精简（参考QQ/网易云播放器配色）
    final themePresets = [
      const Color(0xFF6B8CC4), // QQ蓝
      const Color(0xFFC46B6B), // 网易红
      const Color(0xFF6BB88C), // 清新绿
      const Color(0xFF9B7EC4), // 优雅紫
      const Color(0xFFC4A86B), // 暖橙
      const Color(0xFFC46B9B), // 樱粉
      const Color(0xFF6BB8B8), // 青碧
      const Color(0xFF8C8C9E), // 雾灰
      const Color(0xFF5C6B8C), // 深蓝灰
      const Color(0xFF8C7A6B), // 暖棕
    ];
    // 歌词色：鲜艳高对比
    final lyricPresets = [
      const Color(0xFFFFFFFF), // 白
      const Color(0xFFFFFF00), // 亮黄
      const Color(0xFF00FFFF), // 青
      const Color(0xFF00FF88), // 绿
      const Color(0xFFFF6B9B), // 粉
      const Color(0xFFFF8C42), // 橙
      const Color(0xFFB366FF), // 紫
      const Color(0xFF8899AA), // 灰蓝（已唱）
      const Color(0xFF666677), // 深灰（未唱）
      const Color(0xFFCCDDFF), // 淡蓝白
    ];
    final presets = isTheme ? themePresets : lyricPresets;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final c = hsv.toColor().withOpacity(alpha);
          return AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 十六进制
                  Row(children: [
                    Container(width: 40, height: 40, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: hexCtl,
                        decoration: const InputDecoration(labelText: '十六进制', isDense: true),
                        onChanged: (v) {
                          final hex = v.replaceAll('#', '').trim();
                          if (hex.length == 8) {
                            final val = int.tryParse(hex, radix: 16);
                            if (val != null) setD(() { alpha = (val >> 24) / 255.0; hsv = HSVColor.fromColor(Color(val)); });
                          } else if (hex.length == 6) {
                            final val = int.tryParse(hex, radix: 16);
                            if (val != null) setD(() => hsv = HSVColor.fromColor(Color(0xFF000000 | val)));
                          }
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  // 调色板
                  const Text('调色板', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12, runSpacing: 12,
                    children: presets.map((col) => GestureDetector(
                      onTap: () => setD(() => hsv = HSVColor.fromColor(col)),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: col, shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24, width: 2),
                        ),
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 16),
                  // 精细调整
                  const Text('精细调整', style: TextStyle(fontWeight: FontWeight.bold)),
                  _slider('透明度', alpha, 0, 1, (v) => setD(() => alpha = v)),
                  _slider('色相', hsv.hue, 0, 360, (v) => setD(() => hsv = HSVColor.fromAHSV(alpha, v / 360.0, hsv.saturation, hsv.value))),
                  _slider('饱和度', hsv.saturation, 0, 1, (v) => setD(() => hsv = HSVColor.fromAHSV(alpha, hsv.hue / 360.0, v, hsv.value))),
                  _slider('明度', hsv.value, 0, 1, (v) => setD(() => hsv = HSVColor.fromAHSV(alpha, hsv.hue / 360.0, hsv.saturation, v))),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
              TextButton(
                onPressed: () { onPick(0); Navigator.of(ctx).pop(); },
                child: const Text('跟随默认'),
              ),
              FilledButton(
                onPressed: () {
                  final rgb = (hsv.toColor().value & 0xFFFFFF);
                  onPick(((alpha * 255).round() << 24) | rgb);
                  Navigator.of(ctx).pop();
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _slider(String label, double val, double min, double max, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 60, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(child: Slider(value: val, min: min, max: max, onChanged: onChanged)),
        SizedBox(width: 40, child: Text(val.toStringAsFixed(2), style: const TextStyle(fontSize: 12))),
      ]),
    );
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
            onTap: () => _showColorPicker(context, '背景色', settings.bgColor, (c) => settings.setBgColor(c), isTheme: true),
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
            trailing: settings.lyricActive != 0
                ? Container(width: 24, height: 24, decoration: BoxDecoration(color: Color(settings.lyricActive), borderRadius: BorderRadius.circular(4)))
                : const Text('默认'),
            onTap: () => _showColorPicker(context, '当前行颜色', settings.lyricActive, (c) => settings.setLyricColors(active: c)),
          ),
          ListTile(
            leading: const Icon(Icons.check_circle_outline, color: Colors.green),
            title: const Text('已唱行颜色'),
            trailing: settings.lyricPast != 0
                ? Container(width: 24, height: 24, decoration: BoxDecoration(color: Color(settings.lyricPast), borderRadius: BorderRadius.circular(4)))
                : const Text('默认'),
            onTap: () => _showColorPicker(context, '已唱行颜色', settings.lyricPast, (c) => settings.setLyricColors(past: c)),
          ),
          ListTile(
            leading: const Icon(Icons.radio_button_unchecked, color: Colors.grey),
            title: const Text('未唱行颜色'),
            trailing: settings.lyricFuture != 0
                ? Container(width: 24, height: 24, decoration: BoxDecoration(color: Color(settings.lyricFuture), borderRadius: BorderRadius.circular(4)))
                : const Text('默认'),
            onTap: () => _showColorPicker(context, '未唱行颜色', settings.lyricFuture, (c) => settings.setLyricColors(future: c)),
          ),
          const Divider(),

          // ===== 下载 =====
          _sectionTitle(theme, '下载'),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('本地下载路径'),
            subtitle: Text(settings.downloadPath.isEmpty ? '/storage/emulated/0/Music' : settings.downloadPath),
            onTap: () async {
              final ctl = TextEditingController(text: settings.downloadPath.isEmpty ? '/storage/emulated/0/Music' : settings.downloadPath);
              await showDialog(context: context, builder: (ctx) => AlertDialog(
                title: const Text('本地下载路径'),
                content: TextField(controller: ctl, decoration: const InputDecoration(hintText: '/storage/emulated/0/Music')),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), TextButton(onPressed: () { settings.downloadPath = ctl.text.trim(); Navigator.pop(ctx); }, child: const Text('保存'))],
              ));
            },
          ),
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