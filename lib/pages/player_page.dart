import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../lyrics.dart';
import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../widgets.dart';

/// Full-screen player.
///
/// Portrait: cover -> current lyric line -> title -> seek bar -> controls.
/// Landscape: left = cover + controls, right = title + lyrics (car-friendly).
///
/// Colors come only from the app ColorScheme (system light/dark); nothing is
/// extracted from album art.
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.settings, required this.controller});

  final AppSettings settings;
  final PlayerController controller;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final song = widget.controller.current;
        final landscape =
            MediaQuery.of(context).orientation == Orientation.landscape;

        return Scaffold(
          body: SafeArea(
            child: song == null
                ? const Center(child: Text('没有正在播放的歌曲'))
                : landscape
                    ? _landscapeView(context, song)
                    : _portraitView(context, song),
          ),
        );
      },
    );
  }

  // ---- 竖屏：收起按钮 -> 大黑胶 -> 歌名收藏 -> 当前歌词 -> 进度条 -> 控制 ----
  // ---- 竖屏：小封面+歌名在上，中间完整歌词，底部进度+控制 ----
  Widget _portraitView(BuildContext context, Song song) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // 小封面 + 歌名歌手 + 收藏 + 下载
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              CoverImage(client: widget.controller.client, coverId: song.coverArt, coverUrl: song.coverUrl, size: 56, radius: 8, requestSize: 200),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${song.artist} - ${song.album}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              _FavoriteButton(controller: widget.controller),
              IconButton(tooltip: '下载', icon: const Icon(Icons.download_rounded), onPressed: () => _downloadMenu(context)),
            ],
          ),
        ),
        // 完整歌词列表
        Expanded(child: _lyricsArea(context, song.id)),
        // 歌词缩放
        Align(alignment: Alignment.centerRight, child: LyricSizeControls(settings: widget.settings)),
        _SeekBar(player: widget.controller.player),
        _Controls(controller: widget.controller, compact: false, onShowQueue: () => _openQueue(context)),
        const SizedBox(height: 8),
      ],
    );
  }

  // ---- 横屏：左封面+控制，右歌名+歌词 ----
  Widget _landscapeView(BuildContext context, Song song) {
    final theme = Theme.of(context);
    return Row(
      children: [
        // Left: cover + controls.
        Expanded(
          flex: 5,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surfaceContainerHighest,
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.shadow.withOpacity(0.3),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(8),
                child: ClipOval(
                  child: CoverImage(
                    client: widget.controller.client,
                    coverId: song.coverArt,
                    coverUrl: song.coverUrl,
                    size: 200,
                    requestSize: 500,
                  ),
                ),
              ),
              const Spacer(),
              _SeekBar(player: widget.controller.player),
              _Controls(
                controller: widget.controller,
                compact: true,
                onShowQueue: () => _openQueue(context),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        // Right: title + scrolling lyrics.
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text('${song.artist} · ${song.album}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ),
                        _FavoriteButton(controller: widget.controller),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _lyricsArea(context, song.id),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _lyricsArea(BuildContext context, String songId) {
    if (widget.controller.lyricsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final lyrics = widget.controller.lyrics;
    if (lyrics == null) {
      return Center(
        child: Text('暂无歌词',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return LyricsView(
      key: ValueKey(songId),
      lyrics: lyrics,
      player: widget.controller.player,
      settings: widget.settings,
    );
  }

  Future<void> _downloadMenu(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.phone_android_rounded),
              title: const Text('下载到手机'),
              onTap: () => Navigator.of(ctx).pop('local'),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('上传到 NAS (WebDAV)'),
              onTap: () => Navigator.of(ctx).pop('nas'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在下载…'), duration: Duration(seconds: 1)),
    );
    final msg = choice == 'nas'
        ? await widget.controller.uploadCurrentToNas()
        : await widget.controller.downloadCurrentToLocal();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openQueue(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('播放列表',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  final q = widget.controller.queue;
                  final idx = widget.controller.index;
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: q.length,
                    itemBuilder: (context, i) {
                      final active = i == idx;
                      final sn = q[i];
                      return ListTile(
                        dense: true,
                        leading: Text('${i + 1}',
                            style: TextStyle(
                                color: active
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurfaceVariant)),
                        title: Text(sn.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(sn.artist,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          widget.controller.playAt(i);
                          Navigator.of(ctx).pop();
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Big single line that tracks the currently-active lyric (portrait).
class _CurrentLyricLine extends StatefulWidget {
  const _CurrentLyricLine({required this.controller, required this.settings});
  final PlayerController controller;
  final AppSettings settings;

  @override
  State<_CurrentLyricLine> createState() => _CurrentLyricLineState();
}

class _CurrentLyricLineState extends State<_CurrentLyricLine> {
  StreamSubscription? _sub;
  int _line = -1;

  @override
  void initState() {
    super.initState();
    _sub = widget.controller.player.positionStream.listen((pos) {
      final ly = widget.controller.lyrics;
      if (ly == null || !ly.synced) return;
      final i = ly.indexAt(pos);
      if (i != _line) setState(() => _line = i);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ly = widget.controller.lyrics;
    final text = (ly == null || _line < 0 || _line >= ly.lines.length)
        ? ''
        : ly.lines[_line].text;
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        final scale = widget.settings.lyricScale;
        return Text(
          text.isEmpty ? '♪' : text,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontSize: 22 * scale,
                fontWeight: FontWeight.w600,
              ),
        );
      },
    );
  }
}

/// Favorite heart for the current song.
class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final starred = controller.currentStarred;
        return IconButton(
          tooltip: starred ? '取消收藏' : '收藏',
          icon: Icon(
            starred ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: starred ? Theme.of(context).colorScheme.primary : null,
          ),
          onPressed: controller.toggleStar,
        );
      },
    );
  }
}

/// Playback mode toggle: 顺序 -> 随机 -> 单曲循环.
class _RepeatButton extends StatelessWidget {
  const _RepeatButton({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final mode = controller.repeat;
        final (icon, tooltip) = switch (mode) {
          PlayMode.sequential => (Icons.repeat_rounded, '顺序播放'),
          PlayMode.shuffle => (Icons.shuffle_rounded, '随机播放'),
          PlayMode.repeatOne => (Icons.repeat_one_rounded, '单曲循环'),
        };
        return IconButton(
          tooltip: tooltip,
          icon: Icon(icon),
          color: mode == PlayMode.sequential
              ? null
              : Theme.of(context).colorScheme.primary,
          onPressed: controller.cycleRepeat,
        );
      },
    );
  }
}

/// − 100% + buttons that change the lyric font scale (persisted).
class LyricSizeControls extends StatelessWidget {
  const LyricSizeControls({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '减小歌词字号',
              icon: const Icon(Icons.text_decrease),
              onPressed:
                  settings.canDecreaseLyric ? settings.decreaseLyric : null,
            ),
            SizedBox(
              width: 44,
              child: Text(
                '${(settings.lyricScale * 100).round()}%',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            IconButton(
              tooltip: '增大歌词字号',
              icon: const Icon(Icons.text_increase),
              onPressed:
                  settings.canIncreaseLyric ? settings.increaseLyric : null,
            ),
          ],
        );
      },
    );
  }
}

class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.lyrics,
    required this.player,
    required this.settings,
  });

  final Lyrics lyrics;
  final AudioPlayer player;
  final AppSettings settings;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  static const double _baseFontSize = 22;
  static const double _anchor = 0.38;

  final ItemScrollController _scroll = ItemScrollController();
  StreamSubscription<Duration>? _positionSub;
  int _current = -1;

  @override
  void initState() {
    super.initState();
    if (widget.lyrics.synced) {
      _positionSub = widget.player.positionStream.listen((pos) {
        final i = widget.lyrics.indexAt(pos);
        if (i != _current) {
          setState(() => _current = i);
          _follow();
        }
      });
    }
    widget.settings.addListener(_onScaleChanged);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onScaleChanged);
    _positionSub?.cancel();
    super.dispose();
  }

  void _onScaleChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow(jump: true));
  }

  void _follow({bool jump = false}) {
    if (_current < 0 || !_scroll.isAttached) return;
    if (jump) {
      _scroll.jumpTo(index: _current, alignment: _anchor);
    } else {
      _scroll.scrollTo(
        index: _current,
        alignment: _anchor,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = widget.lyrics.lines;
    final synced = widget.lyrics.synced;

    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        final scale = widget.settings.lyricScale;

        return LayoutBuilder(
          builder: (context, constraints) {
            return ScrollablePositionedList.builder(
              itemScrollController: _scroll,
              itemCount: lines.length,
              padding: EdgeInsets.symmetric(
                horizontal: 24,
                vertical: constraints.maxHeight * 0.4,
              ),
              itemBuilder: (context, i) {
                final line = lines[i];
                final active = !synced || i == _current;

                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: synced ? () => widget.player.seek(line.time) : null,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8 * scale),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: _baseFontSize * scale,
                        height: 1.4,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active
                            ? cs.onSurface
                            : cs.onSurface.withOpacity(0.45),
                      ),
                      child: Text(line.text.isEmpty ? '♪' : line.text),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.player});

  final AudioPlayer player;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;

    return StreamBuilder<Duration?>(
      stream: widget.player.durationStream,
      builder: (context, durationSnap) {
        final total = durationSnap.data ?? Duration.zero;
        final maxMs =
            total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0;

        return StreamBuilder<Duration>(
          stream: widget.player.positionStream,
          builder: (context, positionSnap) {
            final pos = positionSnap.data ?? Duration.zero;
            final value =
                (_dragMs ?? pos.inMilliseconds.toDouble()).clamp(0.0, maxMs);

            return Column(
              children: [
                Slider(
                  value: value.toDouble(),
                  max: maxMs,
                  onChanged: (v) => setState(() => _dragMs = v),
                  onChangeEnd: (v) {
                    widget.player.seek(Duration(milliseconds: v.round()));
                    setState(() => _dragMs = null);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(formatDuration(Duration(milliseconds: value.round())),
                          style: style),
                      Text(formatDuration(total), style: style),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    required this.compact,
    this.onShowQueue,
  });

  final PlayerController controller;
  final bool compact;
  final VoidCallback? onShowQueue;

  @override
  Widget build(BuildContext context) {
    final gap = compact ? 12.0 : 20.0;
    final playSize = compact ? 40.0 : 44.0;
    final navSize = compact ? 30.0 : 32.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RepeatButton(controller: controller),
        SizedBox(width: gap),
        IconButton.filledTonal(
          iconSize: navSize,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: controller.previous,
        ),
        SizedBox(width: gap),
        IconButton.filled(
          iconSize: playSize,
          icon: Icon(controller.playing
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded),
          onPressed: controller.togglePlay,
        ),
        SizedBox(width: gap),
        IconButton.filledTonal(
          iconSize: navSize,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: controller.hasNext ? controller.next : null,
        ),
        SizedBox(width: gap),
        IconButton(
          tooltip: '播放列表',
          icon: const Icon(Icons.queue_music_rounded),
          onPressed: onShowQueue,
        ),
      ],
    );
  }
}
