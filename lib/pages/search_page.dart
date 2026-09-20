import 'dart:async';

import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../widgets.dart';
import 'album_page.dart';
import 'artist_page.dart';
import 'player_page.dart';

/// Search page: songs / albums / artists via Subsonic search3.
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
  bool _loading = false;
  String? _error;

  SubsonicClient get _client => widget.controller.client;

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
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search());
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
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
                  _error = null;
                });
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : r == null
                  ? Center(
                      child: Text('输入关键词搜索',
                          style: TextStyle(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant)),
                    )
                  : ListView(
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
                                title: Text(a.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(a.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () =>
                                    Navigator.of(context).push(MaterialPageRoute(
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
                                title: Text(ar.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () =>
                                    Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => ArtistPage(
                                    settings: widget.settings,
                                    controller: widget.controller,
                                    artist: ar,
                                  ),
                                )),
                              )),
                        ],
                        if (r.songs.isEmpty &&
                            r.albums.isEmpty &&
                            r.artists.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: Text('未找到相关内容')),
                          ),
                      ],
                    ),
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
