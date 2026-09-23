import 'package:permission_handler/permission_handler.dart';

/// 请求应用需要的全部运行时权限，返回未授予的权限中文名列表（空 = 全部已授予）。
///
/// Android 13+：通知(POST_NOTIFICATIONS) / 音频(READ_MEDIA_AUDIO) / 图片(READ_MEDIA_IMAGES)
/// Android 12- ：通知(自动授予) / 存储(READ_EXTERNAL_STORAGE)
///
/// 关键：不能用 Platform.version 判断系统版本（Android 上它是 Dart 版本而非 SDK 版本）。
/// 改用通知权限状态：Android 12- 通知自动授予（granted），Android 13+ 需手动请求（denied）。
Future<List<String>> ensureAppPermissions() async {
  final missing = <String>[];

  Future<void> ask(Permission p, String label) async {
    try {
      final st = await p.status;
      if (st.isGranted || st.isLimited) return;
      final res = await p.request();
      if (!res.isGranted && !res.isLimited && !res.isPermanentlyDenied) {
        missing.add(label);
      }
    } catch (_) {
      missing.add(label);
    }
  }

  // Android 13+ 判定：通知未自动授予 = 需要手动请求 = Android 13+
  var needMedia = false;
  try {
    final notifSt = await Permission.notification.status;
    needMedia = !notifSt.isGranted && !notifSt.isLimited;
  } catch (_) {
    needMedia = true;
  }

  await ask(Permission.notification, '通知');
  if (needMedia) {
    // Android 13+：请求媒体权限（会弹系统框）
    await ask(Permission.audio, '音乐和音频');
    await ask(Permission.photos, '照片和视频');
  } else {
    // Android 12-：请求存储
    await ask(Permission.storage, '存储');
  }
  return missing;
}
