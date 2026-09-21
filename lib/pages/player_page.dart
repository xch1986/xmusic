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

      listenable: Listenable.merge([widget.controller, widget.settings]),

      builder: (context, _) {

        final song = widget.controller.current;

        final landscape =

            MediaQuery.of(context).orientation == Orientation.landscape;

        // 不透明背景：自定义色优先，否则按明暗用不透明色

        final cs = Theme.of(context).colorScheme;

        final brightness = cs.brightness;

        final bg = widget.settings.bgColor != 0

            ? Color(widget.settings.bgColor).withOpacity(1.0)

            : (brightness == Brightness.dark

                ? const Color(0xFF1E2433)

                : const Color(0xFFEAF0FA));



        return Scaffold(

          backgroundColor: bg,

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



  // ---- 竖屏：黑胶封面 -> 歌词(右侧按钮栏) -> 歌名歌手 -> 进度 -> 控制 ----

  Widget _portraitView(BuildContext context, Song song) {

    final theme = Theme.of(context);

    final size = MediaQuery.of(context).size.width * 0.5;

    return Column(

      children: [

        // 黑胶封面

        Expanded(

          flex: 3,

          child: Column(

            mainAxisAlignment: MainAxisAlignment.center,

            children: [

              const SizedBox(height: 40),

              Center(

                child: Container(

                  width: size, height: size,

                  decoration: BoxDecoration(

                    shape: BoxShape.circle,

                    color: theme.colorScheme.surfaceContainerHighest,

                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 24, offset: const Offset(0,10))],

                  ),

                  padding: const EdgeInsets.all(8),

                  child: ClipOval(child: CoverImage(client: widget.controller.client, coverId: song.coverArt, coverUrl: song.coverUrl, size: size, requestSize: 800)),

                ),

              ),

            ],

          ),

        ),

        // 歌词区 + 右侧按钮栏（缩放/收藏/下载）

        Expanded(

          flex: 6,

          child: Row(

            crossAxisAlignment: CrossAxisAlignment.stretch,

            children: [

              Expanded(child: _lyricsArea(context, song.id)),

              _actionSidebar(context),

            ],

          ),

        ),

        // 歌名+歌手（放大居中）

        Padding(

          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),

          child: Column(

            children: [

              Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,

                style: theme.textTheme.headlineSmall?.copyWith(

                  fontWeight: FontWeight.w800, fontSize: 26, height: 1.2)),

              const SizedBox(height: 4),

              Text('${song.artist} - ${song.album}', maxLines: 1, overflow: TextOverflow.ellipsis,

                style: theme.textTheme.bodyLarge?.copyWith(

                  color: theme.colorScheme.onSurfaceVariant, fontSize: 16)),

            ],

          ),

        ),

        _SeekBar(player: widget.controller.player),

        _Controls(controller: widget.controller, compact: false, onShowQueue: () => _openQueue(context)),

        const SizedBox(height: 8),

      ],

    );

  }



  // 右侧竖排按钮：歌词缩放、收藏、下载。放在歌词板块右边，不占歌名行。

  Widget _actionSidebar(BuildContext context) {

    return Container(

      width: 52,

      margin: const EdgeInsets.only(right: 8),

      child: Column(

        mainAxisAlignment: MainAxisAlignment.center,

        children: [

          LyricSizeControls(settings: widget.settings),

          const SizedBox(height: 2),

          _FavoriteButton(controller: widget.controller),

          IconButton(

            tooltip: '下载',

            icon: const Icon(Icons.download_rounded, size: 22),

            onPressed: () => _downloadMenu(context),

          ),

        ],

      ),

    );

  }



  // ---- 横屏：左封面+歌名+控制，右歌词(右侧按钮栏) ----

  Widget _landscapeView(BuildContext context, Song song) {

    final theme = Theme.of(context);

    return Row(

      children: [

        Expanded(

          flex: 5,

          child: Column(

            mainAxisAlignment: MainAxisAlignment.center,

            children: [

              Container(

                width: 140, height: 140,

                decoration: BoxDecoration(

                  shape: BoxShape.circle,

                  color: theme.colorScheme.surfaceContainerHighest,

                  boxShadow: [BoxShadow(color: theme.colorScheme.shadow.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],

                ),

                padding: const EdgeInsets.all(8),

                child: ClipOval(child: CoverImage(client: widget.controller.client, coverId: song.coverArt, coverUrl: song.coverUrl, size: 190, requestSize: 500)),

              ),

              const SizedBox(height: 16),

              Padding(

                padding: const EdgeInsets.symmetric(horizontal: 24),

                child: Column(

                  children: [

                    Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,

                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: 22)),

                    const SizedBox(height: 4),

                    Text('${song.artist} · ${song.album}', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,

                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 15)),

                  ],

                ),

              ),

              const SizedBox(height: 12),

              _SeekBar(player: widget.controller.player),

              _Controls(controller: widget.controller, compact: false, onShowQueue: () => _openQueue(context)),

              const SizedBox(height: 8),

            ],

          ),

        ),

        Expanded(

          flex: 6,

          child: Row(

            crossAxisAlignment: CrossAxisAlignment.stretch,

            children: [

              Expanded(child: _lyricsArea(context, song.id)),

              _actionSidebar(context),

            ],

          ),

        ),

      ],

    );

  }



  Widget _lyricsArea(BuildContext context, String songId) {

    return GestureDetector(

      onDoubleTap: () {

        widget.controller.reloadLyrics();

        ScaffoldMessenger.of(context).showSnackBar(

          const SnackBar(content: Text('刷新歌词...'), duration: Duration(milliseconds: 800)),

        );

      },

      child: Builder(

        builder: (context) {

          if (widget.controller.lyricsLoading) {

            return const Center(child: CircularProgressIndicator());

          }

          final lyrics = widget.controller.lyrics;

          if (lyrics == null) {

            return Center(

              child: Column(

                mainAxisSize: MainAxisSize.min,

                children: [

                  Text('暂无歌词', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),

                  const Text('双击刷新', style: TextStyle(fontSize: 12, color: Colors.grey)),

                ],

              ),

            );

          }

          return LyricsView(

            key: ValueKey(songId),

            lyrics: lyrics,

            player: widget.controller.player,

            settings: widget.settings,

          );

        },

      ),

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

        return Column(

          mainAxisSize: MainAxisSize.min,

          children: [

            IconButton(

              tooltip: '减小歌词字号',

              icon: const Icon(Icons.text_decrease),

              onPressed:

                  settings.canDecreaseLyric ? settings.decreaseLyric : null,

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

                vertical: constraints.maxHeight * 0.15,

              ),

              itemBuilder: (context, i) {

                final line = lines[i];

                final active = !synced || i == _current;



                return InkWell(

                  borderRadius: BorderRadius.circular(12),

                  onTap: synced ? () => widget.player.seek(line.time) : null,

                  child: Padding(

                    padding: EdgeInsets.symmetric(vertical: 14 * scale),

                    child: AnimatedDefaultTextStyle(

                      duration: const Duration(milliseconds: 200),

                      style: TextStyle(

                        fontSize: _baseFontSize * scale,

                        height: 1.4,

                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,

                        color: active

                            ? (widget.settings.lyricActive != 0

                                ? Color(widget.settings.lyricActive)

                                : cs.onSurface)

                            : (i < _current

                                ? (widget.settings.lyricPast != 0

                                    ? Color(widget.settings.lyricPast)

                                    : cs.onSurface.withOpacity(0.45))

                                : (widget.settings.lyricFuture != 0

                                    ? Color(widget.settings.lyricFuture)

                                    : cs.onSurface.withOpacity(0.45))),

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

                SliderTheme(

                  data: SliderTheme.of(context).copyWith(

                    trackHeight: 5,

                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),

                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),

                  ),

                  child: Slider(

                    value: value.toDouble(),

                    max: maxMs,

                    onChanged: (v) => setState(() => _dragMs = v),

                    onChangeEnd: (v) {

                      widget.player.seek(Duration(milliseconds: v.round()));

                      setState(() => _dragMs = null);

                    },

                  ),

                ),

                Padding(

                  padding: const EdgeInsets.symmetric(horizontal: 24),

                  child: Row(

                    mainAxisAlignment: MainAxisAlignment.spaceBetween,

                    children: [

                      Text(formatDuration(Duration(milliseconds: value.round())),

                          style: style?.copyWith(fontSize: 16)),

                      Text(formatDuration(total), style: style?.copyWith(fontSize: 16)),

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

    final gap = compact ? 24.0 : 24.0;

    final playSize = compact ? 64.0 : 64.0;

    final navSize = compact ? 48.0 : 48.0;

    final sideIcon = compact ? 40.0 : 36.0;

    final cs = Theme.of(context).colorScheme;

    return Row(

      mainAxisAlignment: MainAxisAlignment.spaceEvenly,

      children: [

        IconButton(

          iconSize: sideIcon,

          tooltip: '播放模式',

          icon: Icon(switch (controller.repeat) {

            PlayMode.sequential => Icons.repeat_rounded,

            PlayMode.shuffle => Icons.shuffle_rounded,

            PlayMode.repeatOne => Icons.repeat_one_rounded,

          }),

          color: controller.repeat == PlayMode.sequential ? null : cs.primary,

          onPressed: controller.cycleRepeat,

        ),

        IconButton.filledTonal(

          iconSize: navSize,

          icon: const Icon(Icons.skip_previous_rounded),

          onPressed: controller.previous,

        ),

        IconButton.filled(

          iconSize: playSize,

          icon: Icon(controller.playing

              ? Icons.pause_rounded

              : Icons.play_arrow_rounded),

          onPressed: controller.togglePlay,

        ),

        IconButton.filledTonal(

          iconSize: navSize,

          icon: const Icon(Icons.skip_next_rounded),

          onPressed: controller.hasNext ? controller.next : null,

        ),

        IconButton(

          iconSize: sideIcon,

          tooltip: '播放列表',

          icon: const Icon(Icons.queue_music_rounded),

          onPressed: onShowQueue,

        ),

      ],

    );

  }

}
