import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'lyrics.dart';
import 'subsonic.dart';

class ExternalApi {
  ExternalApi(this.baseUrl);

  final String baseUrl;
  static const int _bitrate = 320;

  static const Map<String, String> _h163 = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
    'Referer': 'https://music.163.com/',
  };
  static const Map<String, String> _hQq = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
    'Referer': 'https://y.qq.com/',
  };
  static const Map<String, String> _hBili = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
    'Referer': 'https://www.bilibili.com/',
  };

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

  Future<dynamic> _getRaw(Uri uri, Map<String, String> headers,
      {int timeoutSec = 20}) async {
    final res = await http
        .get(uri, headers: headers)
        .timeout(Duration(seconds: timeoutSec));
    if (res.statusCode != 200) throw SubsonicException('HTTP ${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<dynamic> _postRaw(Uri uri, Map<String, String> headers, Object body,
      {int timeoutSec = 20}) async {
    final res = await http
        .post(uri, headers: headers, body: body is String ? body : jsonEncode(body))
        .timeout(Duration(seconds: timeoutSec));
    if (res.statusCode != 200) throw SubsonicException('HTTP ${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  // ==================== GDStudio 聚合 ====================

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
      final res = await http.get(Uri.parse('https://music.163.com/api/toplist'), headers: _h163)
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
      final res = await http.get(Uri.parse('https://music.163.com/api/playlist/detail?id=$playlistId'), headers: _h163)
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

  // ==================== 网易云直连 ====================

  /// 网易云直连搜索（需要 UA + Referer）
  Future<List<Song>> searchNeteaseDirect(String keyword, {int limit = 20}) async {
    final uri = Uri.parse('https://music.163.com/api/search/get').replace(
      queryParameters: {'s': keyword, 'type': '1', 'offset': '0', 'limit': '$limit'},
    );
    try {
      final j = await _getRaw(uri, _h163) as Map<String, dynamic>;
      final result = j['result'] as Map<String, dynamic>?;
      final songs = (result?['songs'] as List?) ?? [];
      return songs.cast<Map<String, dynamic>>().map((t) {
        final artists = (t['artists'] as List?) ?? [];
        final artistName = artists
            .map((a) => (a as Map)['name']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .join(' / ');
        final album = t['album'] as Map<String, dynamic>?;
        return Song(
          id: t['id'].toString(),
          title: (t['name'] ?? '').toString(),
          artist: artistName.isEmpty ? '未知' : artistName,
          album: (album?['name'] ?? '').toString(),
          coverArt: null,
          coverUrl: (album?['picUrl'] ?? t['picUrl'])?.toString(),
          durationSec: (t['duration'] as num?) != null
              ? ((t['duration'] as num) / 1000).round()
              : null,
          fromExternal: true,
          externalSource: 'netease',
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  // ==================== QQ音乐直连 ====================

  /// QQ音乐搜索（返回 songmid 作为 id）
  Future<List<Song>> searchQq(String keyword, {int limit = 20}) async {
    final uri = Uri.parse('https://c.y.qq.com/soso/fcgi-bin/client_search_cp')
        .replace(queryParameters: {
      'format': 'json', 'p': '1', 'n': '$limit', 'w': keyword,
      'cr': '1', 'g_tk': '5381', 'loginUin': '0', 'hostUin': '0',
      'inCharset': 'utf8', 'outCharset': 'utf-8', 'notice': '0',
      'platform': 'yqq.json', 'needNewCode': '0',
    });
    try {
      final j = await _getRaw(uri, _hQq) as Map<String, dynamic>;
      final song = (j['data']?['song'] as Map<String, dynamic>?)?['list'];
      final list = (song as List?) ?? [];
      return list.cast<Map<String, dynamic>>().map((t) {
        final singers = (t['singer'] as List?) ?? [];
        final singerName = singers
            .map((s) => (s as Map)['name']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .join(' / ');
        final albumMid = (t['albummid'] ?? '').toString();
        return Song(
          id: (t['songmid'] ?? '').toString(),
          title: (t['songname'] ?? '').toString(),
          artist: singerName.isEmpty ? '未知' : singerName,
          album: (t['albumname'] ?? '').toString(),
          coverArt: null,
          coverUrl: albumMid.isEmpty
              ? null
              : 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albumMid.jpg',
          durationSec: (t['interval'] as num?)?.toInt(),
          fromExternal: true,
          externalSource: 'qq',
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// QQ音乐播放地址（vkey）。2026年起匿名接口普遍返回空，返回 null 表示受限。
  Future<String?> qqStreamUrl(String songmid) async {
    if (songmid.isEmpty) return null;
    final guid = (1000000000 + Random().nextInt(8999999999)).toString();
    final body = {
      'req_0': {
        'module': 'vkey.GetVkeyServer',
        'method': 'CgiGetVkey',
        'param': {
          'guid': guid,
          'songmid': [songmid],
          'songtype': [0],
          'uin': '0',
          'loginflag': 1,
          'platform': '20',
        },
      },
      'comm': {'uin': 0, 'format': 'json', 'ct': 24, 'cv': 0},
    };
    try {
      final j = await _postRaw(
        Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
        {..._hQq, 'Content-Type': 'application/json'},
        body,
      ) as Map<String, dynamic>;
      final data = j['req_0']?['data'] as Map<String, dynamic>?;
      final purl = (data?['midurlinfo'] as List?)
              ?.cast<Map<String, dynamic>>()
              .firstOrNull?['purl']
              ?.toString() ??
          '';
      if (purl.isEmpty) return null;
      final sip = (data?['sip'] as List?)?.cast<String>() ?? const [];
      final host = sip.isNotEmpty ? sip.first : 'https://ws.stream.qqmusic.qq.com';
      return '$host$purl';
    } catch (_) {
      return null;
    }
  }

  /// QQ音乐歌词（直连）
  Future<Lyrics?> qqLyric(String songmid) async {
    if (songmid.isEmpty) return null;
    final uri = Uri.parse('https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg')
        .replace(queryParameters: {
      'songmid': songmid, 'format': 'json', 'nobase64': '1',
    });
    try {
      final j = await _getRaw(uri, _hQq) as Map<String, dynamic>;
      final raw = j['lyric']?.toString() ?? '';
      if (raw.trim().isEmpty) return null;
      return Lyrics.fromLrc(raw);
    } catch (_) {
      return null;
    }
  }

  // ==================== B站直连 ====================

  /// B站视频音轨直连：view 拿 cid → playurl 拿音频流（选最高码率）。
  /// 兼容 bvid（BV 开头）与 aid（纯数字）两种 id。
  Future<String?> biliStreamUrl(String bvidOrAid) async {
    final id = bvidOrAid.trim();
    if (id.isEmpty) return null;
    final isBv = RegExp(r'^[Bb][Vv][0-9A-Za-z]+$').hasMatch(id);
    final videoParam = isBv ? 'bvid=$id' : 'aid=$id';
    try {
      final view = await _getRaw(
        Uri.parse('https://api.bilibili.com/x/web-interface/view?$videoParam'),
        _hBili,
      ) as Map<String, dynamic>;
      final data = view['data'] as Map<String, dynamic>?;
      final cid = data?['cid']?.toString();
      if (cid == null || cid.isEmpty) return null;
      final play = await _getRaw(
        Uri.parse(
            'https://api.bilibili.com/x/player/playurl?$videoParam&cid=$cid&fnval=16&fourk=1'),
        _hBili,
      ) as Map<String, dynamic>;
      final pd = play['data'] as Map<String, dynamic>?;
      final dash = pd?['dash'] as Map<String, dynamic>?;
      final audio = (dash?['audio'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      if (audio.isNotEmpty) {
        audio.sort((a, b) =>
            ((b['bandwidth'] as num?)?.toInt() ?? 0) -
            ((a['bandwidth'] as num?)?.toInt() ?? 0));
        final url = audio.first['baseUrl']?.toString() ?? '';
        if (url.isNotEmpty) return url;
      }
      final durl = (pd?['durl'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      if (durl.isNotEmpty) {
        final url = durl.first['url']?.toString() ?? '';
        if (url.isNotEmpty) return url;
      }
    } catch (_) {}
    return null;
  }

  /// 播放/下载 B站音轨时需要带 UA + Referer（部分 CDN 拒绝裸请求）。
  static const Map<String, String> biliPlayHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
    'Referer': 'https://www.bilibili.com/',
  };
}
