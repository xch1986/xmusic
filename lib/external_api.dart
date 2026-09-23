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
    try {
      final uin = cookie.isEmpty
          ? 0
          : (int.tryParse(_uinFromCookie(cookie).replaceFirst('o', '')) ?? 0);
      final j = await _qqFcg({
        'comm': {'ct': 24, 'cv': 0, if (uin > 0) 'uin': uin},
        'req_0': {
          'module': 'music.chart.songlist',
          'method': 'GetChartSongList',
          'param': {'chartId': 4, 'num': 1, 'page': 0},
        },
      }, cookie: cookie) as Map<String, dynamic>;
      final code = (j['req_0']?['code'] as num?)?.toInt() ?? -1;
      final list = ((j['req_0']?['data']?['songInfoList'] ??
              j['req_0']?['data']?['list']) as List?) ??
          [];
      if (code == 0 && list.isNotEmpty) {
        return (true, '有效：QQ 榜单/播放已解锁');
      }
      if (code == 500003) {
        return (false,
            '登录态无效（500003）：Cookie 缺登录凭证或已失效。请从 F12 → Network → musicu.fcg 请求头整串复制（含 psrf_qqaccess_token / skey / uin 等 HttpOnly 字段），不要打码、不要手敲');
      }
      if (code == 500001) return (false, '参数错误（500001）：Cookie 格式异常');
      return (false, '服务端返回错误码 $code');
    } catch (_) {
      return (false, '请求失败：网络或接口异常，请稍后重试');
    }
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
      final j = await _getRaw(uri, _hQq) as Map<String, dynamic>;
      final raw = j['lyric']?.toString() ?? '';
      if (raw.trim().isEmpty) return null;
      return Lyrics.fromLrc(raw);
    } catch (_) {
      return null;
    }
  }

  /// QQ 排行榜列表（带 cookie 更稳）。返回 {id, name, coverImgUrl}。
  Future<List<Map<String, dynamic>>> qqToplists({String cookie = ''}) async {
    try {
      final uin = cookie.isEmpty ? 0 : (int.tryParse(_uinFromCookie(cookie).replaceFirst('o', '')) ?? 0);
      final j = await _qqFcg({
        'comm': {'ct': 24, 'cv': 0, if (cookie.isNotEmpty) 'uin': uin},
        'req_0': {
          'module': 'music.chart.chartlist',
          'method': 'GetChartList',
          'param': {'showtype': 2},
        },
      }, cookie: cookie) as Map<String, dynamic>;
      final list = ((j['req_0']?['data']?['chart'] ?? j['req_0']?['data']?['list']) as List?) ?? [];
      return list.cast<Map<String, dynamic>>().map((m) => {
            'id': (m['chartId'] ?? m['id'] ?? '').toString(),
            'name': (m['chartName'] ?? m['name'] ?? '').toString(),
            'coverImgUrl': (m['picUrl'] ?? '').toString(),
          }).where((m) => (m['id'] ?? '').isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  /// QQ 榜单歌曲（chartId 榜单 id，songmid 作为播放 id）。
  Future<List<Song>> qqToplistSongs(String chartId,
      {String cookie = '', int limit = 30}) async {
    try {
      final uin = cookie.isEmpty ? 0 : (int.tryParse(_uinFromCookie(cookie).replaceFirst('o', '')) ?? 0);
      final j = await _qqFcg({
        'comm': {'ct': 24, 'cv': 0, if (cookie.isNotEmpty) 'uin': uin},
        'req_0': {
          'module': 'music.chart.songlist',
          'method': 'GetChartSongList',
          'param': {
            'chartId': int.tryParse(chartId) ?? 0,
            'num': limit,
            'page': 0,
          },
        },
      }, cookie: cookie) as Map<String, dynamic>;
      final list = ((j['req_0']?['data']?['songInfoList'] ?? j['req_0']?['data']?['list']) as List?) ?? [];
      return list.cast<Map<String, dynamic>>().map((t) {
        final singers = ((t['singer'] as List?) ?? [])
            .map((s) => (s as Map)['name']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .join(' / ');
        final mid = (t['mid'] ?? t['songmid'] ?? '').toString();
        final albumMid = (t['album']?['mid'] ?? '').toString();
        return Song(
          id: mid,
          title: (t['name'] ?? t['songname'] ?? '').toString(),
          artist: singers.isEmpty ? '未知' : singers,
          album: (t['album']?['name'] ?? '').toString(),
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

  /// 每日30首（有 QQ cookie 时）：QQ 热歌榜（chartId=4）前 30，播放走 QQ。
  Future<List<Song>> daily30FromQq({String cookie = '', int count = 30}) async {
    final songs = await qqToplistSongs('4', cookie: cookie, limit: count);
    if (songs.isEmpty) return daily30FromKugou(count: count); // 榜单接口异常时兜底
    return songs;
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

  /// 网易云按 歌名+歌手 搜索匹配（酷狗等源的播放兜底）。
  Future<Song?> matchNetease(String title, String artist) async {
    try {
      final kw = '$title $artist'.trim();
      final uri = Uri.parse('https://music.163.com/api/search/get')
          .replace(queryParameters: {
        's': kw, 'type': '1', 'offset': '0', 'limit': '3',
      });
      final j = await _getRaw(uri, _h163) as Map<String, dynamic>;
      final songs = (((j['result'] as Map?)?['songs']) as List?) ?? [];
      for (final raw in songs.cast<Map<String, dynamic>>()) {
        final name = (raw['name'] ?? '').toString();
        final singers = ((raw['artists'] as List?) ?? [])
            .map((a) => (a as Map)['name']?.toString() ?? '')
            .join(' / ');
        final nameOk = name == title || name.contains(title) || title.contains(name);
        final artOk = artist.isEmpty ||
            singers.contains(artist) ||
            artist.contains(singers);
        if (nameOk && artOk) {
          final album = raw['album'] as Map<String, dynamic>?;
          return Song(
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
        }
      }
      // 严格匹配失败：退而取第一条（至少是同名歌）
      final first = songs.firstOrNull as Map<String, dynamic>?;
      if (first != null) {
        final album = first['album'] as Map<String, dynamic>?;
        return Song(
          id: first['id'].toString(),
          title: (first['name'] ?? '').toString(),
          artist: artist.isEmpty ? '未知' : artist,
          album: (album?['name'] ?? '').toString(),
          coverUrl: (album?['picUrl'] ?? first['picUrl'])?.toString(),
          fromExternal: true,
          externalSource: 'netease',
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 每日30首（无 QQ cookie 时）：酷狗 TOP500 → 网易云匹配播放。
  Future<List<Song>> daily30FromKugou({int count = 30}) async {
    final raw = await kugouRankRaw('8888', page: 1, pagesize: count + 5);
    final out = <Song>[];
    for (final r in raw) {
      final title = r['title'] ?? '';
      if (title.isEmpty) continue;
      final s = await matchNetease(title, r['artist'] ?? '');
      if (s != null) out.add(s);
      if (out.length >= count) break;
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
      }) as Map<String, dynamic>;
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
      }).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final url = utf8.decode(res.bodyBytes).trim();
      if (url.isEmpty || !url.startsWith('http')) return null;
      return url;
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
