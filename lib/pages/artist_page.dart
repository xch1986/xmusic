import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../toast.dart';
import '../widgets.dart';
import '../cover_glass.dart';
import 'album_page.dart';
import 'player_page.dart';
import 'mini_player.dart';

/// Artist page: 二级目录——歌手名 → 该歌手的专辑列表 → 点专辑进 AlbumPage（歌曲）。
/// 顶部提供"全部歌曲"顺序/随机播放；专辑点击进入专辑页。
class ArtistPage extends StatefulWidget {
  const ArtistPage({
    super.key,
    required this.settings,
    required this.controller,
    required this.artist,
  });

  final AppSettings settings;
  final PlayerController controller;
  final Artist artist;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  late Future<List<Album>> _future;

  SubsonicClient? get _client => widget.controller.client;

  @override
  void initState() {
    super.initState();
    _future = _client?.artistAlbums(widget.artist.id) ??
        Future.value(<Album>[]);
  }

  Future<void> _playAll({bool shuffle = false}) async {
    final c = _client;
    if (c == null) {
      if (!mounted) return;
      showTopToast(context, '未配置 Navidrome，请到 设置-源 中配置服务器');
      return;
    }
    try {
      final songs = await c.artistSongs(widget.artist.name);
      if (!mounted) return;
      if (shuffle) songs.shuffle();
      await widget.controller.playQueue(songs, 0, source: '歌手 · ${widget.artist.name}');
      if (mounted) setState(() {});
      if (context.mounted) {
        await openPlayerPage(context, settings: widget.settings, controller: widget.controller);
      }
    } catch (e) {
      if (!mounted) return;
      showTopToast(context, '播放失败：$e');
    }
  }

  void _openAlbum(Album a) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AlbumPage(
        settings: widget.settings,
        controller: widget.controller,
        album: a,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BigScreenText(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // 状态栏透明+图标颜色跟随主题：避免深色主题下状态栏变黑（AnnotatedRegion 双保险）
        value: (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(
                statusBarColor: widget.settings.coverColorBg
                    ? Colors.transparent
                    : Theme.of(context).colorScheme.surfaceContainer),
        child: PageBackground(
          controller: widget.controller,
          settings: widget.settings,
          child: Scaffold(
          // 不透明背景：避免半透明主题透出下层页面导致列表视觉混乱（0.2.x 修复回归）
          // [xmusic] 2026-09-28 透明背景：透出全局封面玻璃背景（与首页歌单详情等统一）
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: Text(widget.artist.name)),
          body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Album>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('加载失败：${snap.error}'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => setState(() =>
                              _future = _client?.artistAlbums(widget.artist.id) ??
                                  Future.value(<Album>[])),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  );
                }
                final albums = snap.data!;
                if (albums.isEmpty) {
                  return const Center(child: Text('暂无该歌手的专辑'));
                }
                return ListView(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(context).bottom + 16,
                  ),
                  children: [
                    // 歌手头部：专辑数 + 全部歌曲播放
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${albums.length} 张专辑',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('全部顺序'),
                            onPressed: () => _playAll(),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            icon: const Icon(Icons.shuffle_rounded),
                            label: const Text('随机'),
                            onPressed: () => _playAll(shuffle: true),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 8),
                    // 专辑列表（二级目录）
                    ...List.generate(
                      albums.length,
                      (i) => ListTile(
                        leading: CoverImage(
                          client: _client,
                          coverId: albums[i].coverArt,
                          size: 48,
                          radius: 8,
                          requestSize: 120,
                        ),
                        title: Text(albums[i].name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [albums[i].artist,
                           if (albums[i].songCount != null) '${albums[i].songCount} 首']
                              .where((s) => s.isNotEmpty)
                              .join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openAlbum(albums[i]),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // 迷你播放条放 body 底部而非 bottomNavigationBar（0.2.x 修复回归）
          MiniPlayer(
            settings: widget.settings,
            controller: widget.controller,
          ),
        ],
      )),
      ),
    ));
  }
}
