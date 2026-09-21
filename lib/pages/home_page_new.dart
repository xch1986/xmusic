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
  late Future<Map<String, List<Song>>> _lists;

  SubsonicClient get _client => widget.controller.client;

  // 榜单/歌单定义
  static const _playlists = [
    {'name': '每日推荐', 'keyword': '华语流行 热门', 'count': 30, 'color': Color(0xFFE85D4A)},
    {'name': '热歌榜', 'keyword': '热歌榜 华语流行', 'count': 20, 'color': Color(0xFFF08A3E)},
    {'name': '新歌榜', 'keyword': '新歌榜 华语', 'count': 20, 'color': Color(0xFF4A9BE8)},
    {'name': '经典老歌', 'keyword': '经典老歌 华语', 'count': 20, 'color': Color(0xFF8B7EC8)},
    {'name': '欧美流行', 'keyword': '欧美流行 热门', 'count': 20, 'color': Color(0xFFE84A7A)},
    {'name': '清新民谣', 'keyword': '民谣 清新', 'count': 20, 'color': Color(0xFF4AC89B)},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final ext = widget.controller.external;
    _lists = Future.wait(
      _playlists.map((p) => ext
          .search(p['keyword'] as String, source: 'netease', limit: p['count'] as int)
          .timeout(const Duration(seconds: 30))
          .catchError((_) => <Song>[]))
    ).then((results) => Map.fromIterables(
          _playlists.map((p) => p['name'] as String),
          results,
        ));
  }

  void _reload() => setState(_load);

  Future<void> _playSongs(List<Song> songs, int index) async {
    await widget.controller.playQueue(songs, index);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(settings: widget.settings, controller: widget.controller),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _openPlaylist(String name, List<Song> songs) async {
    if (songs.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PlaylistDetail(
        title: name,
        songs: songs,
        client: _client,
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
        child: FutureBuilder<Map<String, List<Song>>>(
          future: _lists,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final lists = snap.data ?? {};
            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                // 每日推荐大卡片
                if (lists['每日推荐']?.isNotEmpty == true)
                  _dailyCard(lists['每日推荐']!),
                // 榜单网格
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('推荐榜单',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.3,
                  children: _playlists.where((p) => p['name'] != '每日推荐').map((p) {
                    final name = p['name'] as String;
                    final songs = lists[name] ?? [];
                    return _playlistCard(
                      name,
                      p['color'] as Color,
                      songs,
                    );
                  }).toList(),
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
                    future: _client.randomSongs(size: 20),
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
            );
          },
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
          onTap: () => _openPlaylist('每日推荐', songs),
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
                  child: const Icon(Icons.today_rounded, color: Colors.white, size: 36),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('每日推荐', style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('${songs.length}首精选歌曲', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70)),
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

  Widget _playlistCard(String name, Color color, List<Song> songs) {
    final theme = Theme.of(context);
    return Material(
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openPlaylist(name, songs),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: color.withOpacity(0.15),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.queue_music_rounded, color: Colors.white, size: 24),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  Text('${songs.length}首', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
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
  });

  final String title;
  final List<Song> songs;
  final SubsonicClient client;
  final void Function(int index) onPlay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
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
