import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../widgets.dart';
import 'album_page.dart';
import 'library_page.dart';
import 'player_page.dart';
import 'search_page.dart';

/// Home page: newest albums, daily mix and recent albums.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.settings, required this.controller});

  final AppSettings settings;
  final PlayerController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Album>> _newest;
  late Future<List<Song>> _random;
  late Future<List<Album>> _recent;
  late Future<List<Album>> _frequent;

  SubsonicClient get _client => widget.controller.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _newest = _client.newestAlbums();
    _random = _client.randomSongs(size: 20);
    _recent = _client.recentAlbums(size: 20);
    _frequent = _client.frequentAlbums(size: 20);
  }

  void _reload() => setState(_load);

  Future<void> _openAlbum(Album a) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AlbumPage(
        settings: widget.settings,
        controller: widget.controller,
        album: a,
      ),
    ));
    if (mounted) setState(() {}); // mini player state refresh
  }

  Future<void> _playSongs(List<Song> songs, int index) async {
    await widget.controller.playQueue(songs, index);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(
        settings: widget.settings,
        controller: widget.controller,
      ),
    ));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('音乐'),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SearchPage(
                settings: widget.settings,
                controller: widget.controller,
              ),
            )),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder(
          future: Future.wait([_newest, _random, _recent, _frequent]),
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
                    FilledButton(onPressed: _reload, child: const Text('重试')),
                  ],
                ),
              );
            }
            final data = snap.data as List;
            final newest = data[0] as List<Album>;
            final random = data[1] as List<Song>;
            final recent = data[2] as List<Album>;
            final frequent = data[3] as List<Album>;

            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                // ---- 每日推荐 ----
                SectionHeader(
                  title: '每日推荐',
                  actionLabel: random.isEmpty ? null : '播放全部',
                  onAction: random.isEmpty
                      ? null
                      : () => _playSongs(random, 0),
                ),
                if (random.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('暂无推荐歌曲'),
                  )
                else
                  ...List.generate(
                    random.length > 8 ? 8 : random.length,
                    (i) => SongTile(
                      song: random[i],
                      client: _client,
                      onTap: () => _playSongs(random, i),
                    ),
                  ),

                // ---- 最新专辑 ----
                SectionHeader(
                  title: '最新专辑',
                  actionLabel: newest.isEmpty ? null : '更多',
                  onAction: newest.isEmpty
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => LibraryPage(
                              settings: widget.settings,
                              controller: widget.controller,
                              initialTab: 0,
                            ),
                          )),
                ),
                _albumRow(newest),

                // ---- 最近播放 ----
                SectionHeader(
                  title: '最近播放',
                  actionLabel: recent.isEmpty ? null : '更多',
                  onAction: recent.isEmpty
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => LibraryPage(
                              settings: widget.settings,
                              controller: widget.controller,
                              initialTab: 0,
                            ),
                          )),
                ),
                _albumRow(recent),

                // ---- 常听专辑 ----
                SectionHeader(title: '常听专辑'),
                _albumRow(frequent),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _albumRow(List<Album> albums) {
    if (albums.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text('暂无内容'),
      );
    }
    return SizedBox(
      height: 190,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: albums.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: AlbumCard(
            album: albums[i],
            client: _client,
            width: 130,
            onTap: () => _openAlbum(albums[i]),
          ),
        ),
      ),
    );
  }
}
