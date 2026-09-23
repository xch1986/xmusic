import 'dart:async';
import '../toast.dart';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

enum _OrientMode { auto, landscape, portrait }

class _PlayerPageState extends State<PlayerPage> {
  _OrientMode _orient = _OrientMode.auto;

  @override
  void initState() {
    super.initState();
    // 显式允许所有四个方向（空列表在某些版本不生效/反而锁方向），跟随系统自动旋转
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // 离开播放页时还原系统方向（允许所有方向），避免把其他页面锁住
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  /// 三态循环：自动（跟随系统旋转）→ 强制横屏 → 强制竖屏 → 自动。
  /// 设备没开“自动旋转”时，也能用手动按钮切到想要的朝向。
  Future<void> _toggleRotation() async {
    final next =
        _OrientMode.values[(_orient.index + 1) % _OrientMode.values.length];
    await SystemChrome.setPreferredOrientations(switch (next) {
      _OrientMode.auto => const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      _OrientMode.landscape => const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      _OrientMode.portrait => const [DeviceOrientation.portraitUp],
    });
    if (mounted) setState(() => _orient = next);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, widget.settings]),
      builder: (context, _) {
        final song = widget.controller.current;
        final landscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        // 背景跟随主题：自定义背景色优先，否则透明玻璃（通透度由主题统一处理）
        final bg = widget.settings.bgColor != 0
            ? Color(widget.settings.bgColor)
            : Theme.of(context).scaffoldBackgroundColor;

        return Scaffold(
          backgroundColor: bg,
          body: Container(
            // 高级质感：主题色轻微渐变叠加在透明玻璃之上（模拟迪友卡片的环境光晕）
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.13),
                  Colors.transparent,
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.09),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
            child: SafeArea(
              child: Stack(
                children: [
                  song == null
                      ? const Center(child: Text('没有正在播放的歌曲'))
                      : landscape
                          ? _landscapeView(context, song)
                          : _portraitView(context, song),
                  // 左上角：主页 + 返回（半透明玻璃按钮，不遮歌词/黑胶）
                  Positioned(
                    top: 4,
                    left: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CornerButton(
                          icon: Icons.home_rounded,
                          tooltip: '主页',
                          onTap: () =>
                              Navigator.of(context).popUntil((r) => r.isFirst),
                        ),
                        const SizedBox(width: 6),
                        _CornerButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          tooltip: '返回',
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
        // 黑胶封面（占4份，黑胶尺寸自适应区域高度，绝不溢出到歌词区）
        Expanded(
          flex: 4,
          child: LayoutBuilder(
            builder: (context, box) {
              final s = math.min(size, box.maxHeight * 0.92);
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Center(
                    child: Container(
                      width: s * 1.16,
                      height: s * 1.16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // 环境光晕：主题色低透明度大光斑，让黑胶浮在玻璃上
                        gradient: RadialGradient(
                          colors: [
                            theme.colorScheme.primary.withValues(alpha: 0.14),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.75],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: s, height: s,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.surfaceContainerHighest,
                          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 24, offset: const Offset(0,10))],
                        ),
                        padding: const EdgeInsets.all(8),
                        child: ClipOval(child: CoverImage(client: widget.controller.client, coverId: song.coverArt, coverUrl: song.coverUrl, size: s, requestSize: 800)),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // 歌词区 + 右侧按钮栏（缩放/收藏/下载），与黑胶互不重叠
        Expanded(
          flex: 5,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: _GlassPanel(
                    borderRadius: 24,
                    child: _lyricsArea(context, song.id),
                  ),
                ),
              ),
              _actionSidebar(context),
            ],
          ),
        ),
        // 歌名+歌手（放大居中，玻璃条承载）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: _GlassPanel(
            borderRadius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
        ),
        // 进度条+控制栏：整块玻璃面板（模糊+半透明，跟随深浅）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: _GlassPanel(
            borderRadius: 26,
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SeekBar(player: widget.controller.player),
                _Controls(controller: widget.controller, compact: false, onShowQueue: () => _openQueue(context)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 右侧竖排按钮：旋转、歌词缩放、收藏、下载。放在歌词板块右边，不占歌名行。
  Widget _actionSidebar(BuildContext context) {
    return Container(
      width: 52,
      margin: const EdgeInsets.only(right: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 旋转按钮已按用户要求移除（保留 _toggleRotation/_orient 供系统旋转/恢复逻辑使用）
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

  // ---- 横屏（车机）：左=大黑胶+歌曲信息栏；右=五行歌词+下方播放控制栏 ----
  Widget _landscapeView(BuildContext context, Song song) {
    final theme = Theme.of(context);
    return Row(
      children: [
        // 左侧：大黑胶 + 歌曲信息（自适应尺寸，不溢出）
        Expanded(
          flex: 5,
          child: LayoutBuilder(
            builder: (context, box) {
              final s = math.min(box.maxWidth * 0.62, box.maxHeight * 0.62);
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 左：大黑胶（带环境光晕，浮在玻璃上）+ 歌曲信息
                  Container(
                    width: s * 1.14,
                    height: s * 1.14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          theme.colorScheme.primary.withValues(alpha: 0.15),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.78],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: s, height: s,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.surfaceContainerHighest,
                        boxShadow: [BoxShadow(color: theme.colorScheme.shadow.withOpacity(0.35), blurRadius: 26, offset: const Offset(0, 8))],
                      ),
                      padding: const EdgeInsets.all(10),
                      child: ClipOval(child: CoverImage(client: widget.controller.client, coverId: song.coverArt, coverUrl: song.coverUrl, size: s, requestSize: 800)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: 24)),
                        const SizedBox(height: 6),
                        Text('${song.artist} · ${song.album}', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 15)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // 右侧：五行歌词（右按钮栏） + 下方进度条+播放控制栏
        Expanded(
          flex: 6,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
                        child: _GlassPanel(
                          borderRadius: 24,
                          child: Center(
                            child: _lyricsAreaFixed(context, song.id, visibleLines: 5),
                          ),
                        ),
                      ),
                    ),
                    _actionSidebar(context),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 2, 8, 14),
                child: _GlassPanel(
                  borderRadius: 26,
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SeekBar(player: widget.controller.player),
                      _Controls(controller: widget.controller, compact: false, onShowQueue: () => _openQueue(context)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _lyricsArea(BuildContext context, String songId, {int? visibleLines}) {
    return GestureDetector(
      onDoubleTap: () {
        widget.controller.reloadLyrics();
        showTopToast(context, '刷新歌词...', duration: const Duration(milliseconds: 800));
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
            visibleLines: visibleLines,
          );
        },
      ),
    );
  }

  // 五行歌词：限制歌词视口高度（行高=字号22×1.4 + 行距9×2，按歌词缩放系数计算）
  Widget _lyricsAreaFixed(BuildContext context, String songId, {int? visibleLines}) {
    final area = _lyricsArea(context, songId, visibleLines: visibleLines);
    if (visibleLines == null) return area;
    final scale = widget.settings.lyricScale;
    return SizedBox(
      height: visibleLines * (22 * 1.4 + 9 * 2) * scale + 10,
      child: area,
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
    showTopToast(context, '正在下载…');
    final msg = choice == 'nas'
        ? await widget.controller.uploadCurrentToNas()
        : await widget.controller.downloadCurrentToLocal();
    if (!context.mounted) return;
    showTopToast(context, msg, duration: const Duration(seconds: 2));
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
          textAlign: TextAlign.left,
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
    this.alignRight = false,
    this.visibleLines,
  });

  final Lyrics lyrics;
  final AudioPlayer player;
  final AppSettings settings;
  final bool alignRight;
  final int? visibleLines;

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
                vertical: constraints.maxHeight * 0.08,
              ),
              itemBuilder: (context, i) {
                final line = lines[i];
                final active = !synced || i == _current;
                // 歌词细描边：浅色底黑边/深色底亮边（轻量，保证白色歌词可读又不压字）
                final isDark = Theme.of(context).brightness == Brightness.dark;
                final stroke = isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.28);

                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: synced ? () => widget.player.seek(line.time) : null,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 9 * scale),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: _baseFontSize * scale,
                        height: 1.4,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        shadows: [
                          Shadow(color: stroke, blurRadius: 0, offset: const Offset(1.0, 1.0)),
                          Shadow(color: stroke, blurRadius: 0, offset: const Offset(-1.0, -1.0)),
                          const Shadow(color: Colors.black26, blurRadius: 4),
                        ],
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
                        child: Text(line.text.isEmpty ? '♪' : line.text,
                          textAlign: widget.alignRight ? TextAlign.right : TextAlign.left),
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

/// 播放页左上角玻璃按钮：半透明底 + 主题色图标，始终最上层且不遮挡歌词。
class _CornerButton extends StatelessWidget {
  const _CornerButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Icon(icon, size: 22, color: theme.colorScheme.onSurface),
          ),
        ),
      ),
    );
  }
}
/// 玻璃面板：BackdropFilter 毛玻璃 + 半透明主题色 + 细描边（跟随深浅主题）。
/// 参考迪友桌面（eightbitlab BlurView）的毛玻璃卡片：模糊 + 通透 + 细边框。
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 22,
    this.blur = 26,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              // 深浅自适应：深色更沉稳、浅色更通透
              color: cs.surface.withValues(alpha: isDark ? 0.52 : 0.40),
              border: Border.all(
                color: cs.onSurface.withValues(alpha: isDark ? 0.16 : 0.10),
                width: 0.6,
              ),
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: child,
          ),
        ),
      ),
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
          style: IconButton.styleFrom(
            // 玻璃质感：半透明圆钮，浮在壁纸上
            backgroundColor: cs.primary.withValues(alpha: 0.16),
            foregroundColor: cs.onSurface,
            side: BorderSide(color: cs.primary.withValues(alpha: 0.10), width: 0.5),
          ),
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: controller.previous,
        ),
        IconButton.filled(
          iconSize: playSize,
          style: IconButton.styleFrom(
            backgroundColor: cs.primary,
            shadowColor: cs.shadow.withValues(alpha: 0.35),
            elevation: 4,
          ),
          icon: Icon(controller.playing
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded),
          onPressed: controller.togglePlay,
        ),
        IconButton.filledTonal(
          iconSize: navSize,
          style: IconButton.styleFrom(
            backgroundColor: cs.primary.withValues(alpha: 0.16),
            foregroundColor: cs.onSurface,
            side: BorderSide(color: cs.primary.withValues(alpha: 0.10), width: 0.5),
          ),
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
