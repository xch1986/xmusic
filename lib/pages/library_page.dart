import 'package:flutter/material.dart';

import '../local_library.dart';
import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../widgets.dart';
import 'album_page.dart';
import 'artist_page.dart';
import 'playlist_page.dart';

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
            Tab(text: '专辑'),
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
          _AlbumTab(client: _client, onOpenAlbum: _openAlbum),
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

// ---------------- 专辑 tab ----------------
class _AlbumTab extends StatefulWidget {
  const _AlbumTab({required this.client, required this.onOpenAlbum});

  final SubsonicClient client;
  final void Function(Album) onOpenAlbum;

  @override
  State<_AlbumTab> createState() => _AlbumTabState();
}

class _AlbumTabState extends State<_AlbumTab> {
  late Future<List<Album>> _future;

  SubsonicClient get _client => widget.client;

  @override
  void initState() {
    super.initState();
    _future = _client.newestAlbums(size: 40);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Album>>(
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
                  onPressed: () =>
                      setState(() => _future = _client.newestAlbums(size: 40)),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }
        final albums = snap.data!;
        if (albums.isEmpty) return const Center(child: Text('暂无专辑'));
        // 专辑栏用列表形式（与歌手/歌单一致）：封面 + 专辑名 + 歌手 + 歌曲数
        return ListView.builder(
          itemCount: albums.length,
          itemBuilder: (context, i) {
            final a = albums[i];
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

  @override
  void initState() {
    super.initState();
    _future = widget.client.artists();
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
              leading: CoverImage(
                client: widget.client,
                coverId: ar.coverArt,
                size: 44,
                radius: 8,
                requestSize: 120,
              ),
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
    // 只播放不跳转：底部全局迷你播放条立即出现
    await widget.controller.playQueue(_songs, i);
    if (mounted) setState(() {});
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
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.audio_file_rounded,
                      color: theme.colorScheme.onSurfaceVariant),
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
