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
        if (song == null) return const SizedBox.shrink();
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
          child: SafeArea(
            top: false,
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    PlayerPage(settings: settings, controller: controller),
              )),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
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
                      onPressed: controller.hasNext ? controller.next : null,
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
