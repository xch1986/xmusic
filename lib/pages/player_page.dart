import 'dart:async';
import '../cover_glass.dart';
import '../toast.dart';
import 'home_shell.dart';
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

import '../audio_handler.dart';

/// Full-screen player.
///
/// Portrait: cover -> current lyric line -> title -> seek bar -> controls.
/// Landscape: left = cover + controls, right = title + lyrics (car-friendly).
///
/// Colors come only from the app ColorScheme (system light/dark); nothing is
/// extracted from album art.
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.settings, required this.controller});

  /// 路由名：用于播放页单例去重（popUntil 定位）。
  static const String routeName = 'playerPage';
  /// 当前栈中播放页实例数（>=1 说明已有一层，点歌不再重复 push）。
  static int _stackCount = 0;

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
    PlayerPage._stackCount++;
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
    PlayerPage._stackCount--;
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
    // 车机横屏大屏：整页文字放大 1.35x（歌名/歌词/歌手/进度都跟着大）
    final _mq = MediaQuery.of(context);
    final _car = isCarScreen(context);
    return MediaQuery(
      data: _car ? _mq.copyWith(textScaler: const TextScaler.linear(1.35)) : _mq,
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.controller, widget.settings]),
      builder: (context, _) {
        final song = widget.controller.current;
        final landscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // [xmusic] 2026-09-28 全 App 封面玻璃：背景透出当前播放歌曲封面图片（随切歌更新）
              Positioned.fill(
                child: CoverGlassBackground(
                  controller: widget.controller,
                  settings: widget.settings,
                ),
              ),
              SafeArea(
                minimum: const EdgeInsets.only(bottom: 12),
                child: Stack(
                  children: [
                    song == null
                        ? const Center(child: Text('没有正在播放的歌曲'))
                        : landscape
                            ? _landscapeView(context, song)
                            : _portraitView(context, song),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
    );
  }

  // ---- 竖屏：黑胶封面 -> 歌词(右侧按钮栏) -> 歌名歌手 -> 进度 -> 控制 ----
  Widget _portraitView(BuildContext context, Song song) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size.width * 0.5;
    return Column(
      children: [
        // 封面（占5份，尺寸自适应区域高度，绝不溢出到歌词区）
        Expanded(
          flex: 5,
          child: LayoutBuilder(
            builder: (context, box) {
              final s = math.min(size, box.maxHeight * 0.92);
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if ((widget.controller.queueSource ?? '').isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(left: 16, bottom: 4, top: isCarScreen(context) ? 40 : 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.controller.queueSource!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant, fontSize: 16),
                        ),
                      ),
                    ),
                  Center(
                    child: StreamBuilder<bool>(
                      stream: widget.controller.player.playingStream,
                      builder: (context, snap) {
                        final cov = CoverImage(client: widget.controller.client, coverId: song.coverArt, coverUrl: song.coverUrl, size: s, requestSize: 600);
                        return Container(
                          width: s, height: s,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(s * 0.055),
                            boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 26, offset: const Offset(0, 12))],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(s * 0.055),
                            child: cov,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // 歌词区 + 右侧按钮栏（缩放/收藏/下载），与封面互不重叠
        Expanded(
          flex: 4,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _actionSidebarLeft(context),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: _lyricsArea(context, song.id),
                ),
              ),
              _actionSidebar(context),
            ],
          ),
        ),
        // 歌名+歌手：左右各一个小玻璃按钮（首页/返回）
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _MiniCornerButton(icon: Icons.home_rounded, onTap: () {
                Navigator.of(context).popUntil((r) => r.isFirst);
                HomeShell.switchToHome();
              }),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
              SizedBox(
                width: double.infinity,
                child: _MarqueeText(song.title,
                  maxWidth: MediaQuery.sizeOf(context).width - 140,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: (isCarScreen(context) && MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height) ? 18 : 22,
                    height: 1.2)),
              ),
              SizedBox(height: (isCarScreen(context) && MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height) ? 10 : 4),
              // 歌手+专辑也滚动（完整显示后半段，避免省略号截断）
              SizedBox(
                width: double.infinity,
                child: _MarqueeText('${song.artist} - ${song.album}',
                  maxWidth: MediaQuery.sizeOf(context).width - 140,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: (isCarScreen(context) && MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height) ? 12 : 14)),
              ),

              // 外源歌正在解析播放地址时的加载反馈（并行兜底最多约15s，先告诉用户正在加载）
              if (widget.controller.loadingUrl) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12, height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 8),
                    Text('正在解析播放地址…', style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary, fontSize: 13)),
                  ],
                ),
              ],
                  ],
                ),
              ),
              _MiniCornerButton(icon: Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.of(context).maybePop()),
            ],
          ),
        ),
        // 进度条+控制栏：整块玻璃面板（模糊+半透明，跟随深浅）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SeekBar(player: widget.controller.player),
              _Controls(controller: widget.controller, compact: false, onShowQueue: () => _openQueue(context)),
            ],
          ),
        ),
      ],
    );
  }

  void _toggleBlacklist(Song? song) {
    if (song == null) return;
    final s = widget.settings;
    if (s.isBlacklisted(song)) {
      s.removeBlacklist(song);
      showTopToast(context, '已移出黑名单');
    } else {
      s.addBlacklist(song);
      showTopToast(context, '已加入黑名单，不再出现在榜单/歌单');
    }
  }

  // 右侧竖排按钮：歌词缩放、收藏、下载、上传NAS、黑名单。放在歌词板块右边，不占歌名行。
  /// 左侧动作栏（手机）：歌词缩放 + 收藏 + 黑名单；车机无需下载按钮，左侧为空。
  Widget _actionSidebarLeft(BuildContext context) {
    final car = _carUI(context);
    final bool _landP = MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    final double side = _landP ? 18 : 30;
    final double _gap = _landP ? 2.0 : 6.0;
    if (car) return const SizedBox.shrink();
    final Widget bar = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconTheme(
          data: IconThemeData(size: side),
          child: LyricSizeControls(settings: widget.settings, land: _landP),
        ),
        SizedBox(height: _gap),
        IconTheme(
          data: IconThemeData(size: side),
          child: _FavoriteButton(controller: widget.controller),
        ),
      ],
    );
    return Container(
      width: _landP ? 40 : 44,
      margin: const EdgeInsets.only(left: 8),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: bar,
      ),
    );
  }

  Widget _actionSidebar(BuildContext context) {
    // [xmusic] 2026-09-28 车机端右侧5按钮与主页&返回一致(_MiniCornerButton 64/48毛玻璃圆钮)；手机保持小图标 30
    final car = _carUI(context);
    final bool _landP = MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    final double side = _landP ? 18 : 30;
    final double _gap = _landP ? 2.0 : 6.0;
    if (car) {
      // 车机：统一用 _MiniCornerButton，与主页/返回按钮同尺寸；Column占满高度spaceEvenly均匀分布
      return Container(
        width: 72,
        margin: const EdgeInsets.only(right: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MiniCornerButton(icon: Icons.text_decrease_rounded, onTap: widget.settings.canDecreaseLyricFor(_landP) ? () => widget.settings.decreaseLyricFor(_landP) : null),
            const SizedBox(height: 16),
            _MiniCornerButton(icon: Icons.text_increase_rounded, onTap: widget.settings.canIncreaseLyricFor(_landP) ? () => widget.settings.increaseLyricFor(_landP) : null),
            ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                final starred = widget.controller.currentStarred;
                return _MiniCornerButton(
                  icon: starred ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: starred ? Theme.of(context).colorScheme.primary : null,
                  onTap: widget.controller.toggleStar,
                );
              },
            ),
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                final sg = widget.controller.current;
                final blocked = sg != null && widget.settings.isBlacklisted(sg);
                return _MiniCornerButton(
                  icon: Icons.heart_broken_rounded,
                  color: blocked ? Theme.of(context).colorScheme.error : null,
                  onTap: sg == null ? null : () => _toggleBlacklist(sg),
                );
              },
            ),
          ],
        ),
      );
    }
    // 手机：竖屏小图标 IconTheme 30；横屏用 FittedBox 把整列按钮自适应缩放到歌词区可用高度，避免溢出到进度条
    final Widget bar = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconTheme(
          data: IconThemeData(size: side),
          child: IconButton(
            tooltip: '下载',
            icon: Icon(Icons.download_rounded),
            onPressed: () => _downloadMenu(context),
          ),
        ),
        SizedBox(height: _gap),
        IconTheme(
          data: IconThemeData(size: side),
          child: IconButton(
            tooltip: '下载当前歌曲到NAS',
            icon: Icon(Icons.cloud_download_rounded),
            onPressed: () async {
              showTopToast(context, '正在上传到NAS…');
              final msg = await widget.controller.uploadCurrentToNas();
              if (!context.mounted) return;
              showTopToast(context, msg, duration: const Duration(seconds: 2));
            },
          ),
        ),
        SizedBox(height: _gap),
        IconTheme(
          data: IconThemeData(size: side),
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final sg = widget.controller.current;
              final blocked = sg != null && widget.settings.isBlacklisted(sg);
              return IconButton(
                tooltip: blocked ? '移出黑名单' : '加入黑名单（榜单/歌单不再显示）',
                icon: Icon(Icons.heart_broken_rounded,
                    color: blocked ? Theme.of(context).colorScheme.error : null),
                onPressed: sg == null ? null : () => _toggleBlacklist(sg),
              );
            },
          ),
        ),
      ],
    );
    return Container(
      width: _landP ? 40 : 44,
      margin: const EdgeInsets.only(right: 8),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: bar,
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
              final car = isCarScreen(context);
              final s = math.min(box.maxWidth * (car ? 0.72 : 0.62), box.maxHeight * (car ? 0.78 : 0.62));
              return Column(
                children: [
                  if ((widget.controller.queueSource ?? '').isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(left: 16, bottom: 4, top: isCarScreen(context) ? 40 : 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.controller.queueSource!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant, fontSize: car ? 20 : 16),
                        ),
                      ),
                    ),
                  // 封面：自适应占满上方空间（车机横屏加大）
                  Expanded(
                    child: Center(
                      child: StreamBuilder<bool>(
                        stream: widget.controller.player.playingStream,
                        builder: (context, snap) {
                          final cov = CoverImage(client: widget.controller.client, coverId: song.coverArt, coverUrl: song.coverUrl, size: s, requestSize: 600);
                          return Container(
                            width: s, height: s,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(s * 0.055),
                              boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 26, offset: const Offset(0, 12))],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(s * 0.055),
                              child: cov,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  // 歌名/歌手/专辑 + 首页/返回：下移到底部，与播放控制栏齐平
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 10, 16,
                        isCarScreen(context) &&
                        MediaQuery.of(context).orientation == Orientation.landscape ? 30 : 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _MiniCornerButton(icon: Icons.home_rounded, onTap: () {
                          Navigator.of(context).popUntil((r) => r.isFirst);
                          HomeShell.switchToHome();
                        }),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _MarqueeText(song.title, textAlign: TextAlign.center,
                                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: car ? 26 : 24)),
                              SizedBox(height: car ? 10 : 6),
                              Text('${song.artist} - ${song.album}', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: car ? 17 : 15)),
                            ],
                          ),
                        ),
                        _MiniCornerButton(icon: Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.of(context).maybePop()),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // 右侧：歌词区占满中间（向下扩展）+ 底部进度条+播放控制栏
        Expanded(
          flex: 6,
          child: Column(
            children: [
              // 歌词区：Expanded 占满中间空间，歌词自然向下扩展
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _actionSidebarLeft(context),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
                        child: _lyricsArea(context, song.id),
                      ),
                    ),
                    _actionSidebar(context),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(0, 2, 8,
                    isCarScreen(context) &&
                    MediaQuery.of(context).orientation == Orientation.landscape ? 56 : 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SeekBar(player: widget.controller.player),
                    _Controls(controller: widget.controller, compact: false, onShowQueue: () => _openQueue(context)),
                  ],
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
      behavior: HitTestBehavior.opaque,
      onTap: () {
        widget.controller.reloadLyrics();
        showTopToast(context, '刷新歌词', duration: const Duration(milliseconds: 700));
      },
      onDoubleTap: () {
        widget.controller.reloadLyrics();
        showTopToast(context, '刷新歌词', duration: const Duration(milliseconds: 800));
      },
      onLongPress: () {
        widget.controller.reloadLyrics(switchSource: true);
        showTopToast(context, '歌词源：${widget.controller.lyricSourceName}', duration: const Duration(milliseconds: 900));
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
    final scale = widget.settings.lyricScaleFor(MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height);
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
    final mq = MediaQuery.of(context);
    // 横屏判定直接用宽>高（手机横屏最短边可能 <480，isCarScreen 会返回 false，
    // 必须只按方向判，车机横屏同样宽>高，两者都走右下浮窗）。
    final land = mq.size.width > mq.size.height;
    if (land) {
      // 横屏：右下角收窄小窗浮层。Navigator.push 全屏透明路由 + Stack + Positioned
      // 绝对定位右下（right/bottom 16），位置确定贴右下、不会居中；Container 显式高度
      // 让 _queuePanel 的 Column+Expanded 可靠填充列表；点面板外关闭。
      Navigator.push(
        context,
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.transparent,
          transitionDuration: const Duration(milliseconds: 150),
          pageBuilder: (ctx, _, __) {
            final h = MediaQuery.sizeOf(ctx).height;
            return Scaffold(
              backgroundColor: Colors.transparent,
              body: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Container(
                      width: 340,
                      height: h * 0.6,
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _queuePanel(ctx),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          Theme.of(context).colorScheme.surface.withValues(alpha: 0.78),
      // 固定 60% 屏高的内容区，_queuePanel 的 Column+Expanded 可靠填充列表
      // （DraggableScrollableSheet 在某些设备 Expanded 高度为 0，列表变空白）。
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.6,
        child: _queuePanel(ctx),
      ),
    );
  }

  Widget _queuePanel(BuildContext context,
      {ScrollController? scrollController}) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text('播放列表',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, height: 1.0)),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final q = widget.controller.queue;
              final idx = widget.controller.index;
              return ListView.builder(
                controller: scrollController,
                padding: EdgeInsets.zero,
                itemCount: q.length,
                itemBuilder: (context, i) {
                  final active = i == idx;
                  final sn = q[i];
                  final cs = Theme.of(context).colorScheme;
                  final bl = widget.settings.isBlacklisted(sn);
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    minVerticalPadding: 0,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12),
                    leading: Text('${i + 1}',
                        style: TextStyle(
                            color: active ? cs.primary : cs.onSurfaceVariant)),
                    // 歌名 + 歌手同一行，短横线连接；超长时跑马灯滚动展示完整
                    title: _MarqueeText(
                      (sn.title ?? '') +
                          ((sn.artist ?? '').isNotEmpty
                              ? ' - ${sn.artist}'
                              : ''),
                      style: TextStyle(
                          color: active
                              ? cs.primary
                              : cs.onSurface),
                    ),
                    // 黑名单 / 删除 两图标
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 20,
                          icon: Icon(Icons.heart_broken_rounded,
                              color: bl ? Colors.orange : cs.onSurfaceVariant),
                          onPressed: () async {
                            if (bl) {
                              await widget.settings.removeBlacklist(sn);
                            } else {
                              await widget.settings.addBlacklist(sn);
                            }
                          },
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 20,
                          icon: Icon(Icons.delete_outline_rounded,
                              color: cs.onSurfaceVariant),
                          onPressed: () =>
                              widget.controller.removeFromQueue(i),
                        ),
                      ],
                    ),
                    onTap: () {
                      widget.controller.playAt(i);
                      Navigator.of(context).pop();
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
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
        final scale = widget.settings.lyricScaleFor(MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height);
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
  const LyricSizeControls({super.key, required this.settings, this.land = false});

  final AppSettings settings;
  final bool land;

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
                  settings.canDecreaseLyricFor(land) ? () => settings.decreaseLyricFor(land) : null,
            ),
            IconButton(
              tooltip: '增大歌词字号',
              icon: const Icon(Icons.text_increase),
              onPressed:
                  settings.canIncreaseLyricFor(land) ? () => settings.increaseLyricFor(land) : null,
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
  double _anchor = 0.70; // 当前行锚点，按已唱1行动态算

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
        final scale = widget.settings.lyricScaleFor(MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height);

        return LayoutBuilder(
          builder: (context, constraints) {
            // 已唱占1行、当前占1行、余下给未唱：当前行锚在顶部 padding+1行已唱 处
            final _rowH = (_baseFontSize * 1.4 + 18) * scale;
            _anchor = ((constraints.maxHeight * 0.30) + 1.5 * _rowH) / constraints.maxHeight;
            _anchor = _anchor.clamp(0.04, 0.50);
            return ScrollablePositionedList.builder(
              itemScrollController: _scroll,
              itemCount: lines.length,
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: constraints.maxHeight * 0.23,
                bottom: constraints.maxHeight * 0.26,
              ),
              itemBuilder: (context, i) {
                final line = lines[i];
                final active = !synced || i == _current;
                // 当前行以上的已唱歌词不占位（折叠隐藏）
                if (synced && i < _current) {
                  return const SizedBox.shrink();
                }
                // 歌词细描边：浅色底黑边/深色底亮边（轻量，保证白色歌词可读又不压字）
                final isDark = Theme.of(context).brightness == Brightness.dark;
                final stroke = isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.28);

                return Padding(
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
                                : Color(AppSettings.lyricActiveDefault))
                            : (i < _current
                                ? (widget.settings.lyricPast != 0
                                    ? Color(widget.settings.lyricPast)
                                    : Color(AppSettings.lyricPastDefault))
                                : (widget.settings.lyricFuture != 0
                                    ? Color(widget.settings.lyricFuture)
                                    : Color(AppSettings.lyricFutureDefault))),
                      ),
                        child: Text(line.text.isEmpty ? '♪' : line.text,
                          textAlign: widget.alignRight ? TextAlign.right : TextAlign.left),
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
    // [xmusic] 2026-09-24 车机图标统一：左上角主页/返回按钮图标与控制栏一致（车机48/手机40）
    final car = isCarScreen(context);
    final s = car ? 56.0 : 44.0;
    final isz = car ? 48.0 : 40.0;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(s),
        child: InkWell(
          borderRadius: BorderRadius.circular(s),
          onTap: onTap,
          child: Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(s),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Icon(icon, size: isz, color: theme.colorScheme.onSurface),
          ),
        ),
      ),
    );
  }
}
/// 黑胶唱片旋转：播放时匀速转一圈12秒，暂停时停在当前角度
class _SpinRotator extends StatefulWidget {
  const _SpinRotator({required this.spinning, required this.child});
  final bool spinning;
  final Widget child;
  @override
  State<_SpinRotator> createState() => _SpinRotatorState();
}
class _SpinRotatorState extends State<_SpinRotator> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12));
  @override
  void initState() { super.initState(); if (widget.spinning) _c.repeat(); }
  @override
  void didUpdateWidget(covariant _SpinRotator old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_c.isAnimating) _c.repeat();
    else if (!widget.spinning && _c.isAnimating) _c.stop();
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => RotationTransition(turns: _c, child: widget.child);
}
/// [xmusic] 2026-09-27 黑胶唱片：黑色盘面 + 凹槽纹 + 专辑封面(留边) + 反光 + 中心孔，
/// 播放时整体旋转；叠加识别卡针（播放落下搭在唱片上，暂停抬起）。
class _CdDisc extends StatelessWidget {
  const _CdDisc({super.key, required this.cover, required this.size, required this.spinning});
  /// 专辑封面（已按 label 尺寸构建，label ≈ size*0.76）
  final Widget cover;
  /// 唱片直径
  final double size;
  /// 播放中（驱动旋转 + 卡针落下）
  final bool spinning;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: size * 1.14,
      height: size * 1.14,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 环境光晕：主题色低透明度大光斑，让唱片浮在玻璃上
          Container(
            width: size * 1.14,
            height: size * 1.14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  theme.colorScheme.primary.withValues(alpha: 0.14),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.75],
              ),
            ),
          ),
          // 旋转的 CD 唱片
          _SpinRotator(
            spinning: spinning,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 黑胶盘面（黑胶唱片本体）
                Container(
                  width: size, height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Color(0xFF23262B), Color(0xFF0D0F12), Color(0xFF16181C), Color(0xFF0A0B0D)],
                      stops: [0.0, 0.4, 0.72, 1.0],
                    ),
                    boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 26, offset: const Offset(0, 12))],
                  ),
                ),
                // 黑胶凹槽纹
                Positioned.fill(
                  child: IgnorePointer(child: CustomPaint(painter: _VinylGroovesPainter(size: size))),
                ),
                // 专辑封面：居中并留出金属边 = CD 盘面
                Padding(
                  padding: EdgeInsets.all(size * 0.18),
                  child: ClipOval(child: cover),
                ),
                // 反光扫过（随唱片旋转）
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: const Alignment(-0.7, -1.0),
                          end: const Alignment(0.7, 1.0),
                          colors: [
                            Colors.transparent,
                            Colors.white.withValues(alpha: 0.13),
                            Colors.transparent,
                          ],
                          stops: const [0.44, 0.52, 0.60],
                        ),
                      ),
                    ),
                  ),
                ),
                // 中心孔
                Container(
                  width: size * 0.055, height: size * 0.055,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF14161C)),
                ),
              ],
            ),
          ),
          // 识别卡针（不随唱片旋转，叠在唱片上）
          SizedBox(
            width: size, height: size,
            child: _Tonearm(spinning: spinning, discSize: size),
          ),
        ],
      ),
    );
  }
}
/// 黑胶唱片纹：同心凹槽细环。
class _VinylGroovesPainter extends CustomPainter {
  _VinylGroovesPainter({required this.size});
  final double size;
  @override
  void paint(Canvas canvas, Size s) {
    final c = size / 2;
    final paint = Paint()
      ..color = const Color(0xFF3A3D45).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    for (double r = size * 0.18; r < size * 0.48; r += size * 0.022) {
      canvas.drawCircle(Offset(c, c), r, paint);
    }
  }
  @override
  bool shouldRepaint(_VinylGroovesPainter old) => old.size != size;
}
/// 黑胶识别卡针：播放时落下搭在唱片上，暂停时抬起。
class _Tonearm extends StatefulWidget {
  const _Tonearm({super.key, required this.spinning, required this.discSize});
  final bool spinning;
  final double discSize;
  @override
  State<_Tonearm> createState() => _TonearmState();
}
class _TonearmState extends State<_Tonearm> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    reverseDuration: const Duration(milliseconds: 450),
  );
  late final Animation<double> _anim = CurvedAnimation(parent: _c, curve: Curves.easeInOutCubic);
  @override
  void initState() { super.initState(); _c.value = widget.spinning ? 1.0 : 0.0; }
  @override
  void didUpdateWidget(covariant _Tonearm old) {
    super.didUpdateWidget(old);
    if (widget.spinning && _c.value < 1.0) _c.forward();
    else if (!widget.spinning && _c.value > 0.0) _c.reverse();
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(widget.discSize),
      painter: _TonearmPainter(lift: 1.0 - _anim.value),
    );
  }
}
class _TonearmPainter extends CustomPainter {
  _TonearmPainter({required this.lift});
  /// 0 = 落下(播放)，1 = 抬起(暂停)
  final double lift;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / 2;
    final r = size.width / 2;
    // 唱臂座：唱片右上方（真实黑胶唱机：曲臂从右后侧伸出）
    final pivot = Offset(c + r * 0.82, r * 0.10);
    // 针落点：唱片中心偏左上（半径 0.30r、角度 -0.55）
    const a = -0.55;
    final needle = Offset(c + r * 0.30 * math.cos(a), c + r * 0.30 * math.sin(a));
    // 抬起：暂停绕唱臂座抬起（针离开唱片朝右上），播放归位
    final liftRad = -lift * 0.55;
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(liftRad);
    final dx = needle.dx - pivot.dx;
    final dy = needle.dy - pivot.dy;
    final armLen = math.sqrt(dx * dx + dy * dy);
    canvas.rotate(math.atan2(dy, dx));
    // 臂：细长略带弧度（二次贝塞尔曲臂，更接近黑胶唱机）
    final armPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft, end: Alignment.centerRight,
        colors: [Color(0xFF2C3140), Color(0xFF565E70)],
      ).createShader(Rect.fromLTWH(0, -4, armLen, 8));
    final armPath = Path()
      ..moveTo(0, -2.8)
      ..quadraticBezierTo(armLen * 0.55, -5.0, armLen, -1.8)
      ..lineTo(armLen + r * 0.08, 2.2)
      ..quadraticBezierTo(armLen * 0.55, 3.2, 0, 2.8)
      ..close();
    canvas.drawPath(armPath, armPaint);
    // 针头（唱针）：臂末端小圆头，斜向唱片
    canvas.translate(armLen, 0);
    canvas.rotate(-0.7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-7, -2.4, 18, 6.2), const Radius.circular(3)),
      Paint()..color = const Color(0xFF1A1D24),
    );
    canvas.drawCircle(const Offset(12, 0), 2.8, Paint()..color = const Color(0xFF8B93A5));
    canvas.restore();
    // 唱臂座（盖在最上层，随唱片尺寸缩放）
    canvas.drawCircle(pivot, r * 0.055, Paint()..color = const Color(0xFF3A4150));
    canvas.drawCircle(pivot, r * 0.028, Paint()..color = const Color(0xFF14161C));
  }
  @override
  bool shouldRepaint(_TonearmPainter old) => old.lift != lift;
}
/// 车机/大屏判定：横屏或最短边 >=480dp 均视为大屏（含竖屏车机），用于放大按钮/图标
bool _carUI(BuildContext context) =>
    isCarScreen(context) || MediaQuery.sizeOf(context).shortestSide >= 480;

/// 小玻璃圆钮（歌名行两侧：首页/返回）
class _MiniCornerButton extends StatelessWidget {
  const _MiniCornerButton({required this.icon, this.onTap, this.color});
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: theme.colorScheme.surface.withValues(alpha: 0.18),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              // [xmusic] 2026-09-28 手机主页/返回也加大：56 容器 / 40 图标（对齐控制栏图标），车机 64/48
              width: _carUI(context) ? 64 : 44, height: _carUI(context) ? 64 : 44,
              child: Icon(icon, size: _carUI(context) ? 48 : 30, color: color ?? theme.colorScheme.onSurface),
            ),
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
    final gap = compact ? 20.0 : 20.0;
    // [xmusic] 2026-09-24 车机图标统一：左上角/右侧栏/控制栏图标尺寸全部一致（车机48/手机40）
    final car = isCarScreen(context);
    final land = MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    final playSize = car ? (land ? 76.0 : 82.0) : 40.0;
    final navSize = car ? (land ? 76.0 : 82.0) : 40.0;
    final sideIcon = car ? 72.0 : 40.0;
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


/// 播放页单例入口：栈中已存在播放页则归一到最上层（不重复 push），
/// 否则 push 一层。避免从不同列表反复点歌把播放页堆叠多层（“返回要两次”）。
Future<void> openPlayerPage(
  BuildContext context, {
  required AppSettings settings,
  required PlayerController controller,
}) async {
  final nav = Navigator.of(context);
  if (PlayerPage._stackCount > 0) {
    nav.popUntil(
        (r) => r.isFirst || r.settings.name == PlayerPage.routeName);
    return;
  }
  await nav.push(MaterialPageRoute(
    settings: const RouteSettings(name: PlayerPage.routeName),
    builder: (_) => PlayerPage(settings: settings, controller: controller),
  ));
}


/// 歌名滚动组件：文本超出可用宽度时循环左右滚动展示（不超出则普通省略号文本）。
class _MarqueeText extends StatefulWidget {
  const _MarqueeText(this.text,
      {super.key, this.style, this.textAlign = TextAlign.start, this.maxWidth});
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  /// 确定的可视宽度；不传则用父约束。传明确宽度可避免 LayoutBuilder 拿到不准确的约束。
  final double? maxWidth;
  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final ScrollController _s;
  @override
  void initState() {
    super.initState();
    _s = ScrollController();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..addListener(_tick)
      ..repeat();
  }
  void _tick() {
    if (!mounted || !_s.hasClients) return;
    // maxScrollExtent 由 SingleChildScrollView 实际布局算出（真实文本宽-视口宽）：
    // 长文本 >0 → 真实滚动、尾部必然滚入；短文本 <=0 → 静止完整显示，不滚动
    _s.jumpTo(_s.position.maxScrollExtent * _c.value);
  }
  @override
  void dispose() {
    _s.dispose();
    _c.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cons) {
      final tp = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(ctx),
      )..layout();
      final boxW = widget.maxWidth != null
          ? widget.maxWidth!
          : (cons.maxWidth.isFinite
              ? cons.maxWidth
              : (MediaQuery.sizeOf(ctx).width * 0.86));
      if (boxW <= 0) return const SizedBox.shrink();
      // 短文本（能完整显示）：不滚动，按 textAlign 对齐（居中则真正居中），完整展示
      if (tp.width <= boxW) {
        return Align(
          alignment: widget.textAlign == TextAlign.center ? Alignment.center : Alignment.centerLeft,
          child: Text(widget.text, style: widget.style, maxLines: 1,
              overflow: TextOverflow.ellipsis, softWrap: false, textAlign: widget.textAlign),
        );
      }
      return ClipRect(
        child: SizedBox(
          width: boxW,
          height: tp.height,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            controller: _s,
            child: Text(widget.text, style: widget.style, maxLines: 1,
                softWrap: false, textAlign: widget.textAlign),
          ),
        ),
      );
    });
  }
}
