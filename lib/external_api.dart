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
    final res = await http.get(uri).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw SubsonicException('HTTP ${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<List<Song>> search(String keyword,
      {String source = 'netease', int limit = 20, int? count}) async {
    // count 为 limit 的别名：首页 B站热门用 count: 15，搜索页用 limit:
    limit = count ?? limit;
    final raw = await _getJson('search', source, {
      'name': keyword, 'count': '$limit', 'pages': '1',
    });
    if (raw is! List) return const [];
    final items = raw.cast<Map<String, dynamic>>();

    final coverFutures = items.map((it) async {
      final picId = it['pic_id']?.toString();
      if (picId == null || picId.isEmpty) return null;
      // bilibili的pic_id本身就是URL
      if (picId.startsWith('//')) return 'https:$picId';
      if (picId.startsWith('http')) return picId;
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

  Future<String?> streamUrlFor(String trackId, {String source = 'netease'}) async {
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

  Future<Lyrics?> lyricFor(String trackId, {String source = 'netease'}) async {
    try {
      final r = await _getJson('lyric', source, {'id': trackId});
      if (r is Map && r['lyric'] != null) {
        final raw = r['lyric'].toString();
        if (raw.trim().isNotEmpty) return Lyrics.fromLrc(raw);
      }
    } catch (_) {}
    return null;
  }

  /// 获取网易云排行榜列表（直连163）
  Future<List<Map<String, dynamic>>> getToplists() async {
    try {
      final res = await http.get(Uri.parse('https://music.163.com/api/toplist'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final list = (j['list'] as List?) ?? [];
      return list.cast<Map<String, dynamic>>().map((m) => {
        'id': m['id'].toString(),
        'name': m['name']?.toString() ?? '',
        'coverImgUrl': m['coverImgUrl']?.toString() ?? '',
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// 获取歌单/排行榜歌曲列表（直连163）
  Future<List<Song>> getPlaylistSongs(String playlistId) async {
    try {
      final res = await http.get(Uri.parse('https://music.163.com/api/playlist/detail?id=$playlistId'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final result = j['result'] as Map<String, dynamic>?;
      final tracks = (result?['tracks'] as List?) ?? [];
      return tracks.cast<Map<String, dynamic>>().map((t) {
        final artists = (t['artists'] as List?) ?? [];
        final artistName = artists.map((a) => (a as Map)['name']?.toString() ?? '').join(' / ');
        return Song(
          id: t['id'].toString(),
          title: t['name']?.toString() ?? '',
          artist: artistName.isEmpty ? '未知' : artistName,
          album: (t['album'] as Map?)?['name']?.toString() ?? '',
          coverArt: null,
          coverUrl: (t['album'] as Map?)?['picUrl']?.toString(),
          durationSec: (t['duration'] as num?) != null ? ((t['duration'] as num) / 1000).round() : null,
          fromExternal: true,
          externalSource: 'netease',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
