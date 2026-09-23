import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../local_library.dart';
import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../widgets.dart';
import 'album_page.dart';
import 'artist_page.dart';
import 'playlist_page.dart';import 'player_page.dart';


/// Library page with tabs: 歌单 / 专辑 / 歌手 / 本地(真本地扫描).
class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.settings,
    required this.controller,
    this.initialTab = 0,
  });

  final AppSettings settings;
  final PlayerController controller;
  final int initialTab;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  SubsonicClient get _client => widget.controller.client;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this, initialIndex: widget.initialTab);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('音乐库'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: '歌单'),
            Tab(text: '收藏'),
            Tab(text: '歌手'),
            Tab(text: '本地'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _PlaylistTab(
            client: _client,
            settings: widget.settings,
            controller: widget.controller,
          ),
          _FavoriteTab(settings: widget.settings, controller: widget.controller),
          _ArtistTab(
            client: _client,
            settings: widget.settings,
            controller: widget.controller,
          ),
          _LocalTab(
            settings: widget.settings,
            controller: widget.controller,
          ),
        ],
      ),
    );
  }
}

// ---------------- 收藏 tab（服务器星标歌曲） ----------------
class _FavoriteTab extends StatefulWidget {
  const _FavoriteTab({required this.settings, required this.controller});

  final AppSettings settings;
  final PlayerController controller;

  @override
  State<_FavoriteTab> createState() => _FavoriteTabState();
}

class _FavoriteTabState extends State<_FavoriteTab> {
  late Future<List<Song>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.client.starredSongs();
  }

  Future<void> _play(List<Song> songs, int i) async {
    // 点歌即跳转播放页；底部全局迷你播放条仍会出现
    await widget.controller.playQueue(songs, i);
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
    return FutureBuilder<List<Song>>(
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
                Text('加载失败：'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => setState(() =>
                      _future = widget.controller.client.starredSongs()),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }
        final songs = snap.data!;
        if (songs.isEmpty) {
          return const Center(
            child: Text('暂无收藏歌曲\n在播放页点 ♥ 收藏后会显示在这里'),
          );
        }
        return ListView.builder(
          itemCount: songs.length,
          itemBuilder: (context, i) => SongTile(
            song: songs[i],
            client: widget.controller.client,
            onTap: () => _play(songs, i),
          ),
        );
      },
    );
  }
}
// ---------------- 专辑 tab ----------------
class _AlbumTab extends StatefulWidget {
  const _AlbumTab({required this.client, required this.onOpenAlbum});

  final SubsonicClient client;
  final void Function(Album) onOpenAlbum;

  @override
  State<_AlbumTab> createState() => _AlbumTabState();
}

class _AlbumTabState extends State<_AlbumTab> {
  // 分页加载全部专辑：Navidrome getAlbumList2 按名称字母序全量分页，
  // 修复"音乐库专辑没扫描完"（旧实现只取最新40张，超过的看不到）。
  static const int _pageSize = 50;
  final List<Album> _albums = [];
  final ScrollController _scroll = ScrollController();
  bool _initLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _offset = 0;

  SubsonicClient get _client => widget.client;

  @override
  void initState() {
    super.initState();
    _loadFirst();
    _scroll.addListener(() {
      if (_scroll.position.pixels >=
          _scroll.position.maxScrollExtent - 400) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadFirst() async {
    setState(() {
      _initLoading = true;
      _error = null;
    });
    try {
      final page = await _client.albumList(
          type: 'alphabeticalByName', size: _pageSize, offset: 0);
      if (!mounted) return;
      setState(() {
        _albums
          ..clear()
          ..addAll(page);
        _offset = page.length;
        _hasMore = page.length == _pageSize;
        _initLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _initLoading) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _client.albumList(
          type: 'alphabeticalByName', size: _pageSize, offset: _offset);
      if (!mounted) return;
      setState(() {
        _albums.addAll(page);
        _offset += page.length;
        _hasMore = page.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _albums.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('加载失败：$_error'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadFirst, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_albums.isEmpty) return const Center(child: Text('暂无专辑'));
    // 专辑栏用列表形式（与歌手/歌单一致）：封面 + 专辑名 + 歌手 + 歌曲数
    return ListView.builder(
      controller: _scroll,
      itemCount: _albums.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _albums.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
          );
        }
        final a = _albums[i];
        return ListTile(
          leading: CoverImage(
            client: _client,
            coverId: a.coverArt,
            size: 44,
            radius: 8,
            requestSize: 120,
          ),
          title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [a.artist, if (a.songCount != null) '${a.songCount} 首']
                .where((s) => s.isNotEmpty)
                .join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => widget.onOpenAlbum(a),
        );
      },
    );
  }
}

// ---------------- 歌手 tab ----------------
class _ArtistTab extends StatefulWidget {
  const _ArtistTab({
    required this.client,
    required this.settings,
    required this.controller,
  });

  final SubsonicClient client;
  final AppSettings settings;
  final PlayerController controller;

  @override
  State<_ArtistTab> createState() => _ArtistTabState();
}

class _ArtistTabState extends State<_ArtistTab> {
  late Future<List<Artist>> _future;
  // 歌手头像缓存：按歌手名查网易云歌手头像（仅 coverArt 为空时用，懒加载+去重）。
  final Map<String, Future<String?>> _imgCache = {};

  static const _h163 = {
    'User-Agent': 'Mozilla/5.0',
    'Referer': 'https://music.163.com/',
  };

  @override
  void initState() {
    super.initState();
    _future = widget.client.artists();
  }

  /// 按歌手名从网易云查歌手头像 URL（type=100 歌手搜索）。
  /// 拉 5 条候选、校验名字匹配（避免张冠李戴），失败重试一次。
  Future<String?> _artistImage(String name) {
    return _imgCache.putIfAbsent(name, () async {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final uri = Uri.parse('https://music.163.com/api/search/get')
              .replace(queryParameters: {'s': name, 'type': '100', 'offset': '0', 'limit': '5'});
          final res = await http.get(uri, headers: _h163)
              .timeout(const Duration(seconds: 8));
          if (res.statusCode != 200) {
            await Future.delayed(const Duration(milliseconds: 300));
            continue;
          }
          final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
          final artists = ((j['result'] as Map?)?['artists'] as List?) ?? [];
          for (final a in artists.cast<Map>()) {
            final an = (a['name'] ?? '').toString();
            if (an.isEmpty) continue;
            if (an == name || an.contains(name) || name.contains(an)) {
              // 网易云歌手大头像 picUrl（完整 http URL），失败退 img1v1Url
              final raw = (a['picUrl'] ?? a['img1v1Url'] ?? '').toString();
              if (raw.isNotEmpty && raw.startsWith('http')) return raw;
            }
          }
          return null; // 有结果但无匹配：不重试（避免反复请求）
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
      return null;
    });
  }

  /// 歌手头像：服务器 coverArt 优先；没有时按名查网易云头像，再失败显示首字圆标。
  Widget _artistLeading(BuildContext context, Artist ar) {
    final theme = Theme.of(context);
    if (ar.coverArt != null && ar.coverArt!.isNotEmpty) {
      return CoverImage(
        client: widget.client,
        coverId: ar.coverArt,
        size: 44,
        radius: 8,
        requestSize: 120,
      );
    }
    return FutureBuilder<String?>(
      future: _artistImage(ar.name),
      builder: (context, snap) {
        final url = snap.data;
        if (url != null && url.isNotEmpty) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: url,
              width: 44, height: 44,
              fit: BoxFit.cover,
              httpHeaders: _h163,
              errorWidget: (_, __, ___) => _initialCircle(theme, ar.name),
              placeholder: (_, __) => _initialCircle(theme, ar.name),
            ),
          );
        }
        return _initialCircle(theme, ar.name);
      },
    );
  }

  Widget _initialCircle(ThemeData theme, String name) {
    final initial = name.trim().isNotEmpty ? name.trim().substring(0, 1) : '?';
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(initial,
          style: theme.textTheme.titleMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Artist>>(
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
                  onPressed: () => setState(() => _future = widget.client.artists()),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }
        final artists = snap.data!;
        if (artists.isEmpty) return const Center(child: Text('暂无歌手'));
        return ListView.builder(
          itemCount: artists.length,
          itemBuilder: (context, i) {
            final ar = artists[i];
            return ListTile(
              leading: _artistLeading(context, ar),
              title: Text(ar.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: ar.albumCount == null
                  ? null
                  : Text('${ar.albumCount} 张专辑'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ArtistPage(
                  settings: widget.settings,
                  controller: widget.controller,
                  artist: ar,
                ),
              )),
            );
          },
        );
      },
    );
  }
}

// ---------------- 歌单 tab ----------------
class _PlaylistTab extends StatefulWidget {
  const _PlaylistTab({
    required this.client,
    required this.settings,
    required this.controller,
  });

  final SubsonicClient client;
  final AppSettings settings;
  final PlayerController controller;

  @override
  State<_PlaylistTab> createState() => _PlaylistTabState();
}

class _PlaylistTabState extends State<_PlaylistTab> {
  late Future<List<Playlist>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.client.playlists();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Playlist>>(
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
                  onPressed: () => setState(() => _future = widget.client.playlists()),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }
        final playlists = snap.data!;
        if (playlists.isEmpty) return const Center(child: Text('暂无歌单'));
        return ListView.builder(
          itemCount: playlists.length,
          itemBuilder: (context, i) {
            final p = playlists[i];
            return ListTile(
              leading: CoverImage(
                client: widget.client,
                coverId: p.coverArt,
                size: 44,
                radius: 8,
                requestSize: 120,
              ),
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: p.songCount == null ? null : Text('${p.songCount} 首歌曲'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlaylistPage(
                  settings: widget.settings,
                  controller: widget.controller,
                  playlist: p,
                ),
              )),
            );
          },
        );
      },
    );
  }
}

// ---------------- 本地 tab（真本地扫描） ----------------
/// 扫描“设置里配置的本地下载路径”下的音频文件，直接本地播放（file://）。
class _LocalTab extends StatefulWidget {
  const _LocalTab({required this.settings, required this.controller});

  final AppSettings settings;
  final PlayerController controller;

  @override
  State<_LocalTab> createState() => _LocalTabState();
}

class _LocalTabState extends State<_LocalTab> {
  List<Song> _songs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = await LocalLibrary.load();
    if (!mounted) return;
    setState(() {
      _songs = cached;
      _loading = false;
    });
    _backfillCovers(); // 旧缓存/新扫描漏掉的封面：按文件内嵌 ID3 懒补
  }

  /// 对 coverUrl 为空的本地歌曲，从音频文件内嵌 ID3（APIC）提取封面，
  /// 逐个补进列表并回写缓存。提取失败静默跳过（不阻塞列表）。
  Future<void> _backfillCovers() async {
    final need = _songs.where((s) => (s.coverUrl ?? '').isEmpty).toList();
    if (need.isEmpty) return;
    var changed = false;
    for (final s in need) {
      try {
        final p = Uri.tryParse(s.streamUrl ?? '')?.toFilePath();
        if (p == null || p.isEmpty) continue;
        final cover = await LocalLibrary.extractId3Cover(File(p));
        if (cover != null) {
          final i = _songs.indexWhere((x) => x.id == s.id);
          if (i >= 0 && mounted) {
            setState(() {
              _songs[i] = Song(
                id: s.id,
                title: s.title,
                artist: s.artist,
                album: s.album,
                coverArt: null,
                coverUrl: cover,
                durationSec: s.durationSec,
                fromExternal: false,
                streamUrl: s.streamUrl,
              );
            });
            changed = true;
          }
        }
      } catch (_) {}
    }
    if (changed) await LocalLibrary.save(_songs);
  }

  Future<void> _scan() async {
    final path = widget.settings.downloadPath.trim();
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先到 设置 -> 本地下载路径 选择要扫描的目录')),
      );
      return;
    }
    final progress = ValueNotifier<int>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('扫描本地音乐'),
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, n, __) => Row(
            children: [
              const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(width: 16),
              Expanded(child: Text('正在扫描 $path\n已发现 $n 首...')),
            ],
          ),
        ),
      ),
    );
    try {
      final songs = await LocalLibrary.scan(path, onFile: (n) => progress.value = n);
      await LocalLibrary.save(songs);
      if (!mounted) return;
      Navigator.of(context).pop();
      setState(() => _songs = songs);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描完成：共 ${songs.length} 首本地歌曲')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描失败：$e')),
      );
    }
  }

  Future<void> _play(int i) async {
    // 点歌即跳转播放页；底部全局迷你播放条仍会出现
    await widget.controller.playQueue(_songs, i);
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
    final theme = Theme.of(context);
    final path = widget.settings.downloadPath.trim();
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (path.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('尚未设置本地下载路径\n请到 设置 -> 本地下载路径 选择要扫描的目录',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        ),
      );
    }
    if (_songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('目录里还没扫描到歌曲',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.manage_search_rounded),
              label: const Text('扫描本地目录'),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        // 顶部信息 + 重新扫描
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('${_songs.length} 首本地歌曲 · $path',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _scan,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新扫描'),
              ),
            ],
          ),
        ),
        const Divider(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: _songs.length,
            itemBuilder: (context, i) {
              final s = _songs[i];
              return ListTile(
                leading: CoverImage(
                  client: widget.controller.client,
                  coverId: null,
                  coverUrl: s.coverUrl,
                  size: 44,
                  radius: 8,
                ),
                title: Text(s.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${s.artist} · ${s.album}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _play(i),
              );
            },
          ),
        ),
      ],
    );
  }
}
