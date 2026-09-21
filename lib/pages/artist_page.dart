import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../widgets.dart';
import 'album_page.dart';

/// Artist page: albums of a single artist.
class ArtistPage extends StatefulWidget {
  const ArtistPage({
    super.key,
    required this.settings,
    required this.controller,
    required this.artist,
  });

  final AppSettings settings;
  final PlayerController controller;
  final Artist artist;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  late Future<List<Album>> _future;

  SubsonicClient get _client => widget.controller.client;

  @override
  void initState() {
    super.initState();
    _future = _client.artistAlbums(widget.artist.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: Text(widget.artist.name)),
      body: FutureBuilder<List<Album>>(
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
                    onPressed: () => setState(() =>
                        _future = _client.artistAlbums(widget.artist.id)),
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
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AlbumPage(
                    settings: widget.settings,
                    controller: widget.controller,
                    album: a,
                  ),
                )),
              );
            },
          );
        },
      ),
    );
  }
}