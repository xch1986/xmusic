import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../settings.dart';
import '../widgets.dart';
import 'player_page.dart';

/// 迷你播放栏：完全透明（背景透出外层 PageBackground/CoverGlassBackground），
/// 与首页/音乐库/导航栏统一由设置的主题开关控制；内容跟随主题色。
/// 车机横屏（landscape）时整体压缩尺寸，避免占横向空间。
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.settings, required this.controller});

  final AppSettings settings;
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final song = controller.current;
        final cs = Theme.of(context).colorScheme;

        // 横竖屏都加宽加高、字体加大
        final mq = MediaQuery.of(context);
        final isLandscape = mq.size.width > mq.size.height;
        final isCarScreen = mq.size.shortestSide >= 480;
        // 横屏底部抬高56dp，避开车机/手机系统导航条
        final bottomPad = isLandscape ? 56.0 : 48.0;
        final coverSize = isLandscape ? 54.0 : 56.0;
        final hPad = isLandscape ? 20.0 : 16.0;
        final vPad = isLandscape ? 10.0 : 12.0;
        final gap = isLandscape ? 16.0 : 16.0;
        final iconSize = isLandscape ? 30.0 : 32.0;
        final titleSize = isLandscape ? 18.0 : 18.0;
        final artistSize = isLandscape ? 14.0 : 14.0;

        return Container(
          // 仅一条跟随主题的细分隔线；不画背景色——透出 PageBackground，与全局主题统一
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.25),
                width: 0.5,
              ),
            ),
          ),
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  PlayerPage(settings: settings, controller: controller),
            )),
            child: Padding(
              // 车机横屏直接用固定抬高值；手机用系统手势条 padding
              padding: EdgeInsets.only(
                bottom: isLandscape && isCarScreen
                    ? bottomPad
                    : mq.padding.bottom.clamp(0.0, bottomPad),
              ),
              child: Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
                child: song == null
                    // 常驻底栏：未播放时显示占位（音符 + 未在播放）
                    ? Row(
                        children: [
                          Container(
                            width: coverSize,
                            height: coverSize,
                            decoration: BoxDecoration(
                              color: cs.onSurface.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.music_note_rounded,
                                color: cs.onSurfaceVariant, size: iconSize),
                          ),
                          SizedBox(width: gap),
                          Expanded(
                            child: Text('未在播放',
                                style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontSize: titleSize)),
                          ),
                          Icon(Icons.play_circle_outline_rounded,
                              color: cs.onSurfaceVariant, size: iconSize),
                          SizedBox(width: gap),
                        ],
                      )
                    : Row(
                        children: [
                          CoverImage(
                            client: controller.client,
                            coverId: song.coverArt,
                            coverUrl: song.coverUrl,
                            size: coverSize,
                            radius: 8,
                            requestSize: 120,
                          ),
                          SizedBox(width: gap),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: cs.onSurface,
                                        fontWeight: FontWeight.w600,
                                        fontSize: titleSize)),
                                Text(song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                        fontSize: artistSize)),
                              ],
                            ),
                          ),
                          IconButton(
                            iconSize: iconSize,
                            icon: Icon(
                                controller.playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: cs.onSurface),
                            onPressed: controller.togglePlay,
                          ),
                          IconButton(
                            iconSize: iconSize,
                            icon: Icon(Icons.skip_next_rounded,
                                color: cs.onSurface),
                            onPressed:
                                controller.hasNext ? controller.next : null,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
