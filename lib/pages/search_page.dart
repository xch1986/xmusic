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
    setState(() {
      _externalLoading = true;
      _error = null;
    });
    final api = _externalApi;
    // 聚合全部可用源：网易云直连 / B站(经聚合或官方) / QQ / 酷我 / 聚合API。
    // 每个源独立 try，单个失败不影响其它源。
    final futures = <Future<List<Song>>>[
      api.searchNeteaseDirect(q),
      if (api.isConfigured) ...[
        api.search(q),
        api.search(q, source: 'bilibili'),
      ],
      api.searchQq(q),
      api.searchKuwo(q),
    ];
    final lists = await Future.wait(
        futures.map((f) => f.catchError((_) => const <Song>[])));
    if (!mounted) return;
    // 合并去重：同歌名+歌手只保留一条（源优先：聚合 > 网易云 > B站 > QQ）
    final seen = <String>{};
    final merged = <Song>[];
    for (final list in lists) {
      for (final s in list) {
        final key = '${s.title}|${s.artist}'.toLowerCase();
        if (seen.add(key)) merged.add(s);
      }
    }
    setState(() {
      _external = merged;
      _externalLoading = false;
    });
  }

  Future<void> _playSongs(List<Song> songs, int index) async {
    await widget.controller.playQueue(songs, index);
    if (widget.controller.lastError != null) {
      _showSnack('播放失败: ${widget.controller.lastError}');
    }
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
    // Clone the list so we can fill in stream URLs without mutating UI state.
    final copy = List<Song>.of(songs);
    final song = copy[index];
    final src = song.externalSource ?? 'netease';
    if (song.streamUrl == null) {
      try {
        final url = switch (src) {
          'qq' => await api.qqStreamUrl(song.id),
          'kuwo' => await api.kuwoStreamUrl(song.id),
          'bilibili' => await api.biliStreamUrl(song.id),
          _ => await api.streamUrlFor(song.id, source: src),
        };
        if (url == null || url.isEmpty) {
          _showSnack(switch (src) {
            'qq' => 'QQ音乐暂时无法获取播放地址（受版权/VIP限制）',
            'kuwo' => '酷我暂时无法获取播放地址',
            _ => '无法获取播放地址（可能需 VIP 或已下架）',
          });
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
          externalSource: src,
          streamUrl: url,
        );
      } catch (e) {
        _showSnack('获取播放地址失败：$e');
        return;
      }
    }
    await _playSongs(copy, index);
  }

  void _showSongMenu(BuildContext context, Song s) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.playlist_add), title: const Text('添加到播放列表'), onTap: () => Navigator.of(ctx).pop('enqueue')),
          ListTile(leading: const Icon(Icons.queue_music), title: const Text('添加到歌单'), onTap: () => Navigator.of(ctx).pop('playlist')),
          ListTile(leading: const Icon(Icons.download), title: const Text('下载到手机'), onTap: () => Navigator.of(ctx).pop('local')),
          ListTile(leading: const Icon(Icons.cloud_upload_outlined), title: const Text('上传到 NAS'), onTap: () => Navigator.of(ctx).pop('nas')),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'enqueue':
        await widget.controller.enqueue(s);
        _showSnack('已加入播放列表');
        break;
      case 'playlist':
        await _addToPlaylist(context, s);
        break;
      case 'local':
        _showSnack('正在下载…');
        _showSnack(await widget.controller.downloadSongToLocal(s));
        break;
      case 'nas':
        _showSnack('正在上传…');
        _showSnack(await widget.controller.uploadSongToNas(s));
        break;
    }
  }

  Future<void> _addToPlaylist(BuildContext context, Song s) async {
    try {
      final pls = await _client.playlists();
      if (!mounted) return;
      if (pls.isEmpty) { _showSnack('没有歌单'); return; }
      if (!mounted) return;
      final chosen = await showDialog<Playlist>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('选择歌单'),
          children: [
            for (final p in pls)
              SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop(p), child: Text(p.name)),
          ],
        ),
      );
      if (chosen == null) return;
      await _client.addToPlaylist(chosen.id, s.id);
      _showSnack('已添加到 ${chosen.name}');
    } catch (e) {
      _showSnack('添加失败: $e');
    }
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
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 96,
      ),
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
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 96,
      ),
      children: songs.asMap().entries.map((e) {
        final s = e.value;
        return ListTile(
          leading: CoverImage(client: _client, coverId: s.coverArt, coverUrl: s.coverUrl, size: 48, radius: 8, requestSize: 200),
          title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${s.artist}  ·  ${_srcLabel(s.externalSource)}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(icon: const Icon(Icons.playlist_add), tooltip: '加入列表', iconSize: 20, onPressed: () async { await widget.controller.enqueue(s); _showSnack('已加入播放列表'); }),
              IconButton(icon: const Icon(Icons.download), tooltip: '下载到手机', iconSize: 20, onPressed: () async { _showSnack('正在下载…'); _showSnack(await widget.controller.downloadSongToLocal(s)); }),
              IconButton(icon: const Icon(Icons.cloud_upload_outlined), tooltip: '上传到NAS', iconSize: 20, onPressed: () async { _showSnack('正在上传…'); _showSnack(await widget.controller.uploadSongToNas(s)); }),
            ],
          ),
          onTap: () => _playExternal(songs, e.key),
        );
      }).toList(),
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

  String _srcLabel(String? src) => switch (src) {
        'bilibili' => 'B站',
        'qq' => 'QQ',
        'kuwo' => '酷我',
        'netease' => '网易云',
        _ => '外网',
      };
}
