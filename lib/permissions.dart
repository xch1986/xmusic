import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// 请求应用需要的全部运行时权限，返回未授予的权限中文名列表（空 = 全部已授予）。
///
/// Android 13+：通知(POST_NOTIFICATIONS) / 音频(READ_MEDIA_AUDIO) / 图片(READ_MEDIA_IMAGES)
/// Android 12- ：通知(自动授予) / 存储(READ_EXTERNAL_STORAGE)
/// 返回缺失列表，供启动检查与设置页共用；失败权限也计入缺失，不抛异常。
Future<List<String>> ensureAppPermissions() async {
  final missing = <String>[];
  var sdk = 0;
  try {
    final v = Platform.version; // 形如 "13" / "12" / "14.0"
    sdk = int.tryParse(v.split(RegExp(r'[.\s]')).first) ?? 0;
  } catch (_) {}
  final sdkInt = sdk;

  Future<void> ask(Permission p, String label) async {
    try {
      final st = await p.status;
      if (st.isGranted || st.isLimited) return;
      final res = await p.request();
      if (!res.isGranted && !res.isLimited) missing.add(label);
    } catch (_) {
      missing.add(label);
    }
  }

  await ask(Permission.notification, '通知');
  if (sdkInt >= 33) {
    await ask(Permission.audio, '音乐和音频');
    await ask(Permission.photos, '照片和视频');
  } else {
    await ask(Permission.storage, '存储');
  }
  return missing;
}
