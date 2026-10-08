import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../local_library.dart';
import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../widgets.dart';
import '../cover_glass.dart';
import 'album_page.dart';
import 'artist_page.dart';
import 'playlist_page.dart';import 'player_page.dart';
import 'mini_player.dart';


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

  SubsonicClient? get _client => widget.controller.client;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this, initialIndex: widget.initialTab);
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
    return BigScreenText(
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.center,
          tabs: const [
            Tab(text: 'NAS歌单'),
            Tab(text: 'ID歌单'),
            Tab(text: '本地'),
            Tab(text: '收藏'),
            Tab(text: '歌手'),
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
          _ImportTab(
            settings: widget.settings,
            controller: widget.controller,
          ),
          _LocalTab(
            settings: widget.settings,
            controller: widget.controller,
          ),
          _FavoriteTab(settings: widget.settings, controller: widget.controller),
          _ArtistTab(
            client: _client,
            settings: widget.settings,
            controller: widget.controller,
          ),
        ],
      ),
    ));
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
    _future = widget.controller.client?.starredSongs() ??
        Future.value(<Song>[]);
  }

  Future<void> _play(List<Song> songs, int i) async {
    // 点歌即跳转播放页；底部全局迷你播放条仍会出现
    await widget.controller.playQueue(songs, i, source: '收藏');
    if (mounted) setState(() {});
    if (context.mounted) {
      await openPlayerPage(context, settings: widget.settings, controller: widget.controller);
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
                      _future = widget.controller.client?.starredSongs() ??
                          Future.value(<Song>[])),
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

  final SubsonicClient? client;
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

  SubsonicClient? get _client => widget.client;

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
    final c = _client;
    if (c == null) {
      if (!mounted) return;
      setState(() {
        _initLoading = false;
        _error = '未配置 Navidrome，请到 设置-源 中配置服务器';
      });
      return;
    }
    try {
      final page = await c.albumList(
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
    final c = _client;
    if (c == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await c.albumList(
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

  final SubsonicClient? client;
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
    _future = widget.client?.artists() ?? Future.value(<Artist>[]);
  }

  /// 按歌手名取歌手头像：优先网易云 type=100 歌手搜索的真实头像（用户要的是"歌手图片"），
  /// 网易云失败/无图时回退酷狗热门歌曲封面；都失败显示首字圆标。
  Future<String?> _artistImage(String name) {
    return _imgCache.putIfAbsent(name, () async {
      try {
        final avatar = await widget.controller.external.neteaseArtistAvatar(name);
        if (avatar != null && avatar.isNotEmpty) return avatar;
      } catch (_) {}
      try {
        return await widget.controller.external.kugouSearchCover(name);
      } catch (_) {
        return null;
      }
    });
  }

  /// 歌手头像：网易云真实头像优先（用户要求"歌手图片"），失败回退酷狗歌曲封面，
  /// 再失败用服务器 coverArt（Navidrome artist 的 coverArt 常是专辑图且可能缺失），
  /// 全失败显示首字圆标。
  Widget _artistLeading(BuildContext context, Artist ar) {
    final theme = Theme.of(context);
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
              // [xmusic] 网易云图需带 Referer 防防盗链；酷狗图床用通用 UA
              httpHeaders: url.contains('music.126.net')
                  ? const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://music.163.com/'}
                  : const {'User-Agent': 'Mozilla/5.0'},
              errorWidget: (_, __, ___) => _initialCircle(theme, ar.name),
              placeholder: (_, __) => _initialCircle(theme, ar.name),
            ),
          );
        }
        // 网易云/酷狗都没图：服务器 coverArt 兜底（可能缺失，显示失败则圆标）
        if (ar.coverArt != null && ar.coverArt!.isNotEmpty) {
          return CoverImage(
            client: widget.client,
            coverId: ar.coverArt,
            size: 44,
            radius: 8,
            requestSize: 120,
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
                  onPressed: () => setState(() => _future =
                      widget.client?.artists() ?? Future.value(<Artist>[])),
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

  final SubsonicClient? client;
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
    _future = widget.client?.playlists() ?? Future.value(<Playlist>[]);
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
                  onPressed: () => setState(() => _future =
                      widget.client?.playlists() ??
                          Future.value(<Playlist>[])),
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
        String? cover = await LocalLibrary.extractId3Cover(File(p));
        if (cover == null) {
          // 内嵌封面缺失（非 mp3 或未内嵌）：按 歌名+歌手 从酷狗搜封面补图
          cover = await widget.controller.external
              .kugouSearchCover('${s.title} ${s.artist}');
        }
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
    await widget.controller.playQueue(_songs, i, source: '本地音乐');
    if (mounted) setState(() {});
    if (context.mounted) {
      await openPlayerPage(context, settings: widget.settings, controller: widget.controller);
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

// ---------------- 导入歌单 tab（QQ 歌单 ID 导入） ----------------
class _ImportTab extends StatefulWidget {
  const _ImportTab({required this.settings, required this.controller});

  final AppSettings settings;
  final PlayerController controller;

  @override
  State<_ImportTab> createState() => _ImportTabState();
}

class _ImportTabState extends State<_ImportTab> {
  bool _busy = false;

  List<Map<String, String>> get _list => widget.settings.importedQqPlaylists;

  @override
  void initState() {
    super.initState();
    // 旧版导入的歌单无 cover：进页面后异步补封面（蓝色图标 → 歌单封面）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _backfillCovers());
  }

  /// 对 cover 为空的 ID 歌单逐个拉封面并回写（失败静默，不阻塞列表）。
  Future<void> _backfillCovers() async {
    final need =
        _list.where((e) => (e['cover'] ?? '').toString().isEmpty).toList();
    if (need.isEmpty) return;
    for (final e in need) {
      if (!mounted) return;
      final cover =
          await widget.controller.external.qqPlaylistCover(e['id']!);
      if (!mounted) return;
      if (cover.isNotEmpty) {
        await widget.settings.updateImportedQqCover(e['id']!, cover: cover);
        if (mounted) setState(() {});
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// 长按 ID 歌单弹出操作菜单：重命名 / 删除。
  Future<void> _showIdPlaylistMenu(Map<String, String> e) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(e['name'] ?? '歌单',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('ID: ${e['id']}', maxLines: 1),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'rename') {
      final name = await _promptRename(e['name'] ?? '歌单');
      if (name != null && name.trim().isNotEmpty) {
        await widget.settings
            .renameImportedQqPlaylist(e['id']!, name.trim());
        if (mounted) setState(() {});
      }
    } else if (action == 'delete') {
      await widget.settings.removeImportedQqPlaylist(e['id']!);
      if (mounted) setState(() {});
    }
  }

  Future<String?> _promptRename(String current) {
    final ctrl = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名歌单'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(labelText: '歌单名称'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('确定')),
        ],
      ),
    );
  }

  /// 从粘贴的链接/纯数字里提取歌单 ID（y.qq.com/n/ryqq_v2/playlist/9683093831）。
  static String _extractId(String raw) {
    final m = RegExp(r'(\d{5,})').firstMatch(raw);
    return m?.group(1) ?? raw.trim();
  }

  Future<void> _showImportDialog() async {
    final ctrl = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入 QQ 歌单'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '歌单 ID 或歌单链接',
            isDense: true,
          ),
          onSubmitted: (_) => Navigator.of(ctx).pop(ctrl.text),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: const Text('导入')),
        ],
      ),
    );
    ctrl.dispose();
    final dissid = _extractId(raw ?? '');
    if (dissid.isEmpty || !mounted) return;
    setState(() => _busy = true);
    final (name, songs, cover) =
        await widget.controller.external.qqPlaylistDetail(dissid);
    if (!mounted) return;
    setState(() => _busy = false);
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入失败：未找到该歌单，请检查 ID')));
      return;
    }
    await widget.settings.addImportedQqPlaylist(
        dissid, name.isEmpty ? '歌单 $dissid' : name,
        cover: cover);
    if (!mounted) return;
    setState(() {});
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ImportedSongsPage(
        name: name.isEmpty ? '歌单 $dissid' : name,
        songs: songs,
        settings: widget.settings,
        controller: widget.controller,
      ),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _open(String id, String name) async {
    setState(() => _busy = true);
    final (_, songs, _) = await widget.controller.external.qqPlaylistDetail(id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('拉取失败：歌单可能已失效')));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ImportedSongsPage(
        name: name,
        songs: songs,
        settings: widget.settings,
        controller: widget.controller,
      ),
    ));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _list.isEmpty
                      ? '输入 QQ 歌单 ID 导入，跟"歌单"一样管理'
                      : '已导入 ${_list.length} 个歌单，点右上"+"导入',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              IconButton.filledTonal(
                tooltip: '导入歌单',
                onPressed: _busy ? null : _showImportDialog,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 8),
        Expanded(
          child: _list.isEmpty
              ? Center(
                  child: Text(
                    '还没有导入歌单\n点右上角"+"，粘贴歌单链接或填歌单 ID\n'
                    '例：y.qq.com/.../9683093831 → 9683093831',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              : ListenableBuilder(
                  listenable: widget.settings,
                  builder: (context, _) => GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  gridDelegate: isCarScreen(context) &&
                          MediaQuery.sizeOf(context).width <
                              MediaQuery.sizeOf(context).height
                      ? const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.86)
                      : SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: isCarScreen(context) ? 176 : 118,
                          mainAxisSpacing: isCarScreen(context) ? 12 : 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: isCarScreen(context) ? 0.7 : 0.72),
                  itemCount: _list.length,
                  itemBuilder: (context, i) {
                    final e = _list[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _open(e['id']!, e['name'] ?? '歌单'),
                      onLongPress: () => _showIdPlaylistMenu(e),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF3A6DF0),
                                      Color(0xFF5B8CFA),
                                    ],
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: (e['cover'] ?? '').toString().isEmpty
                                    ? const Icon(Icons.queue_music_rounded,
                                        color: Colors.white, size: 34)
                                    : Image.network(
                                        (e['cover'] ?? '').toString(),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(
                                            Icons.queue_music_rounded,
                                            color: Colors.white,
                                            size: 34),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(e['name'] ?? '歌单',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  height: 1.25)),
                        ],
                      ),
                    );
                  },
                ),
              ),
        ),
      ],
    );
  }
}

// 导入歌单的歌曲列表页（点歌直接播放）
class _ImportedSongsPage extends StatefulWidget {
  const _ImportedSongsPage({
    required this.name,
    required this.songs,
    required this.settings,
    required this.controller,
  });

  final String name;
  final List<Song> songs;
  final AppSettings settings;
  final PlayerController controller;

  @override
  State<_ImportedSongsPage> createState() => _ImportedSongsPageState();
}

class _ImportedSongsPageState extends State<_ImportedSongsPage> {
  late List<Song> _songs;

  @override
  void initState() {
    super.initState();
    // 跟黑名单同步：导入歌单加载时过滤黑名单歌曲（与其他榜单/歌单一致）
    _songs = widget.songs
        .where((s) => !widget.settings.isBlacklisted(s))
        .toList();
  }

  void _play(int i) {
    widget.controller.playQueue(_songs, i, source: widget.name);
    if (mounted) setState(() {});
    if (context.mounted) {
      openPlayerPage(context,
          settings: widget.settings, controller: widget.controller);
    }
  }

  void _playRandom() {
    final songs = List.of(_songs)..shuffle();
    widget.controller.playQueue(songs, 0, source: widget.name);
    if (mounted) setState(() {});
    if (context.mounted) {
      openPlayerPage(context,
          settings: widget.settings, controller: widget.controller);
    }
  }

  /// 下载整个歌单到 NAS（WebDAV）：逐首上传，对话框显示进度，结束汇总结果。
  Future<void> _downloadAllToNas() async {
    if (!widget.settings.webdavConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('未配置 NAS (WebDAV)，请到 设置-个性化 中配置')));
      return;
    }
    final songs = List.of(_songs);
    if (songs.isEmpty) return;
    var done = 0;
    var ok = 0;
    String? firstErr;
    void Function(void Function())? setDlg;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          setDlg = set;
          return AlertDialog(
            title: const Text('下载到 NAS'),
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 16),
                Text('正在上传 $done/${songs.length}…'),
              ],
            ),
          );
        },
      ),
    );
    for (final s in songs) {
      final r = await widget.controller.uploadSongToNas(s, folder: widget.name);
      done++;
      if (r.startsWith('已上传')) {
        ok++;
      } else {
        firstErr ??= r;
      }
      setDlg?.call(() {});
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // 关闭进度框
    final summary = ok == songs.length
        ? '已上传全部 $ok 首到 NAS'
        : '完成：成功 $ok/${songs.length} 首' +
            (firstErr != null ? '，失败示例：$firstErr' : '');
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(summary)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PageBackground(
        controller: widget.controller,
        settings: widget.settings,
        fallbackCoverUrl: widget.songs.isNotEmpty
            ? (widget.songs.first.coverUrl != null && widget.songs.first.coverUrl!.isNotEmpty
                ? widget.songs.first.coverUrl
                : (widget.songs.first.coverArt != null && widget.songs.first.coverArt!.isNotEmpty
                    ? widget.controller.client?.coverUrl(widget.songs.first.coverArt!, size: 600)?.toString()
                    : null))
            : null,
        child: BigScreenText(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: (Theme.of(context).brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark)
              .copyWith(
                  statusBarColor: widget.settings.coverColorBg
                      ? Colors.transparent
                      : Theme.of(context).colorScheme.surfaceContainer),
          child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent, title: Text(widget.name)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.shuffle_rounded, size: 20),
                    label: const Text('随机'),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10)),
                    onPressed: widget.songs.isEmpty ? null : _playRandom,
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('顺序'),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10)),
                    onPressed: widget.songs.isEmpty ? null : () => _play(0),
                  ),
                  const SizedBox(width: 4),
                  if (!isCarScreen(context))
                    TextButton.icon(
                      icon: const Icon(Icons.cloud_download_rounded, size: 20),
                      label: const Text('全部下载'),
                      style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10)),
                      onPressed: widget.songs.isEmpty ? null : _downloadAllToNas,
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: widget.songs.length,
                itemBuilder: (context, i) {
                  final s = widget.songs[i];
                  return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: s.coverUrl ?? '',
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  httpHeaders: const {'User-Agent': 'Mozilla/5.0'},
                  errorWidget: (_, __, ___) => Icon(Icons.music_note,
                      color: theme.colorScheme.onSurfaceVariant),
                  placeholder: (_, __) => Icon(Icons.music_note,
                      color: theme.colorScheme.onSurfaceVariant),
                ),
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
          MiniPlayer(settings: widget.settings, controller: widget.controller),
          ],
        )),
      )),
    );
  }
}
