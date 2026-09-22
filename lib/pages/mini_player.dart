import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../settings.dart';
import '../widgets.dart';
import 'player_page.dart';

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

        // 注意：不用 BackdropFilter 毛玻璃——透明窗口/车机上会渲染成拉伸色块；
        // 用半透明纯色 + 顶部细边 + 柔和阴影，兼顾质感与车机兼容。
        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh.withValues(alpha: 0.88),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.10),
                blurRadius: 14,
                offset: const Offset(0, -3),
              ),
            ],
            border: Border(
              top: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.45),
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
              // 底部避让系统手势条：用 clamp 限制最大高度。
              // 某些设备/透明窗口下 MediaQuery.padding.bottom 会被撑到近全屏，
              // 若直接 SafeArea 会让迷你条高度暴涨、把详情页列表挤没（历史 bug 根因）。
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom.clamp(0.0, 48.0),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: song == null
                    // 常驻底栏：未播放时显示占位（音符 + 未在播放），
                    // 保证榜单/专辑/歌手等详情页一进去底部就有“全局小播放栏”，
                    // 点按进入播放页（提示当前无播放）。
                    ? Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest
                                  .withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.music_note_rounded,
                                color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('未在播放',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        color: cs.onSurfaceVariant)),
                          ),
                          Icon(Icons.play_circle_outline_rounded,
                              color: cs.onSurfaceVariant),
                          const SizedBox(width: 8),
                        ],
                      )
                    : Row(
                        children: [
                          CoverImage(
                            client: controller.client,
                            coverId: song.coverArt,
                            coverUrl: song.coverUrl,
                            size: 44,
                            radius: 8,
                            requestSize: 120,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.titleSmall),
                                Text(song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(controller.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded),
                            onPressed: controller.togglePlay,
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded),
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
