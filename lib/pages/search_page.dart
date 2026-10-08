import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../external_api.dart';
import '../local_library.dart';
import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../widgets.dart';
import '../cover_glass.dart';
import 'album_page.dart';
import 'artist_page.dart';
import 'player_page.dart';

/// Search page: 本地(本地下载) / NAS(Subsonic search3) / 在线(外网 self-hosted API).
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
  int _mode = 0; // 0 = 本地(本地下载), 1 = NAS(Subsonic服务器), 2 = 在线(外网)
  List<String> _history = [];

  SubsonicClient? get _client => widget.controller.client;
  ExternalApi get _externalApi => ExternalApi(widget.settings.externalApiUrl);

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  static const _kHistory = 'search_history';

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kHistory) ?? const <String>[];
    if (mounted) setState(() => _history = list);
  }

  Future<void> _recordHistory(String q) async {
    if (q.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kHistory) ?? <String>[];
    list.remove(q);
    list.insert(0, q);
    if (list.length > 20) list.removeRange(20, list.length);
    await prefs.setStringList(_kHistory, list);
    if (mounted) setState(() => _history = List.of(list));
  }

  Future<void> _removeHistory(String q) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kHistory) ?? <String>[];
    list.remove(q);
    await prefs.setStringList(_kHistory, list);
    if (mounted) setState(() => _history = list);
  }

  Widget _historyBody(BuildContext context) {
    if (_history.isEmpty) {
      return Center(
        child: Text('输入关键词搜索',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text('历史搜索',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                tooltip: '清空历史',
                icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove(_kHistory);
                  if (mounted) setState(() => _history = []);
                },
              ),
            ],
          ),
        ),
        ..._history.map((kw) => ListTile(
              dense: true,
              leading: const Icon(Icons.history, size: 20),
              title: Text(kw, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                _query.text = kw;
                _search();
              },
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _removeHistory(kw),
              ),
            )),
      ],
    );
  }

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

  /// 过滤老歌（开关开 + 年份可确认且早于阈值时剔除）。
  List<Song> _filterOld(List<Song> songs) =>
      songs.where((s) => !widget.settings.isOld(s)).toList();

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    _recordHistory(q);
    if (_mode == 0) {
      await _searchLocalDownloads(q);
    } else if (_mode == 1) {
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
    final c = _client;
    if (c == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '未配置 Navidrome，请到 设置-源 中配置服务器';
      });
      return;
    }
    try {
      final r = await c.search(q);
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

  /// 搜索本地下载的歌曲（设备本地已下载内容）：按 标题/歌手/专辑 过滤。
  Future<void> _searchLocalDownloads(String q) async {
    setState(() { _loading = true; _error = null; });
    try {
      final all = await LocalLibrary.load();
      final ql = q.toLowerCase();
      final hits = all.where((s) =>
          s.title.toLowerCase().contains(ql) ||
          s.artist.toLowerCase().contains(ql) ||
          s.album.toLowerCase().contains(ql)).toList();
      if (!mounted) return;
      setState(() { _results = SearchResults(songs: hits); _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = '搜索失败：$e'; });
    }
  }

  Future<void> _searchExternal(String q) async {
    setState(() {
      _externalLoading = true;
      _error = null;
    });
    final api = _externalApi;
    // 聚合全部可用源：LX(网易云/QQ聚合) / 网易云直连 / 聚合API(gdstudio内置) / QQ / 酷我(KW)。
    // 每个源独立 try，单个失败不影响其它源。
    final futures = <Future<List<Song>>>[
      api.searchNeteaseDirect(q),
      api.lxSearch(q),
      api.search(q),
      api.searchQq(q),
      api.searchKuwo(q),
    ];
    final lists = await Future.wait(
        futures.map((f) => f.catchError((_) => const <Song>[])));
    if (!mounted) return;
    // 合并去重：同歌名+歌手只保留一条（源优先：聚合 > LX > 网易云 > QQ > 酷我）
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
    _backfillCovers(merged);
  }

  /// 在线搜索结果缺封面的条目，用酷我封面接口按「歌名 歌手」补图（最多补 40 条）。
  Future<void> _backfillCovers(List<Song> merged) async {
    final missing =
        merged.where((s) => (s.coverUrl ?? '').isEmpty).take(40).toList();
    if (missing.isEmpty) return;
    final api = _externalApi;
    for (final s in missing) {
      try {
        final url = await api.kugouSearchCover('${s.title} ${s.artist}');
        if (url == null || url.isEmpty || !mounted) continue;
        final list = _external;
        if (list == null) continue;
        final i = list.indexWhere((x) => x.id == s.id);
        if (i < 0) continue;
        setState(() {
          list[i] = Song(
            id: s.id,
            title: s.title,
            artist: s.artist,
            album: s.album,
            coverArt: null,
            coverUrl: url,
            durationSec: s.durationSec,
            fromExternal: s.fromExternal,
            externalSource: s.externalSource,
            streamUrl: s.streamUrl,
            lrcUrl: s.lrcUrl,
            year: s.year,
          );
        });
      } catch (_) {}
    }
  }

  Future<void> _playSongs(List<Song> songs, int index) async {
    await widget.controller.playQueue(songs, index, source: (_query.text.trim().isEmpty ? '搜索' : '搜索 · ' + _query.text.trim()));
    if (widget.controller.lastError != null) {
      _showSnack('播放失败: ${widget.controller.lastError}');
    }
    if (!mounted) return;
    await openPlayerPage(context, settings: widget.settings, controller: widget.controller);
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
          year: song.year,
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
          if (!isCarScreen(context))
            ListTile(leading: const Icon(Icons.download), title: const Text('下载到手机'), onTap: () => Navigator.of(ctx).pop('local')),
          if (!isCarScreen(context))
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
    final c = _client;
    if (c == null) {
      _showSnack('未配置 Navidrome，无法添加歌单');
      return;
    }
    try {
      final pls = await c.playlists();
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
      await c.addToPlaylist(chosen.id, s.id);
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
    return BigScreenText(
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
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
                ),
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
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('本地'),
                  icon: Icon(Icons.folder_rounded),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('NAS'),
                  icon: Icon(Icons.dns_outlined),
                ),
                ButtonSegment(
                  value: 2,
                  label: Text('在线'),
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
          Expanded(
            child: PageBackground(
              controller: widget.controller,
              settings: widget.settings,
              child: _mode <= 1 ? _localBody(context, r) : _externalBody(),
            ),
          ),
        ],
      ),
    ));
  }

  Widget _localBody(BuildContext context, SearchResults? r) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (r == null) {
      return _historyBody(context);
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
                onFavorite: () async {
                  final s = e.value;
                  if (!s.fromExternal) {
                    try {
                      s.starred
                          ? await _client?.unstarSong(s.id)
                          : await _client?.starSong(s.id);
                    } catch (_) {}
                  }
                },
                blacklisted: widget.settings.isBlacklisted(e.value),
                onBlacklist: () async {
                  final s = e.value;
                  if (widget.settings.isBlacklisted(s)) {
                    await widget.settings.removeBlacklist(s);
                  } else {
                    await widget.settings.addBlacklist(s);
                  }
                },
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
      return _historyBody(context);
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
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  // [xmusic] 2026-09-28 不同源不同颜色标注：LX绿/QQ蓝/酷我橙/网易云红/聚合紫
                  color: _srcColor(s.externalSource),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_srcLabel(s.externalSource),
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          isThreeLine: true,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(icon: const Icon(Icons.playlist_add), tooltip: '加入列表', iconSize: 20, onPressed: () async { await widget.controller.enqueue(s); _showSnack('已加入播放列表'); }),
              if (!isCarScreen(context))
                IconButton(icon: const Icon(Icons.download), tooltip: '下载到手机', iconSize: 20, onPressed: () async { _showSnack('正在下载…'); _showSnack(await widget.controller.downloadSongToLocal(s)); }),
              if (!isCarScreen(context))
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
        'lx' => 'LX',
        'qq' => 'QQ',
        'kuwo' => '酷我(KW)',
        'netease' => '网易云',
        _ => '聚合',
      };

  /// 不同源的颜色标注：LX绿 / QQ蓝 / 酷我橙 / 网易云红 / 其它聚合紫。
  Color _srcColor(String? src) => switch (src) {
        'lx' => const Color(0xFF00A884),
        'qq' => const Color(0xFF3A6DF0),
        'kuwo' => const Color(0xFFE68A2E),
        'netease' => const Color(0xFFD94B4B),
        'bilibili' => const Color(0xFFFB7299),
        _ => const Color(0xFF7A6BC4),
      };
}
