import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../widgets.dart';
import 'album_page.dart';
import 'library_page.dart';
import 'player_page.dart';
import 'search_page.dart';

/// Home page: multi-source recommendations + newest albums.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.settings, required this.controller});

  final AppSettings settings;
  final PlayerController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Album>> _newest;
  late Future<List<Song>> _qqRec;
  late Future<List<Song>> _neteaseRec;
  late Future<List<Song>> _localRec;

  SubsonicClient get _client => widget.controller.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _newest = _client.newestAlbums();
    final ext = widget.controller.external;
    // QQ音乐推荐
    _qqRec = ext
        .search('热门华语流行', limit: 20, source: 'qq')
        .timeout(const Duration(seconds: 30))
        .catchError((_) => <Song>[]);
    // 网易云推荐
    _neteaseRec = ext
        .search('热门华语流行', limit: 20, source: 'netease')
        .timeout(const Duration(seconds: 30))
        .catchError((_) => <Song>[]);
    // 本地推荐
    _localRec = _client.randomSongs(size: 20);
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
    if (mounted) setState(() {});
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
        title: const Text('音素'),
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
          future: Future.wait([_newest, _qqRec, _neteaseRec, _localRec]),
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
            final qq = data[1] as List<Song>;
            final netease = data[2] as List<Song>;
            final local = data[3] as List<Song>;

            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                // QQ音乐推荐
                if (qq.isNotEmpty) ...[
                  SectionHeader(
                    title: 'QQ音乐推荐',
                    actionLabel: '播放全部',
                    onAction: () => _playSongs(qq, 0),
                  ),
                  _songRow(qq),
                ],
                // 网易云推荐
                if (netease.isNotEmpty) ...[
                  SectionHeader(
                    title: '网易云推荐',
                    actionLabel: '播放全部',
                    onAction: () => _playSongs(netease, 0),
                  ),
                  _songRow(netease),
                ],
                // 本地推荐
                if (local.isNotEmpty) ...[
                  SectionHeader(
                    title: '本地推荐',
                    actionLabel: '播放全部',
                    onAction: () => _playSongs(local, 0),
                  ),
                  _songRow(local),
                ],
                // 最新专辑
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
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _songRow(List<Song> songs) {
    return SizedBox(
      height: 190,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: songs.length > 12 ? 12 : songs.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: _SongCard(
            song: songs[i],
            client: _client,
            onTap: () => _playSongs(songs, i),
          ),
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

/// 歌曲卡片：封面 + 歌名/歌手叠加。
class _SongCard extends StatelessWidget {
  const _SongCard({
    required this.song,
    required this.client,
    required this.onTap,
  });

  final Song song;
  final SubsonicClient client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 130,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CoverImage(
                  client: client,
                  coverId: song.coverArt,
                  coverUrl: song.coverUrl,
                  size: 130,
                  radius: 12,
                  requestSize: 360,
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Icon(Icons.play_circle_fill_rounded,
                      size: 28, color: Colors.white.withOpacity(0.9)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall),
            Text(song.artist,
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
