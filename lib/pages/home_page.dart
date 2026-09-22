import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../widgets.dart';
import 'player_page.dart';
import 'search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.settings, required this.controller});

  final AppSettings settings;
  final PlayerController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Map<String, dynamic>>> _toplists;
  late Future<List<Song>> _hotSongs;
  late Future<List<Song>> _localRec;

  SubsonicClient get _client => widget.controller.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final ext = widget.controller.external;
    // 真实排行榜
    _toplists = ext.getToplists().timeout(const Duration(seconds: 15)).catchError((_) => <Map<String, dynamic>>[]);
    // 热歌榜歌曲
    _hotSongs = ext.getPlaylistSongs('3778678').timeout(const Duration(seconds: 20)).catchError((_) => <Song>[]);
    // 本地推荐
    _localRec = _client.randomSongs(size: 20);
  }

  void _reload() => setState(_load);

  Future<void> _playSongs(List<Song> songs, int index) async {
    await widget.controller.playQueue(songs, index);
    if (mounted) setState(() {});
  }

  Future<void> _openPlaylist(String name, String playlistId, {String? coverUrl}) async {
    final ext = widget.controller.external;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    final songs = await ext.getPlaylistSongs(playlistId).timeout(const Duration(seconds: 20));
    if (!mounted) return;
    Navigator.pop(context); // dismiss loading
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('加载失败')));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PlaylistDetail(
        title: name,
        songs: songs,
        client: _client,
        coverUrl: coverUrl,
        onPlay: (i) => _playSongs(songs, i),
      ),
    ));
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
              builder: (_) => SearchPage(settings: widget.settings, controller: widget.controller),
            )),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            // 每日推荐/热歌榜大卡片
            FutureBuilder<List<Song>>(
              future: _hotSongs,
              builder: (context, snap) {
                if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
                return _dailyCard(snap.data!);
              },
            ),
            // 排行榜网格
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('排行榜',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _toplists,
              builder: (context, snap) {
                if (!snap.hasData || snap.data!.isEmpty) {
                  return const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('加载排行榜...')));
                }
                // 取前6个排行榜
                final lists = snap.data!.take(6).toList();
                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.5,
                  children: lists.map((t) => _toplistCard(
                    t['name'] as String,
                    t['id'] as String,
                    t['coverImgUrl'] as String?,
                  )).toList(),
                );
              },
            ),
            // 本地推荐
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text('本地推荐',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            SizedBox(
              height: 190,
              child: FutureBuilder<List<Song>>(
                future: _localRec,
                builder: (context, snap) {
                  if (!snap.hasData || snap.data!.isEmpty) {
                    return const Center(child: Text('加载中...'));
                  }
                  final songs = snap.data!;
                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: songs.length > 12 ? 12 : songs.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _Card(song: songs[i], client: _client,
                          onTap: () => _playSongs(songs, i)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dailyCard(List<Song> songs) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openPlaylist('热歌榜', '3778678'),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFFE85D4A), Color(0xFFF08A3E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.trending_up_rounded, color: Colors.white, size: 36),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('热歌榜', style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('${songs.length}首热门歌曲', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70)),
                    ],
                  ),
                ),
                const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toplistCard(String name, String id, String? coverUrl) {
    final theme = Theme.of(context);
    return Material(
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openPlaylist(name, id, coverUrl: coverUrl),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (coverUrl != null && coverUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: coverUrl,
                  fit: BoxFit.cover,
                  httpHeaders: const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://music.163.com/'},
                  placeholder: (_, __) => Container(color: theme.colorScheme.surfaceContainerHighest),
                  errorWidget: (_, __, ___) => Container(color: theme.colorScheme.surfaceContainerHighest),
                )
              else
                Container(color: theme.colorScheme.surfaceContainerHighest),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
                  ),
                ),
              ),
              Positioned(
                left: 12, bottom: 10,
                child: Text(name, style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w600,
                  shadows: [const Shadow(blurRadius: 4, color: Colors.black54)],
                )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 歌单详情页
class _PlaylistDetail extends StatelessWidget {
  const _PlaylistDetail({
    required this.title,
    required this.songs,
    required this.client,
    required this.onPlay,
    this.coverUrl,
  });

  final String title;
  final List<Song> songs;
  final SubsonicClient client;
  final void Function(int index) onPlay;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          // 歌单封面头部
          if (coverUrl != null && coverUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: coverUrl!,
                      width: 80, height: 80, fit: BoxFit.cover,
                      httpHeaders: const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://music.163.com/'},
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('共 ${songs.length} 首', style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => onPlay(0),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('播放全部'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    songs.shuffle();
                    onPlay(0);
                  },
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('随机播放'),
                ),
                const SizedBox(width: 12),
                Text('共 ${songs.length} 首',
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: songs.length,
              itemBuilder: (context, i) => SongTile(
                song: songs[i],
                client: client,
                onTap: () => onPlay(i),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.song, required this.client, required this.onTap});
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
            Stack(children: [
              CoverImage(client: client, coverId: song.coverArt, coverUrl: song.coverUrl, size: 130, radius: 12, requestSize: 360),
              Positioned(right: 4, bottom: 4, child: Icon(Icons.play_circle_fill_rounded, size: 28, color: Colors.white.withOpacity(0.9))),
            ]),
            const SizedBox(height: 6),
            Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
            Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
