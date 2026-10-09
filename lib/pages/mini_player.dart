import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../settings.dart';
import '../widgets.dart';
import 'player_page.dart';

/// 迷你播放栏：液态玻璃（BackdropFilter模糊+半透明），与首页/音乐库/导航栏统一由设置的主题开关控制；内容跟随主题色。
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
        final isDark = Theme.of(context).brightness == Brightness.dark;

        // 横竖屏都加宽加高、字体加大
        final mq = MediaQuery.of(context);
        final isLandscape = mq.size.width > mq.size.height;
        final isCarScreen = mq.size.shortestSide >= 480;
        final bottomPad = isLandscape ? (isCarScreen ? 0.0 : 4.0) : 48.0;
        final coverSize = isLandscape ? 88.0 : 72.0;
        final hPad = isLandscape ? 32.0 : 24.0;
        final vPad = isLandscape ? 20.0 : 18.0;
        final gap = isLandscape ? 28.0 : 22.0;
        final iconSize = isLandscape ? 44.0 : 38.0;
        final titleSize = isLandscape ? 28.0 : 22.0;
        final artistSize = isLandscape ? 21.0 : 18.0;

        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              color: cs.surface.withValues(alpha: isDark ? 0.22 : 0.15),
              child: InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PlayerPage(settings: settings, controller: controller),
                )),
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: isLandscape && isCarScreen
                        ? bottomPad
                        : mq.padding.bottom.clamp(0.0, bottomPad),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
                    child: song == null
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
            ),
          ),
        );
      },
    );
  }
}
