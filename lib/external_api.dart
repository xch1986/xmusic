import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lyrics.dart';
import 'subsonic.dart';

/// External music search client for the gdstudio music-api (API.php) style:
///   GET {base}/api.php?types=search&source=netease&name=<kw>&count=<n>&pages=<p>
///     -> [ {id, name, artist:[...], album, pic_id, url_id, lyric_id, source}, ... ]
///   GET {base}/api.php?types=url&source=netease&id=<trackId>&br=320
///     -> {url, br, size}
///   GET {base}/api.php?types=pic&source=netease&id=<picId>&size=500
///     -> {url}
///
/// Configure the base URL in 设置 -> 外部搜索 API, e.g.
///   https://music-api.gdstudio.xyz
class ExternalApi {
  ExternalApi(this.baseUrl);

  final String baseUrl;

  static const String _source = 'qq';
  static const int _bitrate = 320;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  String get _root => baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Future<dynamic> _getJson(String types, Map<String, String> params) async {
    final uri = Uri.parse('$_root/api.php').replace(queryParameters: {
      'types': types,
      'source': _source,
      ...params,
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw SubsonicException('HTTP ${res.statusCode}');
    }
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<List<Song>> search(String keyword, {int limit = 20}) async {
    final raw = await _getJson('search', {
      'name': keyword,
      'count': '$limit',
      'pages': '1',
    });
    if (raw is! List) return const [];
    final items = raw.cast<Map<String, dynamic>>();

    // Resolve cover URLs in parallel (each needs a /pic call).
    final coverFutures = items.map((it) async {
      final picId = it['pic_id']?.toString();
      if (picId == null || picId.isEmpty) return null;
      try {
        final r = await _getJson('pic', {'id': picId, 'size': '500'});
        if (r is Map && r['url'] != null) return r['url'].toString();
      } catch (_) {}
      return null;
    });
    final covers = await Future.wait(coverFutures);

    final out = <Song>[];
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final id = it['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final artists = (it['artist'] as List?) ?? const [];
      final artistName = artists.map((a) => a.toString()).join(' / ');
      out.add(Song(
        id: id,
        title: (it['name'] ?? '').toString(),
        artist: artistName.isEmpty ? '未知歌手' : artistName,
        album: (it['album'] ?? '').toString(),
        coverArt: null,
        coverUrl: covers[i],
        durationSec: null,
        fromExternal: true,
      ));
    }
    return out;
  }

  /// Resolve the playable stream URL for an external track id.
  Future<String?> streamUrlFor(String trackId) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final r = await _getJson('url', {'id': trackId, 'br': '$_bitrate'});
        if (r is Map && r['url'] != null) {
          final url = r['url'].toString();
          if (url.isNotEmpty) return url;
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return null;
  }

  /// Fetch synced lyrics for an external track id (LRC text from the API).
  Future<Lyrics?> lyricFor(String trackId) async {
    try {
      final r = await _getJson('lyric', {'id': trackId});
      if (r is Map && r['lyric'] != null) {
        final raw = r['lyric'].toString();
        if (raw.trim().isNotEmpty) return Lyrics.fromLrc(raw);
      }
    } catch (_) {}
    return null;
  }
}
