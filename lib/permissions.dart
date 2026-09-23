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
      if (res.isPermanentlyDenied) {
        // 系统已不再弹框（永久拒绝）：引导跳系统设置页手动打开
        await openAppSettings();
        missing.add(label);
      } else if (!res.isGranted && !res.isLimited) {
        missing.add(label);
      }
    } catch (_) {
      missing.add(label);
    }
  }

  // 无条件逐项请求（已授予的自动跳过）。不依赖系统版本判断，
  // 避免"Android 13+ 该弹的框被跳过"这类误判。
  await ask(Permission.notification, '通知');
  await ask(Permission.audio, '音乐和音频');
  await ask(Permission.photos, '照片和视频');
  await ask(Permission.storage, '存储');
  return missing;
}

/// 检查通知权限是否已授予（供启动引导使用）。
Future<bool> notificationGranted() async {
  try {
    final st = await Permission.notification.status;
    return st.isGranted || st.isLimited;
  } catch (_) {
    return false;
  }
}
