import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../widgets.dart';
import 'mini_player.dart';

/// Artist page: 直接展示该歌手的歌曲列表（搜索该歌手名下歌曲），
/// 不做专辑网格；底部挂全局迷你播放条，点击歌曲播放后立即可见。
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
  late Future<List<Song>> _future;

  SubsonicClient get _client => widget.controller.client;

  @override
  void initState() {
    super.initState();
    _future = _client.artistSongs(widget.artist.name);
  }

  Future<void> _playSongs(List<Song> songs, int index) async {
    // 只播放不跳转：底部全局迷你播放条立即出现（车机/列表场景）
    await widget.controller.playQueue(songs, index);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.artist.name)),
      // 全局播放栏位：点击歌曲列表开始播放后，底部立即显示迷你播放条
      bottomNavigationBar: MiniPlayer(
        settings: widget.settings,
        controller: widget.controller,
      ),
      body: FutureBuilder<List<Song>>(
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
                        _future = _client.artistSongs(widget.artist.name)),
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          final songs = snap.data!;
          if (songs.isEmpty) {
            return const Center(child: Text('暂无该歌手的歌曲'));
          }
          return ListView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 16,
            ),
            children: [
              // 歌手头部 + 播放按钮
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${songs.length} 首歌曲',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  )),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('顺序'),
                      onPressed: () => _playSongs(songs, 0),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('随机'),
                      onPressed: () {
                        final s = [...songs]..shuffle();
                        _playSongs(s, 0);
                      },
                    ),
                  ],
                ),
              ),
              ...List.generate(
                songs.length,
                (i) => SongTile(
                  song: songs[i],
                  client: _client,
                  onTap: () => _playSongs(songs, i),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
