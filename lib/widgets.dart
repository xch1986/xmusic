import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'subsonic.dart';

/// 车机屏判定：横屏且最短边 >= 480dp（比亚迪等车机横屏大屏）。
/// 车机上文字等比放大，避免"手机上正常、车机上显小"。
bool isCarScreen(BuildContext context) {
  final s = MediaQuery.of(context).size;
  // 大屏（横竖）都按车机处理：比亚迪车机横屏/竖屏均为大屏，竖屏也走车机 UI
  return s.shortestSide >= 480;
}

/// 大屏字体放大系数：车机横屏大屏 1.35x；竖屏大屏(最短边>=480dp，如车机竖屏/平板) 1.25x；手机 1.0x。
double bigScreenTextScale(BuildContext context) {
  final s = MediaQuery.sizeOf(context);
  if (s.shortestSide >= 480) return 1.35;
  return 1.0;
}

/// 大屏字体放大包装：车机横屏1.35x / 竖屏大屏1.25x，手机原样。
class BigScreenText extends StatelessWidget {
  const BigScreenText({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final scale = bigScreenTextScale(context);
    if (scale <= 1.0) return child;
    // 外层（main.dart 全局大屏放大）已放大则不重复，避免双重放大
    final cur = mq.textScaler.scale(14) / 14;
    if (cur >= 1.15) return child;
    return MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(scale)), child: child);
  }
}

/// Cover art loaded from the server (or a direct URL), with a neutral
/// placeholder. Colors come from the current theme only — nothing is
/// extracted from the art.
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.client,
    required this.coverId,
    this.coverUrl,
    this.size,
    this.radius = 12,
    this.requestSize = 600,
  });

  final SubsonicClient? client;
  final String? coverId;
  final String? coverUrl;
  final double? size;
  final double radius;
  final int requestSize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // A direct URL wins over a server cover id (external songs).
    final url = coverUrl?.isNotEmpty == true
        ? Uri.parse(coverUrl!)
        : client?.coverUrl(coverId, size: requestSize);

    final placeholder = ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.music_note_rounded, color: cs.onSurfaceVariant),
      ),
    );

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: url == null
            ? placeholder
            : (url.scheme == 'file'
                // 本地封面（file://）：直接用 Image.file 渲染，不走网络缓存
                ? Image.file(
                    File(url.toFilePath()),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => placeholder,
                  )
                : CachedNetworkImage(
                    imageUrl: url.toString(),
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 200),
                    fadeOutDuration: const Duration(milliseconds: 200),
                    httpHeaders: _imgHeaders(url.toString()),
                    errorWidget: (_, __, ___) => placeholder,
                    placeholder: (_, __) => placeholder,
                  )),
      ),
    );
  }
}

/// Album cover card used in grids and horizontal lists.
class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.album,
    required this.client,
    required this.onTap,
    this.width,
  });

  final Album album;
  final SubsonicClient? client;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = width ?? 140.0;
    return SizedBox(
      width: w,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverImage(
              client: client,
              coverId: album.coverArt,
              size: w,
              radius: 12,
              requestSize: 360,
            ),
            const SizedBox(height: 6),
            Text(album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall),
            Text(album.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// Song 不可变，收藏状态变化后用它重建一首歌。
Song withStarred(Song s, bool v) => Song(
      id: s.id,
      title: s.title,
      artist: s.artist,
      album: s.album,
      albumId: s.albumId,
      durationSec: s.durationSec,
      coverArt: s.coverArt,
      starred: v,
      coverUrl: s.coverUrl,
      streamUrl: s.streamUrl,
      fromExternal: s.fromExternal,
      externalSource: s.externalSource,
    );

/// A tappable song row with cover, title, artist, duration and a play button.
/// 过滤演唱会/现场/Live 版本歌曲（全局歌曲列表统一过滤）
bool isLiveOrConcert(String? title) {
  if (title == null || title.isEmpty) return false;
  final t = title.toLowerCase();
  return t.contains('演唱会') || t.contains('现场') || t.contains('live');
}

class SongTile extends StatefulWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.client,
    required this.onTap,
    this.trailing,
    this.showAlbum = false,
    this.leading,
    this.onFavorite,
    this.onBlacklist,
    this.blacklisted = false,
    this.onDelete,
  });

  final Song song;
  final SubsonicClient? client;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showAlbum;
  final Widget? leading;
  /// 收藏回调（提供则左滑露出收藏按钮）
  final VoidCallback? onFavorite;
  /// 黑名单回调（提供则左滑露出黑名单按钮）
  final VoidCallback? onBlacklist;
  /// 当前是否已加入黑名单（黑名单按钮高亮）
  final bool blacklisted;
  /// 删除回调（提供则左滑露出删除按钮）
  final VoidCallback? onDelete;

  @override
  State<SongTile> createState() => _SongTileState();
}

class _SongTileState extends State<SongTile> {
  double _dx = 0;
  static const double _minDx = -144;

  bool get _enabled =>
      widget.onFavorite != null ||
      widget.onBlacklist != null ||
      widget.onDelete != null;

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: widget.leading ??
          CoverImage(
            client: widget.client,
            coverId: widget.song.coverArt,
            coverUrl: widget.song.coverUrl,
            size: 44,
            radius: 8,
            requestSize: 120,
          ),
      title: Text(widget.song.title ?? '',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        widget.showAlbum
            ? '${widget.song.artist ?? ''} · ${widget.song.album ?? ''}'
            : (widget.song.artist ?? '未知'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: widget.trailing ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.song.durationSec != null)
                Text(formatDuration(Duration(seconds: widget.song.durationSec!)),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              Icon(Icons.play_circle_outline,
                  color: theme.colorScheme.primary),
            ],
          ),
      onTap: () {
        if (_dx < -20) {
          _close();
        } else {
          widget.onTap();
        }
      },
    );
  }

  void _close() => setState(() => _dx = 0);

  Widget _swipeBtn(IconData icon, Color color, VoidCallback onTap,
      {bool active = false}) {
    return GestureDetector(
      onTap: () {
        onTap();
        _close();
      },
      child: Container(
        width: 48,
        color: color.withValues(alpha: active ? 0.85 : 0.65),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 全局过滤：演唱会/现场/Live 版本歌曲不展示（列表项高度为 0，不占位不空行）
    if (isLiveOrConcert(widget.song.title)) {
      return const SizedBox.shrink();
    }
    if (!_enabled) return _content(context);
    final theme = Theme.of(context);
    return Stack(
      children: [
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          child: IgnorePointer(
            // 未左滑开时按钮不可点也不可见（AnimatedOpacity 0），
            // 左滑（_dx<0）才渐显——既保留"左滑露出"交互，又不让按钮平时透出透明列表项。
            ignoring: _dx >= -20,
            child: AnimatedOpacity(
              opacity: _dx < -20 ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onFavorite != null)
                    _swipeBtn(
                        widget.song.starred
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        Colors.redAccent,
                        widget.onFavorite!,
                        active: widget.song.starred),
                  if (widget.onBlacklist != null)
                    _swipeBtn(Icons.heart_broken_rounded, Colors.orange,
                        widget.onBlacklist!,
                        active: widget.blacklisted),
                  if (widget.onDelete != null)
                    _swipeBtn(Icons.delete_outline_rounded, Colors.blueGrey,
                        widget.onDelete!),
                ],
              ),
            ),
          ),
        ),
        GestureDetector(
          onHorizontalDragUpdate: (d) {
            setState(() => _dx = (_dx + d.delta.dx).clamp(_minDx, 0.0));
          },
          onHorizontalDragEnd: (_) {
            setState(() => _dx = _dx < -48 ? _minDx : 0);
          },
          child: Transform.translate(
            offset: Offset(_dx, 0),
            child: Container(
              // 透明底：列表项不再是白色瓷砖，露出页面封面玻璃背景
              // （此前 colorScheme.surface=纯白 255 是"详情页/播放列表背景发白"的根源）
              color: Colors.transparent,
              child: _content(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// Section header with an optional action button.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
      child: Row(
        children: [
          Text(title, style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

String formatDuration(Duration d) {
  final m = d.inMinutes.remainder(100).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

Map<String, String> _imgHeaders(String u) {
  final host = Uri.parse(u).host.toLowerCase();
  if (host.contains('qq.com') || host.contains('gtimg.cn')) {
    return const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://y.qq.com/'};
  }
  if (host.contains('163') || host.contains('126.net')) {
    return const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://music.163.com/'};
  }
  return const {'User-Agent': 'Mozilla/5.0'};
}
