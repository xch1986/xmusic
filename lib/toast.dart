import 'package:flutter/material.dart';

OverlayEntry? _toastEntry;

/// 全局置顶 Toast：无视当前页面/对话框层级，始终显示在最上层。
/// 用于「验证中/验证结果/歌词刷新」等需要用户一定能看到的提示。
/// context 传任意可用的 BuildContext（对话框内也可，rootOverlay 保证置顶）。
void showTopToast(BuildContext context, String msg,
    {Duration duration = const Duration(milliseconds: 1600)}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  _toastEntry?.remove();
  _toastEntry = null;
  final entry = OverlayEntry(
    builder: (ctx) => Positioned(
      top: MediaQuery.of(ctx).padding.top + 12,
      left: 40,
      right: 40,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),
      ),
    ),
  );
  _toastEntry = entry;
  overlay.insert(entry);
  Future.delayed(duration, () {
    if (entry.mounted) entry.remove();
    if (_toastEntry == entry) _toastEntry = null;
  });
}
