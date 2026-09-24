import 'dart:io';
import '../toast.dart';

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_version.dart';
import '../permissions.dart';
import '../player_controller.dart';
import '../settings.dart';
import '../widgets.dart';

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


  /// 取色弹窗文字细描边：弹窗内白字在浅色/自定义背景上可读（不压字）
  static TextStyle _stroke(TextStyle? base) => (base ?? const TextStyle());

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
            title: Text(title, style: _stroke(null)),
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
                        style: _stroke(Theme.of(ctx).textTheme.bodyLarge),
                        decoration: InputDecoration(
                          labelText: '十六进制',
                          isDense: true,
                          labelStyle: _stroke(null),
                        ),
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
                  Text('调色板', style: _stroke(const TextStyle(fontWeight: FontWeight.bold))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12, runSpacing: 12,
                    children: presets.map((col) => GestureDetector(
                      onTap: () => setD(() => hsv = HSVColor.fromColor(col)),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: col, shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: col.withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 16),
                  // 精细调整
                  Text('精细调整', style: _stroke(const TextStyle(fontWeight: FontWeight.bold))),
                  _slider('透明度', alpha, 0, 1, (v) => setD(() => alpha = v)),
                  _slider('色相', hsv.hue, 0, 360, (v) => setD(() => hsv = HSVColor.fromAHSV(alpha, v / 360.0, hsv.saturation, hsv.value))),
                  _slider('饱和度', hsv.saturation, 0, 1, (v) => setD(() => hsv = HSVColor.fromAHSV(alpha, hsv.hue / 360.0, v, hsv.value))),
                  _slider('明度', hsv.value, 0, 1, (v) => setD(() => hsv = HSVColor.fromAHSV(alpha, hsv.hue / 360.0, hsv.saturation, v))),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('取消', style: _stroke(null))),
              TextButton(
                onPressed: () { onPick(0); Navigator.of(ctx).pop(); },
                child: Text('跟随默认', style: _stroke(null)),
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
        SizedBox(width: 60, child: Text(label, style: _stroke(const TextStyle(fontSize: 13)))),
        Expanded(child: Slider(value: val, min: min, max: max, onChanged: onChanged)),
        SizedBox(width: 40, child: Text(val.toStringAsFixed(2), style: _stroke(const TextStyle(fontSize: 12)))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 车机横屏大屏：整页文字放大 1.35x
    final theme = Theme.of(context);
    final _mq = MediaQuery.of(context);
    final _car = isCarScreen(context);
    return MediaQuery(
      data: _car ? _mq.copyWith(textScaler: const TextScaler.linear(1.35)) : _mq,
      child: Builder(
        builder: (ctx) {
          return IconTheme(
        // [xmusic] 2026-09-24 车机图标适配：设置页列表图标整体放大
        data: IconThemeData(size: _car ? 28 : 24),
        child: Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // ===== 个性化（主题 + 歌词） =====
          _sectionTitle(theme, '个性化'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题模式'),
            subtitle: Text(_themeName(settings.themeMode)),
            onTap: () => _showThemeModeDialog(context),
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
          ),          const Divider(),

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
          // 外网搜索源：展示说明（不做单选，搜索时自动聚合全部源），
          // 点进去展示具体地址，只读不可改。
          ListTile(
            leading: const Icon(Icons.public_rounded),
            title: const Text('外网搜索源'),
            subtitle: const Text('自动聚合：网易云 / B站 / QQ / 聚合API\nQQ 播放受版权/VIP 限制，点击查看详情'),
            isThreeLine: true,
            onTap: () => _showSourcesInfo(context),
          ),
          ListTile(
            leading: const Icon(Icons.music_note_rounded, color: Colors.orange),
            title: const Text('QQ音乐 Cookie'),
            subtitle: Text(settings.qqCookie.trim().isEmpty
                ? '未设置：每日30首用酷狗+网易云兜底\n设置后解锁 QQ 榜单与播放（点击查看获取方法）'
                : '已设置：每日30首/QQ榜单自动启用\n点击可修改（Cookie 含登录态，勿外泄）'),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showQqCookieDialog(context),
          ),

          const Divider(),

          // ===== 权限 =====
          _sectionTitle(theme, '权限'),          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('权限检查'),
            subtitle: const Text('通知 / 存储 / 音乐 / 图片 缺失权限一键补全\n（车机识别与通知栏媒体控制需要通知权限）'),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final missing = await ensureAppPermissions();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(missing.isEmpty
                    ? '所有权限已授予'
                    : '以下权限未授予：' + missing.join('、')),
              ));
            },
          ),
          // [xmusic] 2026-09-24 悬浮窗权限入口：车机能识别的音乐应用(如 MobiMusic)通常有此权限，
          // 提供入口可手动开启，排除该变量。
          ListTile(
            leading: const Icon(Icons.picture_in_picture_alt_outlined),
            title: const Text('允许出现在其他应用上（悬浮窗）'),
            subtitle: const Text('车机能识别的音乐应用普遍开启，点击前往系统设置开启'),
            onTap: () async {
              try {
                final st = await Permission.systemAlertWindow.status;
                if (st.isGranted) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('悬浮窗权限已开启')));
                } else {
                  final res = await Permission.systemAlertWindow.request();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(res.isGranted
                          ? '悬浮窗权限已开启'
                          : '未开启：请在系统设置-应用-音素-允许出现在其他应用上 中手动打开')));
                }
              } catch (_) {}
            },
          ),
          // [xmusic] 2026-09-24 通知权限 + 媒体服务自检：车机识别排查入口
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('通知权限（媒体控制）'),
            subtitle: const Text('通知栏播放控制需要；Android 12- 自动授予不弹框，点击检查状态'),
            onTap: () async {
              try {
                final granted = await notificationGranted();
                if (!context.mounted) return;
                if (granted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('通知权限已授予，通知栏会显示播放控制')));
                } else {
                  final missing = await ensureAppPermissions();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(missing.contains('通知')
                          ? '通知未授权：请在系统设置-应用-音素-通知 中手动打开'
                          : '通知权限已授予')));
                }
              } catch (_) {}
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_remote_outlined),
            title: const Text('媒体服务自检'),
            subtitle: const Text('点击检查系统媒体服务是否就绪（车机桌面识别的前提）'),
            onTap: () async {
              var running = false;
              try {
                // audio_service 0.18 无 isRunning() 静态方法；running 为 bool getter（runningStream 当前值）
                running = AudioService.running;
              } catch (_) {}
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(running
                      ? '系统媒体服务运行中：车机桌面（迪友）应能枚举到音素'
                      : '媒体服务未运行：播放一首歌后自动拉起，再切车机桌面查看')));
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_rounded),
            title: const Text('申请存储权限'),
            subtitle: const Text('Android 11+ 写入公共目录需要（如 /Music）'),
            onTap: () async {
              final status = await Permission.manageExternalStorage.request();
              if (!context.mounted) return;
              final msg = status.isGranted
                  ? '已授予存储权限'
                  : '未授予，请在系统设置-应用-音素-权限中手动开启"所有文件访问"';
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
            },
          ),          const Divider(),
          // ===== 下载 =====
          _sectionTitle(theme, '下载'),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('本地下载路径'),
            subtitle: Text(settings.downloadPath.isEmpty ? '/storage/emulated/0/Music（默认）' : settings.downloadPath),
            onTap: () => _pickDownloadDirectory(context),
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
      ),
      );
        },
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

  /// 目录选择器：从 /storage/emulated/0 开始逐层浏览，选中后保存。
  Future<void> _pickDownloadDirectory(BuildContext context) async {
    final start = settings.downloadPath.isNotEmpty
        ? settings.downloadPath
        : '/storage/emulated/0';
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DirectoryPickerSheet(initialPath: start),
    );
    if (picked != null && picked.isNotEmpty) {
      settings.setDownloadPath(picked);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载目录已设为 $picked')),
        );
      }
    }
  }

  /// 外网搜索源详情：只读展示各源具体地址，不可更改。
  void _showSourcesInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('外网搜索源'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _srcRow('聚合API（当前）', settings.externalApiUrl),
              _srcRow('网易云直连', 'https://music.163.com'),
              _srcRow('B站直连', 'https://api.bilibili.com'),
              _srcRow('QQ音乐', 'https://c.y.qq.com（播放受版权/VIP限制）'),
              const SizedBox(height: 8),
              Text('搜索外网时自动聚合以上全部源，播放按歌曲来源分发；'
                  '聚合API地址可在上方“外部API地址”填写修改。',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _srcRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13),
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  /// QQ音乐 Cookie 输入：粘贴 y.qq.com 请求头里的 Cookie 整串即可解锁 QQ 榜单/播放。
  void _showQqCookieDialog(BuildContext context) {
    final ctl = TextEditingController(text: settings.qqCookie);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QQ音乐 Cookie'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'QQ 每日30首 / 各榜单现已匿名可用（无需 Cookie 也能刷出来）。\n'
                  '填写 Cookie 可进一步解锁会员/付费歌曲的 QQ 直连播放；'
                  '若播放受版权限制会自动切换其他音源。',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              TextField(
                controller: ctl,
                maxLines: 3,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Cookie（整串粘贴）',
                  hintText: 'uin=o123456; qqmusic_key=...',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              const Text('如何获取：',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 4),
              const Text(
                '1. 电脑浏览器（Chrome/Edge）登录 https://y.qq.com，随便播放一首歌\n'
                '2. 按 F12 → Network（网络）面板 → 刷新页面，在请求列表里找\n'
                '   名称含 musicu.fcg 的请求（找不到就点开任意歌曲再刷新）\n'
                '3. 点开该请求 → Request Headers（请求标头）→ 复制 Cookie 一行的\n'
                '   完整值（很长一串，从 pac_uid 一直到 ts_last）\n'
                '4. 整串粘贴，不要删改任何字段、不要打码\n'
                '重要：必须从请求头复制！浏览器「应用」面板里看不到 HttpOnly\n'
                '字段（psrf_qqaccess_token 等），从那里复制会缺关键登录凭证，\n'
                '验证必失败。Cookie 含登录态勿外泄，失效后重新获取即可。',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              final cookie = ctl.text.trim();
              if (cookie.isEmpty) {
                showTopToast(ctx, '请先粘贴 Cookie 再验证');
                return;
              }
              showTopToast(ctx, '验证中...', duration: const Duration(seconds: 2));
              final res = await controller.external.qqCookieValidDetailed(cookie);
              if (!ctx.mounted) return;
              showTopToast(
                ctx,
                res.$1 ? 'Cookie 有效，QQ 榜单/播放已解锁' : 'Cookie 无效：\n${res.$2}',
                duration: const Duration(seconds: 4),
              );
            },
            child: const Text('验证'),
          ),
          FilledButton(
            onPressed: () async {
              final cookie = ctl.text.trim();
              if (cookie.isEmpty) {
                showTopToast(ctx, '请先粘贴 Cookie 再保存');
                return;
              }
              showTopToast(ctx, '保存并验证中...', duration: const Duration(seconds: 2));
              final res = await controller.external.qqCookieValidDetailed(cookie);
              settings.setQqCookie(cookie);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              showTopToast(
                ctx,
                res.$1
                    ? '已保存，Cookie 有效，QQ 榜单/播放已解锁'
                    : '已保存，但 Cookie 无效：\n${res.$2}',
                duration: const Duration(seconds: 4),
              );
            },
            child: const Text('保存并验证'),
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

/// 纯 Dart 目录浏览器：无需额外插件，配合“所有文件访问”权限使用。
class _DirectoryPickerSheet extends StatefulWidget {
  const _DirectoryPickerSheet({required this.initialPath});

  final String initialPath;

  @override
  State<_DirectoryPickerSheet> createState() => _DirectoryPickerSheetState();
}

class _DirectoryPickerSheetState extends State<_DirectoryPickerSheet> {
  late String _path = widget.initialPath;
  List<Directory> _dirs = const [];
  bool _loading = true;
  String? _error;

  static const _shortcuts = [
    '/storage/emulated/0',
    '/storage/emulated/0/Music',
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Movies',
  ];

  @override
  void initState() {
    super.initState();
    _enter(_path);
  }

  Future<void> _enter(String p) async {
    setState(() {
      _path = p;
      _loading = true;
      _error = null;
    });
    try {
      final entries = await Directory(p)
          .list(followLinks: false)
          .where((e) => e is Directory)
          .where((e) => !e.path.split('/').last.startsWith('.'))
          .toList();
      final dirs = entries.cast<Directory>().toList()
        ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _dirs = dirs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '无法读取目录：$e';
      });
    }
  }

  void _goUp() {
    if (_path == '/' || _path.isEmpty) return;
    final parent = _path.substring(0, _path.lastIndexOf('/'));
    _enter(parent.isEmpty ? '/' : parent);
  }

  Future<void> _createFolder() async {
    final ctl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件夹名称'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await Directory('$_path/$name').create(recursive: false);
      _enter(_path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('创建失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canGoUp = _path != '/' && _path.isNotEmpty;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward_rounded),
                    tooltip: '上一级',
                    onPressed: canGoUp ? _goUp : null,
                  ),
                  Expanded(
                    child: Text(_path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall),
                  ),
                  IconButton(
                    icon: const Icon(Icons.create_new_folder_outlined),
                    tooltip: '新建文件夹',
                    onPressed: _createFolder,
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_path),
                    child: const Text('选择此目录'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final s in _shortcuts)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(s.split('/').last),
                        selected: _path == s,
                        onSelected: (_) => _enter(s),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!, textAlign: TextAlign.center),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _dirs.length,
                          itemBuilder: (context, i) {
                            final d = _dirs[i];
                            final name = d.path.split('/').last;
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.folder_rounded),
                              title: Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _enter(d.path),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
