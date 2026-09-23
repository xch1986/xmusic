import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../widgets.dart';
import 'mini_player.dart';
import 'player_page.dart';

/// Playlist page: songs of a single playlist.
/// 支持左滑删除歌曲（移除记录按歌单名本地持久化，与首页歌单一致）。
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
  Set<String> _removed = <String>{};

  SubsonicClient get _client => widget.controller.client;

  @override
  void initState() {
    super.initState();
    _future = _client.playlistSongs(widget.playlist.id);
    _loadRemoved();
  }

  Future<void> _loadRemoved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'playlist_removed_${widget.playlist.name}';
      final list = prefs.getStringList(key) ?? const <String>[];
      if (!mounted) return;
      setState(() => _removed = list.toSet());
    } catch (_) {}
  }

  Future<void> _removeSong(Song song) async {
    setState(() => _removed = {..._removed, song.id});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          'playlist_removed_${widget.playlist.name}', _removed.toList());
    } catch (_) {}
  }

  /// 未被移除的歌曲在原始列表中的索引（onPlay 需要原始索引）
  List<int> _visibleIndices(List<Song> songs) {
    final out = <int>[];
    for (var i = 0; i < songs.length; i++) {
      if (!_removed.contains(songs[i].id)) out.add(i);
    }
    return out;
  }

  Future<void> _playSongs(List<Song> songs, int index) async {
    await widget.controller.playQueue(songs, index);
    if (mounted) setState(() {});
    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerPage(
          settings: widget.settings,
          controller: widget.controller,
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: Text(widget.playlist.name)),
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
                          onPressed: () => setState(() =>
                              _future = _client.playlistSongs(widget.playlist.id)),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  );
                }
                final songs = snap.data!;
                final vis = _visibleIndices(songs);
                if (songs.isEmpty) return const Center(child: Text('歌单为空'));
                if (vis.isEmpty) return const Center(child: Text('已全部移除'));
                // 底部留白 = 系统手势条/车机底栏 inset + 余量，
                // 保证最后一行歌曲永远能滚到底部 MiniPlayer / 系统栏之上，不被遮挡。
                final bottomInset = MediaQuery.paddingOf(context).bottom + 16;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('${vis.length} 首歌曲',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('顺序'),
                            onPressed: () => _playSongs(songs, vis[0]),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            icon: const Icon(Icons.shuffle_rounded),
                            label: const Text('随机'),
                            onPressed: () {
                              final s = vis.map((i) => songs[i]).toList()..shuffle();
                              _playSongs(s, 0);
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.only(bottom: bottomInset),
                        itemCount: vis.length,
                        itemBuilder: (context, k) {
                          final i = vis[k];
                          final song = songs[i];
                          return Dismissible(
                            key: ValueKey('pl_${widget.playlist.name}_${song.id}'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: Theme.of(context).colorScheme.error,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(Icons.delete_outline_rounded,
                                  color: Colors.white),
                            ),
                            onDismissed: (_) => _removeSong(song),
                            child: SongTile(
                              song: song,
                              client: _client,
                              onTap: () => _playSongs(songs, i),
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
          MiniPlayer(settings: widget.settings, controller: widget.controller),
        ],
      ),
    );
  }
}
