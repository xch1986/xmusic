import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../lyrics.dart';
import '../player_controller.dart';
import '../settings.dart';
import '../widgets.dart';

/// Full-screen player.
///
/// Colors come only from the app's ColorScheme, which follows the system
/// light/dark setting. Nothing is extracted from the album art.
class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key, required this.settings, required this.controller});

  final AppSettings settings;
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final song = controller.current;
        final theme = Theme.of(context);

        return Scaffold(
          appBar: AppBar(
            title: const Text('正在播放'),
            actions: [
              LyricSizeControls(settings: settings),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: song == null
                ? const Center(child: Text('没有正在播放的歌曲'))
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                        child: Row(
                          children: [
                            CoverImage(
                              client: controller.client,
                              coverId: song.coverArt,
                              size: 72,
                              radius: 12,
                              requestSize: 240,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(song.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleLarge),
                                  const SizedBox(height: 2),
                                  Text(song.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                              color: theme.colorScheme
                                                  .onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(child: _lyricsArea(context, song.id)),
                      _SeekBar(player: controller.player),
                      _Controls(controller: controller),
                      const SizedBox(height: 8),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _lyricsArea(BuildContext context, String songId) {
    if (controller.lyricsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final lyrics = controller.lyrics;
    if (lyrics == null) {
      return Center(
        child: Text('暂无歌词',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return LyricsView(
      key: ValueKey(songId), // rebuild state when the song changes
      lyrics: lyrics,
      player: controller.player,
      settings: settings,
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
  static const double _anchor = 0.38; // where the active line rests (0 top, 1 bottom)

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

  // Line heights change with the font size, so re-anchor after layout.
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
  const _Controls({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          iconSize: 32,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: controller.previous,
        ),
        const SizedBox(width: 20),
        IconButton.filled(
          iconSize: 44,
          icon: Icon(controller.playing
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded),
          onPressed: controller.togglePlay,
        ),
        const SizedBox(width: 20),
        IconButton.filledTonal(
          iconSize: 32,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: controller.hasNext ? controller.next : null,
        ),
      ],
    );
  }
}
