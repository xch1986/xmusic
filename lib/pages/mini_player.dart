import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../settings.dart';
import '../widgets.dart';
import 'player_page.dart';

/// 模糊滤镜复用：sigma 从 24 降到 10（车机 GPU 每帧重绘代价显著下降），
/// 且避免 ListenableBuilder 每次重建都新建 ImageFilter 对象。
/// 注意：这里不套 RepaintBoundary——BackdropFilter 需读取下层绘制内容，
/// 额外合成层会改变模糊结果。
final ImageFilter _miniPlayerBlur =
    ImageFilter.blur(sigmaX: 10, sigmaY: 10);

/// 迷你播放栏：液态玻璃（BackdropFilter模糊+半透明），与首页/音乐库/导航栏统一由设置的主题开关控制；内容跟随主题色。
/// 车机横屏（landscape）时整体压缩尺寸，避免占横向空间。
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.settings,
    required this.controller,
    this.bottomInsetOverride,
  });

  final AppSettings settings;
  final PlayerController controller;
  /// HomeShell 把 MiniPlayer 与 NavigationBar 一起包进避让 Padding，
  /// 那时传 0 避免重复抬高；单独使用的页面不传，自行避让。
  final double? bottomInsetOverride;

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
        // 车机横屏：迪友桌面自绘底部导航条不进入系统 inset，
        // 用统一计算（系统 viewPadding 与设置值取大）把内容抬到它上面。
        final bottomPad = bottomInsetOverride ??
            (isLandscape && isCarScreen
                ? carBottomInsetOf(context, settings)
                : mq.padding.bottom.clamp(0.0, 48.0));
        final coverSize = isLandscape ? 56.0 : 72.0;
        final hPad = isLandscape ? 32.0 : 24.0;
        final vPad = isLandscape ? 10.0 : 18.0;
        final gap = isLandscape ? 16.0 : 22.0;
        final iconSize = isLandscape ? 28.0 : 38.0;
        final titleSize = isLandscape ? 26.0 : 22.0;
        final artistSize = isLandscape ? 18.0 : 18.0;

        return ClipRect(
          child: BackdropFilter(
            filter: _miniPlayerBlur,
            child: Container(
              color: cs.surface.withValues(alpha: isDark ? 0.22 : 0.15),
              child: InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PlayerPage(settings: settings, controller: controller),
                )),
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomPad),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
                    child: song == null
                        ? Row(
                            children: [
                              TvFocus(
                                enabled: settings.tvMode,
                                onSelect: () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => PlayerPage(settings: settings, controller: controller),
                                )),
                                child: Container(
                                  width: coverSize,
                                  height: coverSize,
                                  decoration: BoxDecoration(
                                    color: cs.onSurface.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.music_note_rounded,
                                      color: cs.onSurfaceVariant, size: iconSize),
                                ),
                              ),
                              SizedBox(width: gap),
                              TvFocus(
                                enabled: settings.tvMode,
                                onSelect: () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => PlayerPage(settings: settings, controller: controller),
                                )),
                                child: Expanded(
                                  child: Text('未在播放',
                                      style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          fontSize: titleSize)),
                                ),
                              ),
                              Icon(Icons.play_circle_outline_rounded,
                                  color: cs.onSurfaceVariant, size: iconSize),
                              SizedBox(width: gap),
                            ],
                          )
                        : Row(
                            children: [
                              TvFocus(
                                enabled: settings.tvMode,
                                onSelect: () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => PlayerPage(settings: settings, controller: controller),
                                )),
                                child: CoverImage(
                                  client: controller.client,
                                  coverId: song.coverArt,
                                  coverUrl: song.coverUrl,
                                  size: coverSize,
                                  radius: 8,
                                  requestSize: 120,
                                ),
                              ),
                              SizedBox(width: gap),
                              TvFocus(
                                enabled: settings.tvMode,
                                onSelect: () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => PlayerPage(settings: settings, controller: controller),
                                )),
                                child: Expanded(
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
                              ),
                              TvFocus(
                                enabled: settings.tvMode,
                                onSelect: controller.togglePlay,
                                child: IconButton(
                                  iconSize: iconSize,
                                  icon: Icon(
                                      controller.playing
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      color: cs.onSurface),
                                  onPressed: controller.togglePlay,
                                ),
                              ),
                              TvFocus(
                                enabled: settings.tvMode,
                                onSelect: controller.hasNext ? controller.next : null,
                                child: IconButton(
                                  iconSize: iconSize,
                                  icon: Icon(Icons.skip_next_rounded,
                                      color: cs.onSurface),
                                  onPressed:
                                      controller.hasNext ? controller.next : null,
                                ),
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
