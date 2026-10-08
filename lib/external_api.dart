import 'dart:convert';
import 'dart:io';
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

  /// 将各源发行时间/年份（毫秒或秒时间戳、或 4 位年份）解析为年份，失败返回 null。
  static int? _yearOf(dynamic v) {
    if (v == null) return null;
    if (v is num) {
      final n = v.toInt();
      if (n > 9999) {
        final ms = n > 100000000000 ? n : n * 1000;
        return DateTime.fromMillisecondsSinceEpoch(ms).year;
      }
      return n;
    }
    final str = v.toString().trim();
    final m = RegExp(r'^\d{4}').firstMatch(str);
    return m == null ? null : int.parse(m.group(0)!);
  }

  bool get isConfigured => baseUrl.trim().isNotEmpty;
  /// 内置默认聚合 API（gdstudio）；「外部API地址」留空时自动使用。
  static const String defaultAggregate = 'https://music-api.gdstudio.xyz';
  String get _root =>
      (baseUrl.trim().isEmpty ? defaultAggregate : baseUrl.trim())
          .replaceAll(RegExp(r'/+$'), '');

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
  /// 忽略证书的 GET（酷狗 mobilecdn 证书链校验失败）。
  Future<dynamic> _insecureGetJson(Uri uri, {int timeoutSec = 12}) async {
    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    try {
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0 Safari/537.36');
      req.headers.set('Referer', 'https://m.kugou.com/');
      final res = await req.close().timeout(Duration(seconds: timeoutSec));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) throw SubsonicException('HTTP ${res.statusCode}');
      return jsonDecode(body);
    } finally {
      client.close();
    }
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
        year: _yearOf(it['publishTime'] ??
            (it['album'] is Map ? (it['album'] as Map)['publishTime'] : null)),
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
          year: _yearOf((t['album'] as Map?)?['publishTime']),
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
          year: _yearOf(t['publishTime'] ?? (t['album'] as Map?)?['publishTime']),
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
          year: _yearOf(t['time'] ?? t['pubtime']),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 从 cookie 提取 uin（支持完整 cookie 头或 uin=o123456; qqmusic_key=...）。
  static String _uinFromCookie(String cookie) {
    final m = RegExp(r'uin=o?(\d+)').firstMatch(cookie);
    return m != null ? 'o${m.group(1)}' : '0';
  }

  /// QQ musicu.fcg 标准调用：GET + format=json&data=<urlencoded json>。
  /// 注意：POST 直传 JSON body 的旧方式 2026 年起返回 code 500001（请求体不被识别），
  /// 必须用 GET 的 data 参数携带请求体。
  Future<dynamic> _qqFcg(Map<String, dynamic> body, {String cookie = ''}) async {
    final uri = Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg')
        .replace(queryParameters: {'format': 'json', 'data': jsonEncode(body)});
    final res = await http
        .get(uri, headers: {..._hQq, if (cookie.isNotEmpty) 'Cookie': cookie})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw SubsonicException('HTTP ' + res.statusCode.toString());
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  /// 验证 QQ Cookie 是否有效：调热歌榜接口，req_0.code==0 且榜单非空即为有效。
  /// 供设置页「验证」按钮使用；无效原因（过期/脱敏/缺字段）由调用方提示。
  Future<bool> qqCookieValid(String cookie) async =>
      (await qqCookieValidDetailed(cookie)).$1;

  /// QQ Cookie 详细验证：返回 (是否有效, 诊断信息)。
  /// 500003=登录态失效/缺凭证；500001=参数错误；code 0 + 非空列表=有效。
  Future<(bool, String)> qqCookieValidDetailed(String cookie) async {
    // 2026 年起 QQ 榜单接口已匿名可用（musicu.fcg 对无凭证一律 500003），
    // Cookie 的实际价值是解锁会员/付费歌曲播放（vkey）。
    // 这里：1) 检查 Cookie 关键登录字段是否齐备；2) 探测榜单接口连通性。
    final hasUin = RegExp(r'uin=[^;\s]+').hasMatch(cookie);
    final hasKey = RegExp(r'qm_keyst=[^;\s]+').hasMatch(cookie) ||
        RegExp(r'qqmusic_key=[^;\s]+').hasMatch(cookie);
    final hasSkey = RegExp(r'skey=[^;\s]+').hasMatch(cookie);
    if (!hasUin || (!hasKey && !hasSkey)) {
      return (false,
          'Cookie 缺登录字段（需要 uin=... 且 qm_keyst=/qqmusic_key= 或 skey=）。\n说明：QQ 榜单已匿名可用，Cookie 仅用于解锁会员歌曲播放，缺失不影响榜单显示。');
    }
    try {
      final songs = await qqToplistCp('4', limit: 1);
      if (songs.isNotEmpty) {
        return (true,
            'Cookie 登录字段完整，QQ 榜单已可用；\n会员/付费歌曲播放若受版权限制会自动切换其他音源。');
      }
    } catch (_) {}
    return (false, 'Cookie 字段齐备，但榜单接口探测失败，请稍后重试。');
  }

  /// QQ音乐播放地址（vkey）。带 cookie（设置里填的 QQ Cookie）可解锁会员/每日推荐；
  /// 匿名 2026 年起普遍返回空，返回 null 表示受限。
  Future<String?> qqStreamUrl(String songmid, {String cookie = ''}) async {
    if (songmid.isEmpty) return null;
    final rawUin = cookie.isEmpty ? '0' : _uinFromCookie(cookie);
    final guid = (1000000000 + Random().nextInt(8999999999)).toString();
    final body = {
      'req_0': {
        'module': 'vkey.GetVkeyServer',
        'method': 'CgiGetVkey',
        'param': {
          'guid': guid,
          'songmid': [songmid],
          'songtype': [0],
          'uin': rawUin,
          'loginflag': 1,
          'platform': '20',
        },
      },
      'comm': {
        'uin': int.tryParse(rawUin.replaceFirst('o', '')) ?? 0,
        'format': 'json', 'ct': 24, 'cv': 0,
      },
    };
    try {
      final j = await _qqFcg(body, cookie: cookie) as Map<String, dynamic>;
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
      final j = await _getRaw(uri, _hQq, timeoutSec: 8) as Map<String, dynamic>;
      final raw = j['lyric']?.toString() ?? '';
      if (raw.trim().isEmpty) return null;
      return Lyrics.fromLrc(raw);
    } catch (_) {
      return null;
    }
  }

  /// QQ 排行榜列表（老接口匿名可用，无需 cookie）。返回 {id, name, coverImgUrl}。
  /// topid: 4=流行指数榜 26=QQ热歌榜 27=新歌榜 62=飙升榜 5=内地 6=香港 3=欧美 16=韩国 17=日本 60=抖音热歌。
  static const List<Map<String, String>> _qqCharts = [
    {'id': '4', 'name': '流行指数榜', 'cover': ''},
    {'id': '27', 'name': '新歌榜', 'cover': ''},
    {'id': '62', 'name': '飙升榜', 'cover': ''},
    {'id': '26', 'name': 'QQ热歌榜', 'cover': ''},
    {'id': '5', 'name': '内地榜', 'cover': ''},
    {'id': '6', 'name': '香港榜', 'cover': ''},
    {'id': '3', 'name': '欧美榜', 'cover': ''},
    {'id': '16', 'name': '韩国榜', 'cover': ''},
    {'id': '17', 'name': '日本榜', 'cover': ''},
    {'id': '60', 'name': '抖音热歌榜', 'cover': ''},
  ];

  Future<List<Map<String, dynamic>>> qqToplists({String cookie = ''}) async {
    // [xmusic] 2026-09-24 拉取真实榜单封面：fcg_v8_toplist_cp.fcg 返回 topinfo.pic（匿名可用），
    // http 转 https 供 CachedNetworkImage 加载（http 会被 Android 明文流量拦截）。
    final out = <Map<String, dynamic>>[];
    for (final c in _qqCharts) {
      var cover = c['cover'] ?? '';
      try {
        final uri = Uri.parse('https://c.y.qq.com/v8/fcg-bin/fcg_v8_toplist_cp.fcg')
            .replace(queryParameters: {
          'topid': c['id']!,
          'page': '1',
          'toptype': 'top',
          'format': 'json',
          'platform': 'h5',
          'needNewCode': '1',
        });
        final j = await _getRaw(uri, _hQq) as Map<String, dynamic>;
        final pic = (j['topinfo'] as Map?)?['pic']?.toString() ?? '';
        if (pic.isNotEmpty) {
          cover = pic.replaceFirst('http://', 'https://');
        }
      } catch (_) {}
      out.add({'id': c['id'], 'name': c['name'], 'coverImgUrl': cover});
    }
    return out;
  }

  /// QQ 榜单歌曲（topid 榜单 id，songmid 作为 id）。
  /// 用 c.y.qq.com 老接口 fcg_v8_toplist_cp.fcg（匿名可用，2026-09 实测 code=0）。
  Future<List<Song>> qqToplistSongs(String chartId,
      {String cookie = '', int limit = 30}) =>
      qqToplistCp(chartId, limit: limit);

  /// QQ 网页老榜单接口（无需 cookie，实测可用）。
  Future<List<Song>> qqToplistCp(String topid, {int limit = 100}) async {
    final uri = Uri.parse('https://c.y.qq.com/v8/fcg-bin/fcg_v8_toplist_cp.fcg')
        .replace(queryParameters: {
      'topid': topid,
      'page': '1',
      'toptype': 'top',
      'format': 'json',
      'platform': 'h5',
      'needNewCode': '1',
    });
    try {
      final j = await _getRaw(uri, _hQq) as Map<String, dynamic>;
      final list = (j['songlist'] as List?) ?? const [];
      return list.cast<Map<String, dynamic>>().map((t) {
        final d = (t['data'] as Map?) ?? t; // 歌曲字段在 data 子对象里；兼容无 data 格式
        final singers = ((d['singer'] as List?) ?? [])
            .map((s) => (s as Map)['name']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .join(' / ');
        final mid = (d['songmid'] ?? d['mid'] ?? '').toString();
        final albumMid = (d['albummid'] ?? d['album']?['mid'] ?? '').toString();
        return Song(
          id: mid,
          title: (d['songname'] ?? d['name'] ?? '').toString(),
          artist: singers.isEmpty ? '未知' : singers,
          album: (d['albumname'] ?? d['album']?['name'] ?? '').toString(),
          coverUrl: albumMid.isEmpty
              ? null
              : 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albumMid.jpg',
          durationSec: (d['interval'] as num?)?.toInt(),
          fromExternal: true,
          externalSource: 'qq',
          year: _yearOf(d['pubtime'] ?? d['time']),
        );
      }).where((s) => s.id.isNotEmpty).take(limit).toList();
    } catch (_) {
      return const [];
    }
  }

  // ===== LX 音乐源（通用网易云/QQ 兼容 API）=====
  // 默认源可在设置页配置；榜单/歌单/搜索都走这里。
  static String lxBase = 'https://music-api.gdstudio.xyz';
  static const List<String> lxBases = [
    'https://music-api.gdstudio.xyz',
    'https://api.injahow.cn/meting',
    'https://lxmusic-api.deno.dev',
  ];

  Map<String, String> get _hlx => {
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://music.163.com/',
      };

  /// LX 搜索
  Future<List<Song>> lxSearch(String kw, {int limit = 30}) async {
    for (final base in lxBases) {
      try {
        final uri = Uri.parse('$base/api/search').replace(queryParameters: {
          'keywords': kw, 'limit': '$limit',
        });
        final r = await http.get(uri, headers: _hlx).timeout(const Duration(seconds: 10));
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        final list = ((j['result'] as Map?)?['songs'] as List?) ?? [];
        return list.cast<Map>().map((s) {
          final al = (s['al'] as Map?) ?? {};
          return Song(
            id: 'lx_${s['id']}',
            title: (s['name'] ?? '').toString(),
            artist: ((s['ar'] as List?) ?? []).map((a) => a['name']).join(' / '),
            album: (al['name'] ?? '').toString(),
            coverUrl: (al['picUrl'] ?? '').toString(),
            durationSec: ((s['dt'] as num?)! / 1000).round(),
            fromExternal: true, externalSource: 'lx',
            year: _yearOf(s['publishTime']),
          );
        }).toList();
      } catch (_) { continue; }
    }
    return const [];
  }

  /// LX 歌单详情
  Future<List<Song>> lxPlaylistSongs(String id) async {
    for (final base in lxBases) {
      try {
        final uri = Uri.parse('$base/api/playlist/detail').replace(queryParameters: {'id': id});
        final r = await http.get(uri, headers: _hlx).timeout(const Duration(seconds: 10));
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        final list = ((j['playlist'] as Map?)?['tracks'] as List?) ?? [];
        return list.cast<Map>().map((s) {
          final al = (s['al'] as Map?) ?? {};
          return Song(
            id: 'lx_${s['id']}',
            title: (s['name'] ?? '').toString(),
            artist: ((s['ar'] as List?) ?? []).map((a) => a['name']).join(' / '),
            album: (al['name'] ?? '').toString(),
            coverUrl: (al['picUrl'] ?? '').toString(),
            durationSec: ((s['dt'] as num? ?? 0) / 1000).round(),
            fromExternal: true, externalSource: 'lx',
            year: _yearOf(s['publishTime']),
          );
        }).toList();
      } catch (_) { continue; }
    }
    return const [];
  }

  /// LX 播放地址
  Future<String?> lxUrl(String songId) async {
    final sid = songId.replaceFirst('lx_', '');
    for (final base in lxBases) {
      try {
        final uri = Uri.parse('$base/api/song/url').replace(queryParameters: {
          'id': sid, 'br': '320000',
        });
        final r = await http.get(uri, headers: _hlx).timeout(const Duration(seconds: 10));
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        final data = (j['data'] as List?)?.cast<Map>() ?? [];
        if (data.isNotEmpty && data[0]['url'] != null) return data[0]['url'].toString();
      } catch (_) { continue; }
    }
    return null;
  }
  /// LX 先行版（meting，已验证可用）：网易云歌单/榜单拉取。
  /// meting 返回数组 [{name, artist, url, pic, lrc}]，url 即直链、pic 即封面。
  /// id 为网易云歌单/榜单 id。歌曲直接带 streamUrl，播放不再二次解析。
  Future<List<Song>> lxMetingPlaylistSongs(String id) async {
    for (final b in <String>['https://api.injahow.cn/meting', lxBase]) {
      try {
        final uri = Uri.parse(b).replace(queryParameters: {'type': 'playlist', 'id': id});
        final r = await http.get(uri, headers: _hlx).timeout(const Duration(seconds: 12));
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        if (j is! List) continue;
        final list = j.cast<Map<String, dynamic>>();
        if (list.isEmpty) continue;
        final out = <Song>[];
        for (final s in list) {
          final title = (s['name'] ?? '').toString();
          if (title.isEmpty) continue;
          out.add(Song(
            id: 'lx_' + (s['url']?.toString() ?? ''),
            title: title,
            artist: (s['artist'] ?? '').toString(),
            album: (s['album'] ?? '').toString(),
            coverUrl: (s['pic'] ?? '').toString(),
            streamUrl: (s['url'] ?? '').toString(),
            lrcUrl: (s['lrc'] ?? '').toString(),
            durationSec: int.tryParse(s['interval']?.toString() ?? '') ?? 0,
            fromExternal: true, externalSource: 'lx',
          ));
        }
        if (out.isNotEmpty) return out;
      } catch (_) { continue; }
    }
    return const [];
  }

  /// LX/meting 歌词直链：拉取 LRC 文本并解析为 Lyrics（失败/无词返回 null）。
  Future<Lyrics?> lxLrc(String lrcUrl) async {
    try {
      final r = await http.get(Uri.parse(lrcUrl), headers: _hlx).timeout(const Duration(seconds: 12));
      final raw = utf8.decode(r.bodyBytes);
      if (raw.trim().isEmpty) return null;
      return Lyrics.fromLrc(raw);
    } catch (_) { return null; }
  }
  /// LX 先行版预置：网易云榜单/精选歌单（id 已实测非空可拉）。
  static const List<Map<String, String>> lxPresets = [
    {'id': '19723756', 'name': '飙升榜', 'coverUrl': 'https://api.injahow.cn/meting/?server=netease&type=pic&id=109951172568091306'},
    {'id': '3778678', 'name': '热歌榜', 'coverUrl': 'https://api.injahow.cn/meting/?server=netease&type=pic&id=109951170483263672'},
    {'id': '3779629', 'name': '新歌榜', 'coverUrl': 'https://api.injahow.cn/meting/?server=netease&type=pic&id=109951173820334666'},
    {'id': '2884035', 'name': '原创榜', 'coverUrl': 'https://api.injahow.cn/meting/?server=netease&type=pic&id=109951173951926165'},
    {'id': '3136952023', 'name': '华语精选', 'coverUrl': 'https://api.injahow.cn/meting/?server=netease&type=pic&id=109951165418603915'},
    {'id': '1978921795', 'name': '抖音热歌', 'coverUrl': 'https://api.injahow.cn/meting/?server=netease&type=pic&id=109951173554809216'},
    {'id': '2809577409', 'name': '欧美热歌', 'coverUrl': 'https://api.injahow.cn/meting/?server=netease&type=pic&id=109951173998585253'},
    {'id': '2250011882', 'name': '抖音热门', 'coverUrl': 'https://api.injahow.cn/meting/?server=netease&type=pic&id=109951165647093663'},
  ];  /// 每日30首（填了 QQ cookie 时）：QQ 热歌榜（topid=4）前 30，匿名老接口即可。
  Future<List<Song>> daily30FromQq({String cookie = '', int count = 30}) async {
    // 每日30首：填了有效 QQ cookie 优先走账号个性化推荐（按爱听）；否则兜底。
    if (cookie.trim().isNotEmpty) {
      try {
        final rec = await qqDailyRecommend(cookie, count: count);
        if (rec.isNotEmpty) return rec;
      } catch (_) {}
    }
    // FM 接口对多数 cookie 会 500003（登录态受限），静默回退到固定热歌榜导致"每天不变"。
    // 改为：合并多个 QQ 榜单，按日期种子随机取 count 首，保证每天变化且是真实歌曲。
    final byId = <String, Song>{};
    for (final id in const ['27', '62', '4', '26']) {
      // 27=新歌榜 62=飙升榜 4=流行指数榜 26=热歌榜
      try {
        for (final s in await qqToplistCp(id, limit: count)) {
          byId[s.id] = s;
        }
      } catch (_) {}
    }
    final list = byId.values.toList();
    if (list.isEmpty) return daily30FromKugou(count: count);
    final days = DateTime.now().difference(DateTime(2026, 1, 1)).inDays;
    list.shuffle(Random(days));
    return list.take(count).toList();
  }

  /// QQ 每日推荐（账号个性化，GetRecommendSong）：依赖登录 cookie，按账号爱听推荐。
  /// 返回歌曲带直链封面/时长；若接口不可用或字段解析失败会抛异常由调用方兜底。
  Future<List<Song>> qqDailyRecommend(String cookie, {int count = 30}) async {
    final uinNum = int.tryParse(_uinFromCookie(cookie).replaceAll('o', '')) ?? 0;
    final body = {
      'comm': {'ct': 24, 'cv': 0, 'uin': uinNum, 'format': 'json', 'inCharset': 'utf-8'},
      'req_0': {
        'module': 'v8.FM',
        'method': 'GetFmList',
        'param': {
          'songCount': count, 'uin': uinNum, 'playAction': 'default',
        },
      },
    };
    final j = await _qqFcg(body, cookie: cookie);
    final data = j['req_0']?['data'];
    final list = (data?['songInfo'] as List?) ?? (data?['songList'] as List?) ?? const [];
    return list.cast<Map>().map((t) {
      final album = (t['album'] as Map?) ?? const {};
      final albumMid = (album['mid'] ?? '').toString();
      final singers = ((t['singer'] as List?) ?? const [])
          .map((x) => ((x as Map?) ?? const {})['name']?.toString() ?? '')
          .where((x) => x.isNotEmpty)
          .join(' / ');
      return Song(
        id: (t['mid'] ?? '').toString(),
        title: (t['name'] ?? '').toString(),
        artist: singers.isEmpty ? '未知' : singers,
        album: (album['name'] ?? '').toString(),
        coverUrl: albumMid.isEmpty ? null : 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albumMid.jpg',
        durationSec: (t['interval'] as num?)?.toInt(),
        fromExternal: true,
        externalSource: 'qq',
        year: _yearOf(t['time'] ?? t['pubtime']),
      );
    }).where((x) => x.id.isNotEmpty).take(count).toList();
  }

  /// QQ 精选歌单（新版 musicu.fcg 接口）：
  /// - categoryId == 0（全部）：music.playlist.PlaylistSquare/GetRecommendWhole 推荐歌单
  /// - categoryId > 0（风格分类，如流行3152/电子45/轻音乐49/民谣48/说唱42/摇滚41/古风61）：
  ///   music.playlist.PlayListCategory/get_category_content
  /// 实测各风格分类均有独立数据（total≈1000），封面/播放量/创建者齐全，无需兜底合并。
  Future<List<Map<String, dynamic>>> qqPlaylists({int categoryId = 0, int take = 12}) async {
    try {
      final Map<String, dynamic> req1 = categoryId == 0
          ? {
              'module': 'music.playlist.PlaylistSquare',
              'method': 'GetRecommendWhole',
              'param': {'IsReqFeed': true, 'FeedReq': {'From': 0, 'Size': 50}},
            }
          : {
              'module': 'music.playlist.PlayListCategory',
              'method': 'get_category_content',
              'param': {
                'caller': '474769524', // 固定 uin，接口仅用于识别调用方，无需登录态
                'category_id': categoryId,
                'size': 50,
                'page': 0,
                'use_page': 1,
              },
            };
      final data = {'comm': {'ct': 24, 'cv': 0}, 'req_1': req1};
      final uri = Uri.parse('https://t.y.qq.com/cgi-bin/musicu.fcg').replace(
          queryParameters: {'format': 'json', 'data': jsonEncode(data)});
      final resp = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0 Mobile Safari/537.36',
        'Referer': 'https://y.qq.com/n/ryqq_v2/category',
        'Origin': 'https://y.qq.com',
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      }).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        throw StateError('QQ 歌单广场接口 HTTP ${resp.statusCode}');
      }
      Map<String, dynamic>? j;
      try {
        j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {
        try {
          j = jsonDecode(utf8.decode(gzip.decode(resp.bodyBytes))) as Map<String, dynamic>;
        } catch (_) {
          final txt = utf8.decode(resp.bodyBytes, allowMalformed: true);
          final m = RegExp(r'\{"code".*?\}', dotAll: true).firstMatch(txt);
          if (m != null) j = jsonDecode(m.group(0)!) as Map<String, dynamic>;
        }
      }
      final r1 = j?['req_1'] as Map?;
      if (j == null || j['code'] != 0 || r1 == null || r1['code'] != 0) {
        throw StateError('QQ 歌单广场接口异常 code=${j?['code']} req=${r1?['code']}');
      }
      final body = (r1['data'] as Map?) ?? const {};
      final List<dynamic> items = categoryId == 0
          ? (((body['FeedRsp'] as Map?)?['List']) as List?) ?? const []
          : (((body['content'] as Map?)?['v_item']) as List?) ?? const [];
      final maps = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final raw in items.cast<Map>()) {
        final Map basic;
        if (categoryId == 0) {
          final p = (raw['Playlist'] as Map?) ?? const {};
          basic = (p['basic'] as Map?) ?? const {};
        } else {
          basic = (raw['basic'] as Map?) ?? const {};
        }
        final id = basic['tid']?.toString() ?? '';
        if (id.isEmpty || !seen.add(id)) continue;
        final cover = basic['cover'] as Map?;
        var img = cover?['default_url']?.toString() ?? '';
        if (img.isEmpty) img = cover?['pic_url2']?.toString() ?? '';
        if (img.startsWith('http://')) img = 'https://' + img.substring(7);
        final creator = basic['creator'] as Map?;
        maps.add({
          'dissid': id,
          'name': basic['title']?.toString() ?? '歌单',
          'coverImgUrl': img,
          'listennum': (basic['play_cnt'] as num?)?.toInt() ?? 0,
          'creator': creator?['nick']?.toString() ?? '',
        });
      }
      if (maps.isEmpty) {
        throw StateError('QQ 歌单广场接口返回空列表（分类$categoryId）');
      }
      // 按收听数降序，取前 take 个（车机6列2行/手机3列4行）
      maps.sort((a, b) =>
          ((b['listennum'] ?? 0) as num).compareTo((a['listennum'] ?? 0) as num));
      return maps.take(take).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// QQ 歌单歌曲（qzone 匿名接口）
  Future<List<Song>> qqPlaylistSongs(String dissid, {int limit = 50}) async {
    try {
      final u = Uri.parse('https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg')
          .replace(queryParameters: {
        'type': '1', 'utf8': '1', 'disstid': dissid, 'format': 'json',
        'inCharset': 'utf-8', 'outCharset': 'utf-8', 'notice': '0',
        'platform': 'y.json', 'needNewCode': '0', 'loginUin': '0',
        'hostUin': '0', 'song_num': '$limit', 'song_begin': '0',
      });
      final resp = await http.get(u, headers: {
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://y.qq.com/',
      });
      final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final list = (j['cdlist'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (list.isEmpty) return const [];
      final songs = (list.first['songlist'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      return songs.map((m) {
        final mid = (m['songmid'] ?? '').toString();
        final title = (m['songname'] ?? '').toString();
        final artist = (m['singer'] as List?)?.cast<Map>().map((s) => s['name']).join(' / ') ?? '';
        final albummid = (m['albummid'] ?? '').toString();
        return Song(
          id: mid,
          title: title,
          artist: artist,
          album: (m['albumname'] ?? '').toString(),
          coverUrl: 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albummid.jpg',
          fromExternal: true,
          externalSource: 'qq',
        );
      }).where((s) => s.id.isNotEmpty).take(limit).toList();
    } catch (_) {
      return const [];
    }
  }

  /// QQ 电台列表（fcg_v8_radiolist 匿名接口）：返回按组分组的结构
  /// [{groupName, radios: [{id, name, coverUrl, listenNum}]}]
  Future<List<Map<String, dynamic>>> qqRadios() async {
    final uri = Uri.parse('https://c.y.qq.com/v8/fcg-bin/fcg_v8_radiolist.fcg')
        .replace(queryParameters: {
      'channel': 'radio', 'page': 'index', 'tpl': 'wk', 'new': '1',
      'p': '1', 'format': 'json', 'outCharset': 'utf-8',
    });
    final resp = await http.get(uri, headers: {
      'User-Agent': 'Mozilla/5.0',
      'Referer': 'https://y.qq.com/',
    }).timeout(const Duration(seconds: 15));
    final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final groupList = (j['data']?['data']?['groupList'] as List?) ?? const [];
    final out = <Map<String, dynamic>>[];
    for (final g in groupList.cast<Map>()) {
      final gname = (g['groupName'] ?? g['name'] ?? '').toString().trim();
      final radios = (g['radioList'] as List?) ?? const [];
      final items = <Map<String, dynamic>>[];
      for (final r in radios.cast<Map>()) {
        final id = r['radioId'];
        final name = (r['radioName'] ?? '').toString();
        if (id == null || name.isEmpty) continue;
        final img = (r['radioImg'] ?? '').toString();
        items.add({
          'id': id,
          'name': name,
          'coverUrl': img.startsWith('http')
              ? img.replaceFirst('http://', 'https://')
              : null,
          'listenNum': (r['listenNum'] ?? 0),
        });
      }
      if (items.isEmpty) continue;
      out.add({
        'groupName': gname.isEmpty ? '电台' : gname,
        'radios': items,
      });
    }
    return out;
  }

  /// QQ 电台歌曲（musicu get_radio_track，匿名可用）：单次固定返回 5 首，
  /// 循环拉取按 mid 去重凑 ~30 首；个性电台（code 1000）需登录态，明确抛错。
  Future<List<Song>> qqRadioSongs(int radioId) async {
    final headers = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0 Mobile Safari/537.36',
      'Referer': 'https://y.qq.com/',
    };
    final seen = <String>{};
    final songs = <Song>[];
    int? lastCode;
    for (var i = 0; i < 6 && songs.length < 30; i++) {
      final body = {
        'comm': {'ct': 24, 'cv': 0},
        'songlist': {
          'module': 'mb_track_radio_svr',
          'method': 'get_radio_track',
          'param': {'id': radioId, 'firstplay': 1, 'num': 30},
        },
      };
      final uri = Uri.parse('https://t.y.qq.com/cgi-bin/musicu.fcg')
          .replace(queryParameters: {'format': 'json', 'data': jsonEncode(body)});
      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
      final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final code = j['code'] ?? j['songlist']?['code'];
      lastCode = code;
      // QQ 封死匿名拉取（代理/个别网络下）：明确抛错，避免显示"没有歌曲数据"误导。
      if (code == 500001) {
        throw StateError('QQ需登录态');
      }
      final tracks = (j['songlist']?['data']?['tracks'] as List?) ?? const [];
      // 个性电台（id=99 等）匿名返回 code 1000 且 tracks 为空：需登录态个性化推荐
      if (tracks.isEmpty && code == 1000) {
        throw StateError('个性电台需登录态');
      }
      for (final t in tracks.cast<Map>()) {
        final mid = (t['mid'] ?? '').toString();
        if (mid.isEmpty || !seen.add(mid)) continue;
        final album = (t['album'] as Map?) ?? const {};
        final albumMid = (album['mid'] ?? '').toString();
        final singers = ((t['singer'] as List?) ?? const [])
            .map((x) => ((x as Map?) ?? const {})['name']?.toString() ?? '')
            .where((x) => x.isNotEmpty)
            .join(' / ');
        songs.add(Song(
          id: mid,
          title: (t['name'] ?? t['title'] ?? '').toString(),
          artist: singers.isEmpty ? '未知' : singers,
          album: (album['name'] ?? '').toString(),
          coverUrl: albumMid.isEmpty
              ? null
              : 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albumMid.jpg',
          durationSec: (t['interval'] as num?)?.toInt(),
          fromExternal: true,
          externalSource: 'qq',
        ));
      }
    }
    if (songs.isEmpty) {
      // 循环结束仍无歌曲：QQ 已封死匿名拉取电台（含"个性电台"需登录态），
      // 明确抛错（带实际 code 便于定位），避免上层显示"没有歌曲数据"误导。
      throw StateError('QQ电台接口无歌曲（code=$lastCode，需登录态，已限制匿名拉取）');
    }
    return songs;
  }

  /// QQ 歌单详情：歌单名 + 歌曲列表（qzone 匿名接口，song_num 上限约 1000）。
  /// 用于音乐库"导入歌单"：输入歌单 ID 拉取歌曲（不足 1000 首的歌单可拉全）。
  Future<(String, List<Song>, String)> qqPlaylistDetail(String dissid,
      {int limit = 1000}) async {
    try {
      final u = Uri.parse('https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg')
          .replace(queryParameters: {
        'type': '1', 'utf8': '1', 'disstid': dissid, 'format': 'json',
        'inCharset': 'utf-8', 'outCharset': 'utf-8', 'notice': '0',
        'platform': 'y.json', 'needNewCode': '0', 'loginUin': '0',
        'hostUin': '0', 'song_num': '$limit', 'song_begin': '0',
      });
      final resp = await http.get(u, headers: {
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://y.qq.com/',
      });
      final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final list = (j['cdlist'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (list.isEmpty) return ('', const <Song>[], '');
      final name = (list.first['dissname'] ?? '').toString();
      final songs = (list.first['songlist'] as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];
      final cover = (list.first['pic'] ??
                  list.first['pic_url'] ??
                  list.first['logo'] ??
                  list.first['imgurl'] ??
                  '')
              .toString()
          .replaceAll('http://', 'https://');
      return (name, songs.map<Song>((m) {
        final mid = (m['songmid'] ?? '').toString();
        final title = (m['songname'] ?? '').toString();
        final artist =
            (m['singer'] as List?)?.cast<Map>().map((s) => s['name']).join(' / ') ?? '';
        final albummid = (m['albummid'] ?? '').toString();
        return Song(
          id: mid,
          title: title,
          artist: artist,
          album: (m['albumname'] ?? '').toString(),
          coverUrl: 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albummid.jpg',
          fromExternal: true,
          externalSource: 'qq',
        );
      }).where((s) => s.id.isNotEmpty).take(limit).toList(), cover);
    } catch (_) {
      return ('', const <Song>[], '');
    }
  }

  /// 轻量取歌单封面（复用 qzone 详情接口，song_num=1 只解析封面，不拉歌曲列表）。
  /// 用于 ID 歌单补封面：旧版导入的歌单无 cover 字段，进页面时懒加载回写。
  Future<String> qqPlaylistCover(String dissid) async {
    try {
      final u = Uri.parse('https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg')
          .replace(queryParameters: {
        'type': '1', 'utf8': '1', 'disstid': dissid, 'format': 'json',
        'inCharset': 'utf-8', 'outCharset': 'utf-8', 'notice': '0',
        'platform': 'y.json', 'needNewCode': '0', 'loginUin': '0',
        'hostUin': '0', 'song_num': '1', 'song_begin': '0',
      });
      final resp = await http.get(u, headers: {
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://y.qq.com/',
      });
      final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final list = (j['cdlist'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (list.isEmpty) return '';
      final c = (list.first['pic'] ??
                  list.first['pic_url'] ??
                  list.first['logo'] ??
                  list.first['imgurl'] ??
                  '')
              .toString()
          .replaceAll('http://', 'https://');
      return c;
    } catch (_) {
      return '';
    }
  }

  // ==================== 酷狗榜单（mobilecdn 公开接口，无签名） ====================

  /// 酷狗榜单原始数据（rankid: 8888=TOP500, 6666=飙升榜 等）。
  Future<List<Map<String, String>>> kugouRankRaw(String rankid,
      {int page = 1, int pagesize = 30}) async {
    try {
      final j = await _insecureGetJson(
        Uri.parse('https://mobilecdn.kugou.com/api/v3/rank/song')
            .replace(queryParameters: {
          'rankid': rankid, 'page': '$page', 'pagesize': '$pagesize',
        }),
      );
      final info = (j['data']?['info'] as List?) ?? [];
      return info.cast<Map<String, dynamic>>().map((it) {
        final authors = (it['authors'] as List?) ?? [];
        final artist = authors
            .map((a) => (a as Map)['author_name']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .join(' / ');
        return {
          'title': it['songname']?.toString() ?? '',
          'artist': artist,
        };
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 酷狗按关键词搜索歌曲封面（union_cover，{size} 替换为 400）。
  /// 用于：本地歌曲/歌手无图时按 歌名+歌手（或歌手名）搜封面。
  Future<String?> kugouSearchCover(String keyword) async {
    try {
      final j = await _insecureGetJson(
        Uri.parse('http://mobilecdn.kugou.com/api/v3/search/song')
            .replace(queryParameters: {
          'format': 'json',
          'keyword': keyword,
          'page': '1',
          'pagesize': '5',
          'showtype': '1',
        }),
      );
      final info = ((j['data'] as Map?)?['info'] as List?) ?? [];
      for (final it in info.cast<Map>()) {
        final tp = (it['trans_param'] as Map?);
        final cover = tp?['union_cover']?.toString() ?? '';
        if (cover.isNotEmpty && cover.contains('{size}')) {
          final u = cover.replaceAll('{size}', '400');
          // [xmusic] 酷狗图床统一走 https，避免明文流量边缘问题
          return u.startsWith('http://') ? 'https://' + u.substring(7) : u;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 网易云按歌手名搜索真实歌手头像（type=100 歌手搜索）。
  /// [xmusic] 2026-09-24 实测：music.163.com/api/search/get?type=100 已恢复可用
  /// （返回 artists[].picUrl 歌手本人照片；0.3.216 时期曾 400 失效被放弃）。
  /// 用于音乐库歌手列表头像，优先于酷狗歌曲封面（用户要求"歌手图片"而非歌曲封面）。
  Future<String?> neteaseArtistAvatar(String name) async {
    if (name.trim().isEmpty) return null;
    try {
      final uri = Uri.parse('https://music.163.com/api/search/get')
          .replace(queryParameters: {
        's': name.trim(), 'type': '100', 'offset': '0', 'limit': '3',
      });
      final j = await _getRaw(uri, _h163, timeoutSec: 10) as Map<String, dynamic>;
      final artists = (((j['result'] as Map?)?['artists']) as List?) ?? [];
      for (final a in artists.cast<Map<String, dynamic>>()) {
        // 精确匹配歌手名（防同名歌手）
        final an = (a['name'] ?? '').toString();
        final alias = ((a['alias'] as List?) ?? []).cast<String>();
        if (an == name.trim() || alias.any((x) => x == name.trim())) {
          final pic = a['picUrl']?.toString() ?? '';
          if (pic.isNotEmpty) return pic;
        }
      }
      // 无精确匹配：取第一个歌手（搜索结果首位通常是目标歌手）
      if (artists.isNotEmpty) {
        final pic = (artists.first as Map)['picUrl']?.toString() ?? '';
        if (pic.isNotEmpty) return pic;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 网易云按 歌名+歌手 搜索匹配（酷狗等源的播放兜底）。
  /// 网易云搜索接口不返回 picUrl（album 只有 picId）；用 song/detail 补封面。
  Future<Song> _withNeteaseCover(Song s) async {
    if ((s.coverUrl ?? '').isNotEmpty) return s;
    try {
      final r = await _getRaw(
        Uri.parse('https://music.163.com/api/song/detail?ids=[${s.id}]'),
        _h163,
        timeoutSec: 10,
      ) as Map<String, dynamic>;
      final songs = (r['songs'] as List?) ?? [];
      if (songs.isNotEmpty) {
        final m = songs.first as Map;
        final pic = ((m['album'] as Map?)?['picUrl'])?.toString();
        if (pic != null && pic.isNotEmpty) {
          return Song(
            id: s.id,
            title: s.title,
            artist: s.artist,
            album: s.album,
            coverArt: null,
            coverUrl: pic,
            durationSec: s.durationSec,
            fromExternal: true,
            externalSource: 'netease',
          );
        }
      }
    } catch (_) {}
    return s;
  }

  Future<Song?> matchNetease(String title, String artist) async {
    try {
      final kw = '$title $artist'.trim();
      final uri = Uri.parse('https://music.163.com/api/search/get')
          .replace(queryParameters: {
        's': kw, 'type': '1', 'offset': '0', 'limit': '3',
      });
      final j = await _getRaw(uri, _h163, timeoutSec: 10) as Map<String, dynamic>;
      final songs = (((j['result'] as Map?)?['songs']) as List?) ?? [];
      for (final raw in songs.cast<Map<String, dynamic>>()) {
        final name = (raw['name'] ?? '').toString();
        final singers = ((raw['artists'] as List?) ?? [])
            .map((a) => (a as Map)['name']?.toString() ?? '')
            .join(' / ');
        // [xmusic] 放宽匹配：去掉括号内容/空白/标点后比较，提高 QQ/酷狗歌名命中率
        String norm(String s) => s
            .replaceAll(RegExp(r'[（(【\[].*?[）)】\]]'), '')
            .replaceAll(RegExp(r'[\s\p{P}]'), '')
            .toLowerCase();
        final nameOk = name == title || name.contains(title) || title.contains(name) ||
            norm(name) == norm(title) || norm(name).contains(norm(title)) || norm(title).contains(norm(name));
        final artOk = artist.isEmpty ||
            singers.contains(artist) ||
            artist.contains(singers) ||
            norm(artist).contains(norm(singers)) || norm(singers).contains(norm(artist));
        if (nameOk && artOk) {
          final album = raw['album'] as Map<String, dynamic>?;
          final song = Song(
            id: raw['id'].toString(),
            title: name,
            artist: singers.isEmpty ? artist : singers,
            album: (album?['name'] ?? '').toString(),
            coverUrl: (album?['picUrl'] ?? raw['picUrl'])?.toString(),
            durationSec: (raw['duration'] as num?) != null
                ? ((raw['duration'] as num) / 1000).round()
                : null,
            fromExternal: true,
            externalSource: 'netease',
          );
          return await _withNeteaseCover(song);
        }
      }
      // 严格匹配失败：退而取第一条（至少是同名歌）
      final first = songs.firstOrNull as Map<String, dynamic>?;
      if (first != null) {
        final album = first['album'] as Map<String, dynamic>?;
        final song = Song(
          id: first['id'].toString(),
          title: (first['name'] ?? '').toString(),
          artist: artist.isEmpty ? '未知' : artist,
          album: (album?['name'] ?? '').toString(),
          coverUrl: (album?['picUrl'] ?? first['picUrl'])?.toString(),
          fromExternal: true,
          externalSource: 'netease',
        );
        return await _withNeteaseCover(song);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 每日30首（无 QQ cookie 时）：酷狗 TOP500 → 网易云匹配播放。
  Future<List<Song>> daily30FromKugou({int count = 30}) async {
    // [xmusic] 2026-09-24 优化：TOP500 + 飙升榜混合取歌（各一半），去重后匹配网易云，
    // 更贴近"每日30首·飙升/新歌/原创推荐"文案，且减少与排行榜网格（QQ热歌榜）重复。
    final half = (count / 2).ceil();
    final raw = <Map<String, String>>[];
    for (final rid in ['8888', '6666']) {
      try {
        raw.addAll(await kugouRankRaw(rid, page: 1, pagesize: half + 3));
      } catch (_) {}
    }
    // 每日换一批：日期做种子打乱
    final ds = DateTime.now();
    raw.shuffle(Random(ds.year * 10000 + ds.month * 100 + ds.day));
    final out = <Song>[];
    final seen = <String>{};
    for (final r in raw) {
      final title = r['title'] ?? '';
      final artist = r['artist'] ?? '';
      if (title.isEmpty) continue;
      final key = '$title|$artist';
      if (!seen.add(key)) continue; // 跨榜去重
      final s = await matchNetease(title, artist);
      if (s != null) {
        out.add(s);
        if (out.length >= count) break;
      }
    }
    return out;
  }

  // ==================== 酷我音乐直连 ====================

  /// 酷我音乐搜索（返回 rid 数字部分作为 id）。
  /// 2026-09 实测：搜索接口可用；播放走 antiserver（见 kuwoStreamUrl）。
  Future<List<Song>> searchKuwo(String keyword, {int limit = 20}) async {
    final uri = Uri.parse('http://search.kuwo.cn/r.s').replace(queryParameters: {
      'all': keyword,
      'ft': 'music',
      'itemset': 'web_2013',
      'client': 'kt',
      'pn': '0',
      'rn': '$limit',
      'rformat': 'json',
      'encoding': 'utf8',
      'vipver': 'MUSIC_8.7.7.0_WX',
      'mobi': '1',
    });
    try {
      final j = await _getRaw(uri, const {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
      }, timeoutSec: 10) as Map<String, dynamic>;
      final abslist = (j['abslist'] as List?) ?? const [];
      final out = <Song>[];
      for (final t in abslist.cast<Map<String, dynamic>>()) {
        final rid = (t['MUSICRID'] ?? '').toString().replaceFirst('MUSIC_', '');
        if (rid.isEmpty) continue;
        final pic = (t['pic'] ?? t['web_albumpic_short'] ?? '').toString();
        out.add(Song(
          id: rid,
          title: (t['SONGNAME'] ?? '').toString().replaceAll('&nbsp;', ' '),
          artist: (t['ARTIST'] ?? '未知').toString().replaceAll('\\u0026', '&'),
          album: (t['ALBUM'] ?? '').toString(),
          coverArt: null,
          coverUrl: pic.isEmpty
              ? null
              : (pic.startsWith('http') ? pic : 'https:$pic'),
          durationSec: null,
          fromExternal: true,
          externalSource: 'kuwo',
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// 酷我音乐播放地址（antiserver anti.s，2026-09 实测可用，返回纯文本 URL）。
  /// [xmusic] 2026-09-24 实测：VIP 歌曲 antiserver 返回 11 秒试听片段，
  /// URL 路径含 /nf/（如 .../nf/resource/...），完整版无 /nf/。调用方应视为不可播。
  Future<String?> kuwoStreamUrl(String rid) async {
    if (rid.isEmpty) return null;
    final uri = Uri.parse('http://antiserver.kuwo.cn/anti.s').replace(queryParameters: {
      'format': 'mp3',
      'rid': 'MUSIC_$rid',
      'response': 'url',
      'type': 'convert_url3',
    });
    try {
      final res = await http.get(uri, headers: const {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        'Referer': 'http://www.kuwo.cn/',
      }).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final url = utf8.decode(res.bodyBytes).trim();
      // [xmusic] 酷我 antiserver 2026-09 实测返回 JSON {"code":200,"url":"https://..."}，
      // 需解析取 url；兼容旧版纯文本 URL 响应。
      if (url.startsWith('{')) {
        try {
          final j = jsonDecode(url) as Map<String, dynamic>;
          final u = j['url']?.toString() ?? '';
          if (u.isNotEmpty && u.startsWith('http')) {
            // [xmusic] /nf/ = 试听片段，返回 null 视为受限不可播
            if (u.contains('/nf/')) return null;
            return u;
          }
        } catch (_) {}
        return null;
      }
      if (url.isEmpty || !url.startsWith('http')) return null;
      if (url.contains('/nf/')) return null; // [xmusic] 试听片段不可播
      return url;
    } catch (_) {
      return null;
    }
  }

  /// 酷我直连兜底：按歌名+歌手搜酷我并解析播放 URL（QQ/B站 播放失败时用，实测可用）。
  /// [xmusic] 2026-09-24 修复：antiserver 对 VIP 歌返回 /nf/ 试听（11秒），
  /// kuwoStreamUrl 已把试听视为失败；此处命中同名歌后逐首尝试，全试听则返回 null。
  Future<String?> matchKuwo(String title, String artist) async {
    try {
      final hits = await searchKuwo('$title $artist'.trim(), limit: 5);
      if (hits.isEmpty) return null;
      String norm(String s) => s
          .replaceAll(RegExp(r'[（(【\[].*?[）)】\]]'), '')
          .replaceAll(RegExp(r'[\s\p{P}]'), '')
          .toLowerCase();
      final nt = norm(title);
      final na = norm(artist);
      // [xmusic] 2026-09-24 修复"播放曲目与显示对不上号"：兜底换源必须歌名+歌手都匹配，
      // 否则宁可返回 null（上层继续其他源或失败提示），绝不强行播放无关歌曲（原实现
      // 最后无条件返回 hits.first，导致"素颜"播成同名/翻唱/别的歌）。
      for (final h in hits) {
        final hn = norm(h.title);
        final ha = norm(h.artist);
        final titleOk = hn == nt || hn.contains(nt) || nt.contains(hn);
        final artOk = na.isEmpty ||
            ha == na || ha.contains(na) || na.contains(ha) ||
            ha.contains(na.split(' ').first) || na.contains(ha.split(' ').first);
        if (titleOk && artOk) {
          final u = await kuwoStreamUrl(h.id);
          if (u != null && u.isNotEmpty) return u;
        }
      }
      return null; // 无歌名+歌手都匹配的条目，不强行兜底
    } catch (_) {
      return null;
    }
  }

  // ==================== B站直连 ====================

  /// B站热门视频（x/web-interface/popular，匿名可用，实测 code=0）。
  /// 返回 Song（id=aid 数字，biliStreamUrl 兼容），封面 pic 转 https。
  Future<List<Song>> biliHotVideos({int limit = 15}) async {
    final uri = Uri.parse('https://api.bilibili.com/x/web-interface/popular')
        .replace(queryParameters: {'ps': '$limit', 'pn': '1'});
    try {
      final j = await _getRaw(uri, _hBili) as Map<String, dynamic>;
      final list = (((j['data'] as Map?)?['list']) as List?) ?? const [];
      return list.cast<Map<String, dynamic>>().map((v) {
        final owner = (v['owner'] as Map?) ?? const {};
        final pic = (v['pic'] ?? '').toString();
        return Song(
          id: (v['aid'] ?? '').toString(),
          title: (v['title'] ?? '').toString(),
          artist: (owner['name'] ?? 'UP主').toString(),
          album: 'B站热门',
          coverUrl: pic.startsWith('http')
              ? pic.replaceFirst('http://', 'https://')
              : null,
          durationSec: (v['duration'] as num?)?.toInt(),
          fromExternal: true,
          externalSource: 'bilibili',
        );
      }).where((s) => s.id.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  /// B站视频音轨直连：view 拿 cid+bvid → playurl 拿音频流（选最高码率）。
  /// 兼容 bvid（BV 开头）与 aid（纯数字）两种 id。
  /// [xmusic] 2026-09 实测：playurl 接口用 aid 参数一律 -400（新旧 aid 均验证），
  /// 必须改用 view 返回的 bvid 参数才能正常取流。因此统一从 view 取 bvid 再请求。
  Future<String?> biliStreamUrl(String bvidOrAid) async {
    final id = bvidOrAid.trim();
    if (id.isEmpty) return null;
    final isBv = RegExp(r'^[Bb][Vv][0-9A-Za-z]+$').hasMatch(id);
    final viewParam = isBv ? 'bvid=$id' : 'aid=$id';
    try {
      final view = await _getRaw(
        Uri.parse('https://api.bilibili.com/x/web-interface/view?$viewParam'),
        _hBili,
      ) as Map<String, dynamic>;
      final data = view['data'] as Map<String, dynamic>?;
      final cid = data?['cid']?.toString();
      // [xmusic] 关键：playurl 只认 bvid，从 view 结果取 bvid 用于取流
      final bvid = data?['bvid']?.toString();
      if (cid == null || cid.isEmpty) return null;
      if (bvid == null || bvid.isEmpty) return null;
      final play = await _getRaw(
        Uri.parse(
            'https://api.bilibili.com/x/player/playurl?bvid=$bvid&cid=$cid&fnval=16&fourk=1'),
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
