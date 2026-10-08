import 'package:flutter/services.dart';

/// 歌词悬浮窗原生通道（Android）。调用 native LyricOverlayService：
/// 仅在当前前台是设备默认桌面（迪友桌面）时显示半透明歌词，其它 app 不浮。
class LyricOverlay {
  static const MethodChannel _ch = MethodChannel('lyric_overlay');

  static Future<void> enable() async {
    try { await _ch.invokeMethod('enable'); } catch (_) {}
  }

  static Future<void> disable() async {
    try { await _ch.invokeMethod('disable'); } catch (_) {}
  }

  static Future<void> updateLyric(String text,
      {String title = '', String artist = '', String cover = '', int line = 0}) async {
    try {
      await _ch.invokeMethod('updateLyric', {
        'text': text, 'title': title, 'artist': artist, 'cover': cover, 'line': line,
      });
    } catch (_) {}
  }

  /// 返回 { overlay, usageStats, accessibility } 三个 bool 的权限状态。
  static Future<Map<dynamic, dynamic>?> checkPermissions() async {
    try {
      return await _ch.invokeMethod('checkPermissions') as Map<dynamic, dynamic>?;
    } catch (_) { return null; }
  }

  static Future<void> requestOverlay() async {
    try { await _ch.invokeMethod('requestOverlay'); } catch (_) {}
  }

  static Future<void> requestUsageStats() async {
    try { await _ch.invokeMethod('requestUsageStats'); } catch (_) {}
  }

  static Future<void> requestAccessibility() async {
    try { await _ch.invokeMethod('requestAccessibility'); } catch (_) {}
  }
}
