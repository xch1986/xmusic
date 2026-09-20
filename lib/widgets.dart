import 'package:flutter/material.dart';

import 'subsonic.dart';

/// Cover art loaded from the server, with a neutral placeholder.
/// Colors come from the current theme only — nothing is extracted from the art.
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.client,
    required this.coverId,
    this.size,
    this.radius = 12,
    this.requestSize = 600,
  });

  final SubsonicClient client;
  final String? coverId;
  final double? size;
  final double radius;
  final int requestSize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = client.coverUrl(coverId, size: requestSize);

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
            : Image.network(
                url.toString(),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : placeholder,
              ),
      ),
    );
  }
}

String formatDuration(Duration d) {
  final m = d.inMinutes.remainder(100).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
