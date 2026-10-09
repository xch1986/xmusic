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
        // 车机横屏底部抬高由 home_shell 统一控制（避免与导航栏padding叠加）
        final bottomPad = isLandscape
            ? (isCarScreen ? 0.0 : 4.0)
            : 48.0;
        final coverSize = isLandscape ? 88.0 : 72.0;
        final hPad = isLandscape ? 32.0 : 24.0;
        final vPad = isLandscape ? 20.0 : 18.0;
        final gap = isLandscape ? 28.0 : 22.0;
        final iconSize = isLandscape ? 44.0 : 38.0;
        final titleSize = isLandscape ? 28.0 : 22.0;
        final artistSize = isLandscape ? 21.0 : 18.0;

        return Container(
          // 四周细描边，与其他卡片统一
          decoration: BoxDecoration(
            border: Border.all(
              color: cs.onSurface.withValues(alpha: 0.35),
              width: 1.2,
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
