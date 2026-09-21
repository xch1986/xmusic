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
  late Future<List<Song>> _hot;
  late Future<List<Song>> _newMusic;
  late Future<List<Song>> _localRec;

  SubsonicClient get _client => widget.controller.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final ext = widget.controller.external;
    _hot = ext.search('热歌榜 华语流行', source: 'netease', limit: 24)
        .timeout(const Duration(seconds: 30)).catchError((_) => <Song>[]);
    _newMusic = ext.search('经典老歌 华语', source: 'netease', limit: 24)
        .timeout(const Duration(seconds: 30)).catchError((_) => <Song>[]);
    _localRec = _client.randomSongs(size: 20);
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
        child: FutureBuilder(
          future: Future.wait([_hot, _newMusic, _localRec]),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snap.data as List;
            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _section('网易云热歌', data[0] as List<Song>),
                _section('经典华语', data[1] as List<Song>),
                _section('本地推荐', data[2] as List<Song>),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _section(String title, List<Song> songs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          actionLabel: songs.isEmpty ? null : '播放全部',
          onAction: songs.isEmpty ? null : () => _playSongs(songs, 0),
        ),
        if (songs.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('加载中...'))
        else
          SizedBox(
            height: 190,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: songs.length > 12 ? 12 : songs.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _Card(song: songs[i], client: _client, onTap: () => _playSongs(songs, i)),
              ),
            ),
          ),
      ],
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
