import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../widgets.dart';
import 'mini_player.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage({
    super.key,
    required this.settings,
    required this.controller,
    required this.album,
  });

  final AppSettings settings;
  final PlayerController controller;
  final Album album;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  late Future<List<Song>> _future;

  SubsonicClient get _client => widget.controller.client;

  @override
  void initState() {
    super.initState();
    _future = _client.albumSongs(widget.album.id);
  }

  Future<void> _playSongs(List<Song> songs, int index) async {
    // 只播放不跳转：底部全局迷你播放条立即出现（车机/列表场景）
    await widget.controller.playQueue(songs, index);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final album = widget.album;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: Text(album.name)),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Song>>(
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
                    onPressed: () => setState(
                        () => _future = _client.albumSongs(widget.album.id)),
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          final songs = snap.data!;
          // 底部留白 = 系统手势条/车机底栏 inset + MiniPlayer 高度 + 余量。
          final bottomInset = MediaQuery.paddingOf(context).bottom + 96;
          return ListView(
            padding: EdgeInsets.only(bottom: bottomInset),
            children: [
              // ---- 专辑头部 ----
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CoverImage(
                      client: _client,
                      coverId: album.coverArt,
                      size: 140,
                      radius: 14,
                      requestSize: 420,
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(album.name,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(album.artist,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          if (album.year != null || album.songCount != null)
                            Text(
                              [
                                if (album.year != null) '${album.year}',
                                if (album.songCount != null)
                                  '${album.songCount} 首',
                              ].join(' · '),
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('顺序'),
                            onPressed: songs.isEmpty ? null : () => _playSongs(songs, 0),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            icon: const Icon(Icons.shuffle_rounded),
                            label: const Text('随机'),
                            onPressed: songs.isEmpty ? null : () { final s = [...songs]..shuffle(); _playSongs(s, 0); },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 16),
              // ---- 歌曲列表 ----
              if (songs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('专辑内没有歌曲')),
                )
              else
                ...List.generate(
                  songs.length,
                  (i) => SongTile(
                    song: songs[i],
                    client: _client,
                    showAlbum: false,
                    leading: SizedBox(
                      width: 40,
                      child: Center(
                        child: Text('${i + 1}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ),
                    ),
                    onTap: () => _playSongs(songs, i),
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
      ),
    );
  }
}