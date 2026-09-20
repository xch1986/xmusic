import 'dart:convert';

import 'package:http/http.dart' as http;

import 'subsonic.dart';

/// External (non-Subsonic) music search client.
///
/// Expects a self-hosted NeteaseCloudMusicApi-compatible server:
///   GET {base}/search?keywords=<q>&limit=<n>
///     -> {"result": {"songs": [{"id": 123, "name": "...",
///         "artists": [{"name": "..."}], "album": {"name": "...", "picUrl": "..."}}]}}
///   GET {base}/song/url?id=<id>
///     -> {"data": [{"url": "https://..."}]}
///
/// Configure the base URL in 设置 -> 外部搜索 API.
class ExternalApi {
  ExternalApi(this.baseUrl);

  final String baseUrl;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  Future<List<Song>> search(String keyword, {int limit = 30}) async {
    final uri = Uri.parse('$baseUrl/search').replace(queryParameters: {
      'keywords': keyword,
      'limit': '$limit',
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw SubsonicException('HTTP ${res.statusCode}');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final result = body['result'] as Map<String, dynamic>?;
    final songs = (result?['songs'] as List?) ?? const [];
    final out = <Song>[];
    for (final s in songs.cast<Map<String, dynamic>>()) {
      final id = s['id'];
      if (id == null) continue;
      final artists = (s['artists'] as List?) ?? const [];
      final artistName = artists
          .cast<Map<String, dynamic>>()
          .map((a) => (a['name'] ?? '').toString())
          .where((n) => n.isNotEmpty)
          .join(' / ');
      final album = (s['album'] as Map<String, dynamic>?) ?? const {};
      out.add(Song(
        id: 'ext_$id',
        title: (s['name'] ?? '').toString(),
        artist: artistName.isEmpty ? '未知歌手' : artistName,
        album: (album['name'] ?? '').toString(),
        coverArt: null,
        coverUrl: album['picUrl']?.toString(),
        durationSec: ((s['dt'] as num?)?.toInt() ?? 0) ~/ 1000,
        fromExternal: true,
        // streamUrl is resolved lazily right before playback.
      ));
    }
    return out;
  }

  /// Resolve the playable stream URL for an external song id like "ext_123".
  Future<String?> streamUrlFor(String songId) async {
    final netId = songId.startsWith('ext_') ? songId.substring(4) : songId;
    final uri = Uri.parse('$baseUrl/song/url').replace(queryParameters: {
      'id': netId,
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) return null;
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final data = (body['data'] as List?) ?? const [];
    if (data.isEmpty) return null;
    final url = ((data.first as Map<String, dynamic>)['url'] ?? '').toString();
    return url.isEmpty ? null : url;
  }
}
