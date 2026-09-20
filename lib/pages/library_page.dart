import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../widgets.dart';
import 'album_page.dart';
import 'mini_player.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.settings, required this.controller});

  final AppSettings settings;
  final PlayerController controller;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late Future<List<Album>> _albums;

  SubsonicClient get _client => widget.controller.client;

  @override
  void initState() {
    super.initState();
    _albums = _client.newestAlbums();
  }

  void _reload() => setState(() => _albums = _client.newestAlbums());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('专辑'),
        actions: [
          IconButton(
            tooltip: '退出登录',
            icon: const Icon(Icons.logout),
            onPressed: widget.settings.clearLogin,
          ),
        ],
      ),
      body: FutureBuilder<List<Album>>(
        future: _albums,
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
                  FilledButton(onPressed: _reload, child: const Text('重试')),
                ],
              ),
            );
          }
          final albums = snap.data!;
          if (albums.isEmpty) {
            return const Center(child: Text('服务器上还没有专辑'));
          }
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
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AlbumPage(
                    settings: widget.settings,
                    controller: widget.controller,
                    album: a,
                  ),
                )),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: CoverImage(
                          client: _client,
                          coverId: a.coverArt,
                          requestSize: 360,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall),
                    Text(a.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar:
          MiniPlayer(settings: widget.settings, controller: widget.controller),
    );
  }
}
