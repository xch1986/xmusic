import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../widgets.dart';
import 'album_page.dart';
import 'artist_page.dart';
import 'playlist_page.dart';

/// Library page with tabs: 专辑 / 歌手 / 歌单.
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
    _tab = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
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
            Tab(text: '专辑'),
            Tab(text: '歌手'),
            Tab(text: '歌单'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _AlbumTab(client: _client, onOpenAlbum: _openAlbum),
          _ArtistTab(
            client: _client,
            settings: widget.settings,
            controller: widget.controller,
          ),
          _PlaylistTab(
            client: _client,
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
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.74,
          ),
          itemCount: albums.length,
          itemBuilder: (context, i) {
            final a = albums[i];
            return AlbumCard(
              album: a,
              client: _client,
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
