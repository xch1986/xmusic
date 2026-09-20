import 'dart:async';

import 'package:flutter/material.dart';

import '../external_api.dart';
import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../widgets.dart';
import 'album_page.dart';
import 'artist_page.dart';
import 'player_page.dart';

/// Search page: 本地 (Subsonic search3) / 外网 (self-hosted music API).
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.settings, required this.controller});

  final AppSettings settings;
  final PlayerController controller;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _query = TextEditingController();
  Timer? _debounce;
  SearchResults? _results;
  List<Song>? _external;
  bool _externalLoading = false;
  bool _loading = false;
  String? _error;
  int _mode = 0; // 0 = 本地, 1 = 外网

  SubsonicClient get _client => widget.controller.client;
  ExternalApi get _externalApi => ExternalApi(widget.settings.externalApiUrl);

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = null;
        _external = null;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search());
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    if (_mode == 0) {
      await _searchLocal(q);
    } else {
      await _searchExternal(q);
    }
  }

  Future<void> _searchLocal(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _client.search(q);
      if (!mounted) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '搜索失败：$e';
      });
    }
  }

  Future<void> _searchExternal(String q) async {
    if (!_externalApi.isConfigured) {
      setState(() {
        _external = null;
        _error = '未配置外部搜索 API，请到 设置 -> 外部搜索 API 填写地址';
      });
      return;
    }
    setState(() {
      _externalLoading = true;
      _error = null;
    });
    try {
      final songs = await _externalApi.search(q);
      if (!mounted) return;
      setState(() {
        _external = songs;
        _externalLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _externalLoading = false;
        _error = '外网搜索失败：$e';
      });
    }
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

  /// Play an external song: resolve the stream URL first if needed.
  Future<void> _playExternal(List<Song> songs, int index) async {
    final api = _externalApi;
    if (!api.isConfigured) {
      _showSnack('未配置外部搜索 API');
      return;
    }
    // Clone the list so we can fill in stream URLs without mutating UI state.
    final copy = List<Song>.of(songs);
    final song = copy[index];
    if (song.streamUrl == null) {
      try {
        final url = await api.streamUrlFor(song.id);
        if (url == null) {
          _showSnack('无法获取播放地址（可能需 VIP 或已下架）');
          return;
        }
        copy[index] = Song(
          id: song.id,
          title: song.title,
          artist: song.artist,
          album: song.album,
          coverArt: null,
          coverUrl: song.coverUrl,
          durationSec: song.durationSec,
          fromExternal: true,
          streamUrl: url,
        );
      } catch (e) {
        _showSnack('获取播放地址失败：$e');
        return;
      }
    }
    await _playSongs(copy, index);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final r = _results;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            hintText: '搜索歌曲 / 专辑 / 歌手',
            border: InputBorder.none,
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
        ),
        actions: [
          if (_query.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _query.clear();
                setState(() {
                  _results = null;
                  _external = null;
                  _error = null;
                });
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('本地'),
                  icon: Icon(Icons.dns_outlined),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('外网'),
                  icon: Icon(Icons.public_rounded),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) {
                setState(() => _mode = s.first);
                _search();
              },
            ),
          ),
        ),
      ),
      body: _mode == 0 ? _localBody(context, r) : _externalBody(),
    );
  }

  Widget _localBody(BuildContext context, SearchResults? r) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (r == null) {
      return Center(
        child: Text('输入关键词搜索',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return ListView(
      children: [
        if (r.songs.isNotEmpty) ...[
          _header('歌曲'),
          ...r.songs.asMap().entries.map((e) => SongTile(
                song: e.value,
                client: _client,
                onTap: () => _playSongs(r.songs, e.key),
              )),
        ],
        if (r.albums.isNotEmpty) ...[
          _header('专辑'),
          ...r.albums.map((a) => ListTile(
                leading: CoverImage(
                  client: _client,
                  coverId: a.coverArt,
                  size: 44,
                  radius: 8,
                  requestSize: 120,
                ),
                title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(a.artist,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AlbumPage(
                    settings: widget.settings,
                    controller: widget.controller,
                    album: a,
                  ),
                )),
              )),
        ],
        if (r.artists.isNotEmpty) ...[
          _header('歌手'),
          ...r.artists.map((ar) => ListTile(
                leading: CoverImage(
                  client: _client,
                  coverId: ar.coverArt,
                  size: 44,
                  radius: 8,
                  requestSize: 120,
                ),
                title: Text(ar.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ArtistPage(
                    settings: widget.settings,
                    controller: widget.controller,
                    artist: ar,
                  ),
                )),
              )),
        ],
        if (r.songs.isEmpty && r.albums.isEmpty && r.artists.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('未找到相关内容')),
          ),
      ],
    );
  }

  Widget _externalBody() {
    if (_externalLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(_error!, textAlign: TextAlign.center)),
      );
    }
    final songs = _external;
    if (songs == null) {
      return Center(
        child: Text('搜索外网歌曲',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    if (songs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('未找到相关歌曲')),
      );
    }
    return ListView(
      children: songs.asMap().entries.map((e) => SongTile(
            song: e.value,
            client: _client,
            onTap: () => _playExternal(songs, e.key),
          )),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      );
}
