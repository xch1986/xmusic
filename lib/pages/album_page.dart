import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../widgets.dart';
import 'mini_player.dart';
import 'player_page.dart';

class AlbumPage extends StatelessWidget {
  const AlbumPage({
    super.key,
    required this.settings,
    required this.controller,
    required this.album,
  });

  final AppSettings settings;
  final PlayerController controller;
  final Album album;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(album.name)),
      body: FutureBuilder<List<Song>>(
        future: controller.client.albumSongs(album.id),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('加载失败：${snap.error}'));
          }
          final songs = snap.data!;
          return ListView.builder(
            itemCount: songs.length,
            itemBuilder: (context, i) {
              final s = songs[i];
              return ListTile(
                leading: Text('${i + 1}',
                    style: Theme.of(context).textTheme.bodyMedium),
                title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle:
                    Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: s.durationSec == null
                    ? null
                    : Text(formatDuration(Duration(seconds: s.durationSec!))),
                onTap: () {
                  controller.playQueue(songs, i);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        PlayerPage(settings: settings, controller: controller),
                  ));
                },
              );
            },
          );
        },
      ),
      bottomNavigationBar: MiniPlayer(settings: settings, controller: controller),
    );
  }
}
