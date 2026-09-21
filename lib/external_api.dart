import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lyrics.dart';
import 'subsonic.dart';

class ExternalApi {
  ExternalApi(this.baseUrl);

  final String baseUrl;
  static const int _bitrate = 320;

  bool get isConfigured => baseUrl.trim().isNotEmpty;
  String get _root => baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Future<dynamic> _getJson(String types, String source, Map<String, String> params) async {
    final uri = Uri.parse('$_root/api.php').replace(queryParameters: {
      'types': types,
      'source': source,
      ...params,
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw SubsonicException('HTTP ${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<List<Song>> search(String keyword, {String source = 'qq', int limit = 20}) async {
    final raw = await _getJson('search', source, {
      'name': keyword, 'count': '$limit', 'pages': '1',
    });
    if (raw is! List) return const [];
    final items = raw.cast<Map<String, dynamic>>();

    final coverFutures = items.map((it) async {
      final picId = it['pic_id']?.toString();
      if (picId == null || picId.isEmpty) return null;
      try {
        final r = await _getJson('pic', source, {'id': picId, 'size': '500'});
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
        externalSource: source,
      ));
    }
    return out;
  }

  Future<String?> streamUrlFor(String trackId, {String source = 'qq'}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final r = await _getJson('url', source, {'id': trackId, 'br': '$_bitrate'});
        if (r is Map && r['url'] != null) {
          final url = r['url'].toString();
          if (url.isNotEmpty) return url;
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return null;
  }

  Future<Lyrics?> lyricFor(String trackId, {String source = 'qq'}) async {
    try {
      final r = await _getJson('lyric', source, {'id': trackId});
      if (r is Map && r['lyric'] != null) {
        final raw = r['lyric'].toString();
        if (raw.trim().isNotEmpty) return Lyrics.fromLrc(raw);
      }
    } catch (_) {}
    return null;
  }
}
