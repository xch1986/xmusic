import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../widgets.dart';
import 'mini_player.dart';
import 'player_page.dart';

/// Playlist page: songs of a single playlist.
class PlaylistPage extends StatefulWidget {
  const PlaylistPage({
    super.key,
    required this.settings,
    required this.controller,
    required this.playlist,
  });

  final AppSettings settings;
  final PlayerController controller;
  final Playlist playlist;

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  late Future<List<Song>> _future;

  SubsonicClient get _client => widget.controller.client;

  @override
  void initState() {
    super.initState();
    _future = _client.playlistSongs(widget.playlist.id);
  }

  Future<void> _playSongs(List<Song> songs, int index) async {
    await widget.controller.playQueue(songs, index);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.playlist.name)),
      bottomNavigationBar: MiniPlayer(settings: widget.settings, controller: widget.controller),
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
                        _future = _client.playlistSongs(widget.playlist.id)),
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          final songs = snap.data!;
          if (songs.isEmpty) return const Center(child: Text('歌单为空'));
          // 底部留白 = 系统手势条/车机底栏 inset + MiniPlayer 高度 + 余量，
          // 保证最后一行歌曲永远能滚到 MiniPlayer / 系统栏之上，不被遮挡。
          final bottomInset = MediaQuery.paddingOf(context).bottom + 96;
          return ListView(
            padding: EdgeInsets.only(bottom: bottomInset),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${songs.length} 首歌曲',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                      onPressed: () { final s = [...songs]..shuffle(); _playSongs(s, 0); },
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
