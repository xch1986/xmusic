import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'subsonic.dart';

/// Cover art loaded from the server (or a direct URL), with a neutral
/// placeholder. Colors come from the current theme only — nothing is
/// extracted from the art.
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.client,
    required this.coverId,
    this.coverUrl,
    this.size,
    this.radius = 12,
    this.requestSize = 600,
  });

  final SubsonicClient client;
  final String? coverId;
  final String? coverUrl;
  final double? size;
  final double radius;
  final int requestSize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // A direct URL wins over a server cover id (external songs).
    final url = coverUrl?.isNotEmpty == true
        ? Uri.parse(coverUrl!)
        : client.coverUrl(coverId, size: requestSize);

    final placeholder = ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.music_note_rounded, color: cs.onSurfaceVariant),
      ),
    );

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: url == null
            ? placeholder
            : CachedNetworkImage(
                imageUrl: url.toString(),
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 200),
                fadeOutDuration: const Duration(milliseconds: 200),
                httpHeaders: const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://music.163.com/'},
                errorWidget: (_, __, ___) => placeholder,
                placeholder: (_, __) => placeholder,
              ),
      ),
    );
  }
}

/// Album cover card used in grids and horizontal lists.
class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.album,
    required this.client,
    required this.onTap,
    this.width,
  });

  final Album album;
  final SubsonicClient client;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = width ?? 140.0;
    return SizedBox(
      width: w,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverImage(
              client: client,
              coverId: album.coverArt,
              size: w,
              radius: 12,
              requestSize: 360,
            ),
            const SizedBox(height: 6),
            Text(album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall),
            Text(album.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// A tappable song row with cover, title, artist, duration and a play button.
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.client,
    required this.onTap,
    this.trailing,
    this.showAlbum = false,
    this.leading,
  });

  final Song song;
  final SubsonicClient client;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showAlbum;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: leading ??
          CoverImage(
            client: client,
            coverId: song.coverArt,
            coverUrl: song.coverUrl,
            size: 44,
            radius: 8,
            requestSize: 120,
          ),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        showAlbum ? '${song.artist} · ${song.album}' : song.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (song.durationSec != null)
                Text(formatDuration(Duration(seconds: song.durationSec!)),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              Icon(Icons.play_circle_outline,
                  color: theme.colorScheme.primary),
            ],
          ),
      onTap: onTap,
    );
  }
}

/// Section header with an optional action button.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
      child: Row(
        children: [
          Text(title, style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

String formatDuration(Duration d) {
  final m = d.inMinutes.remainder(100).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
