import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_handler.dart';
import 'external_api.dart';
import 'lyrics.dart';
import 'local_library.dart';
import 'main.dart';
import 'settings.dart';
import 'subsonic.dart';

/// Playback mode: sequential, shuffle or repeat-one.
enum PlayMode { sequential, shuffle, repeatOne }

/// Owns the audio player, the play queue and the current song's lyrics.
class PlayerController extends ChangeNotifier {
  PlayerController(this.client, this.settings) {
    // 先停止AudioService自动恢复的播放
    unawaited(player.stop());
    _completedSub = player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) _onCompleted();
    });
    _playingSub = player.playingStream.listen((_) => notifyListeners());
    _positionSub = player.positionStream.listen((pos) {
      _lastPos = pos;
      _lastPosTime = DateTime.now();
    });
    _stuckTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkStuck());
    // 通知栏/车机的 next/prev 按键回调。
    audioHandler.onSkipNext = next;
    audioHandler.onSkipPrevious = previous;
    // PlayerController 接管即放行系统主动播放（方向盘/通知栏 play）。
    // 仅 restoreLastState 防 AudioService 启动自动恢复时短暂置 false。
    audioHandler.allowPlay = true;
  }

  final SubsonicClient client;
  final AppSettings settings;
  AudioPlayer get player => audioHandler.player;

  ExternalApi get external => ExternalApi(settings.externalApiUrl);

  List<Song> queue = const [];
  int index = -1;
  Lyrics? lyrics;
  bool lyricsLoading = false;
  // 默认随机播放（用户要求：播放界面控制栏默认随机）
  PlayMode _repeat = PlayMode.shuffle;
  final Random _rnd = Random();

  late final StreamSubscription<ProcessingState> _completedSub;
  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<Duration> _positionSub;
  late final Timer _stuckTimer;
  Duration _lastPos = Duration.zero;
  DateTime _lastPosTime = DateTime.now();
  int _loadToken = 0;
  /// 播放加载令牌：快速连点切歌/自动播放时，只允许最新一次加载真正生效，
  /// 旧加载在关键节点放弃，避免两次 setUrl 相互覆盖造成竞态。
  int _playToken = 0;
  /// 自动封面令牌：切歌/连点只允许最新一次自动封面生效。
  int _coverToken = 0;
  /// 正在解析播放地址（外源歌兜底链较长，UI 据此显示"加载中"，避免用户以为没反应）。
  bool loadingUrl = false;
  String? lastError;
  Duration _prevStuckPos = Duration.zero;

  Future<File> get _stateFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/last_player.json');
  }

  Future<void> saveLastState() async {
    try {
      final f = await _stateFile;
      await f.writeAsString(jsonEncode({
        'index': index,
        'position': player.position.inMilliseconds,
        'queue': queue.map((s) => {
          'id': s.id, 'title': s.title, 'artist': s.artist, 'album': s.album,
          'coverArt': s.coverArt, 'coverUrl': s.coverUrl, 'streamUrl': s.streamUrl,
          'fromExternal': s.fromExternal, 'externalSource': s.externalSource,
        }).toList(),
      }));
    } catch (_) {}
  }

  Future<void> restoreLastState() async {
    try {
      final f = await _stateFile;
      if (!await f.exists()) return;
      final m = jsonDecode(await f.readAsString()) as Map;
      final list = (m['queue'] as List?) ?? [];
      if (list.isEmpty) return;
      queue = list.map((e) => Song(
        id: e['id'], title: e['title'], artist: e['artist'], album: e['album'],
        coverArt: e['coverArt'], coverUrl: e['coverUrl'], streamUrl: e['streamUrl'],
        fromExternal: e['fromExternal'] ?? false, externalSource: e['externalSource'],
      )).toList();
      index = (m['index'] as int?) ?? 0;
      if (index >= queue.length) index = 0;
      notifyListeners();
      // 先停止AudioService自动恢复的播放，避免双播
      audioHandler.allowPlay = false;
      await player.stop();
      try {
        await player.processingStateStream.firstWhere(
          (st) => st == ProcessingState.idle,
        ).timeout(const Duration(milliseconds: 800));
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 1500));
      try {
        await _loadAndPlay(index, autoplay: settings.autoPlay);
        // 恢复上次退出/切后台时的播放进度（>3秒才跳转，避免从头几秒还跳一下）
        final savedPos = (m['position'] as num?)?.toInt() ?? 0;
        if (savedPos > 3000) {
          try {
            await player.seek(Duration(milliseconds: savedPos));
          } catch (_) {}
        }
      } catch (_) {}
      // 恢复完成，重新放行系统主动播放（方向盘 play 有效）
      audioHandler.allowPlay = true;
    } catch (_) {}
  }

  Song? get current =>
      (index >= 0 && index < queue.length) ? queue[index] : null;
  bool get hasNext => queue.length > 1;
  bool get hasPrev => queue.length > 1;
  bool get playing => player.playing;
  PlayMode get repeat => _repeat;

  void cycleRepeat() {
    _repeat = PlayMode.values[(_repeat.index + 1) % PlayMode.values.length];
    _applyLoopMode();
    notifyListeners();
  }

  void _applyLoopMode() {
    player.setLoopMode(_repeat == PlayMode.repeatOne
        ? LoopMode.one
        : LoopMode.off);
  }

  /// 返回 (播放URL, 兜底命中的真实曲目元数据)。
  /// [xmusic] 2026-09-24：原实现只返回 URL——QQ vkey 失败兜底到网易云/酷我、
  /// 网易云 GDStudio 失败兜底到酷我时，播的是匹配到的另一首，但队列标题/歌手/专辑/
  /// 歌词源仍停留在原曲，导致"每日30首 歌名专辑与实际播放对不上、拖进度歌词对不上"。
  /// 现在兜底命中哪首就把哪首带回来，由 _loadAndPlay 同步队列元数据。
  Future<({String url, Song? resolved})> _mediaUrlForSong(Song s) async {
    const emptyRec = (url: '', resolved: null);
    if (s.streamUrl != null) return (url: s.streamUrl!, resolved: null);
    if (s.fromExternal) {
      final src = s.externalSource ?? 'netease';
      // B站/QQ/酷我走直连；网易云走GDStudio聚合（稳定）
      if (src == 'bilibili') {
        final url = await external.biliStreamUrl(s.id);
        return (url: url ?? '', resolved: null);
      }
      if (src == 'qq') {
        // vkey 直连受 IP/会员风控（2026 实测匿名/cookie 均拿不到 purl）：失败后并行兜底。
        // 并行：网易云(GDStudio) 与 酷我 同时尝试，先返回非空者先用，避免串行 60-90s 卡死。
        try {
          final url = await external
              .qqStreamUrl(s.id, cookie: settings.qqCookie)
              .timeout(const Duration(seconds: 8));
          if (url != null && url.isNotEmpty) return (url: url, resolved: null);
        } catch (_) {}
        final ne = () async {
          try {
            final m = await external
                .matchNetease(s.title, s.artist)
                .timeout(const Duration(seconds: 10));
            if (m == null) return emptyRec;
            final u = await external
                .streamUrlFor(m.id, source: 'netease')
                .timeout(const Duration(seconds: 10));
            if (u == null || u.isEmpty) return emptyRec;
            return (url: u, resolved: m);
          } catch (_) {
            return emptyRec;
          }
        };
        final kw = () async {
          try {
            final r = await external
                .matchKuwoMatched(s.title, s.artist)
                .timeout(const Duration(seconds: 15));
            if (r == null) return emptyRec;
            return (url: r.$1, resolved: r.$2);
          } catch (_) {
            return emptyRec;
          }
        };
        final f1 = ne();
        final f2 = kw();
        var fromF1 = false;
        final c1 = f1.then((v) {
          fromF1 = true;
          return v;
        });
        final c2 = f2.then((v) {
          fromF1 = false;
          return v;
        });
        final first = await Future.any([c1, c2]);
        if (first.url.isNotEmpty) return first;
        final other = await (fromF1 ? f2 : f1);
        if (other.url.isNotEmpty) return other;
        return first;
      }
      if (src == 'kuwo') {
        final url = await external
            .kuwoStreamUrl(s.id)
            .timeout(const Duration(seconds: 12));
        return (url: url ?? '', resolved: null);
      }
      // netease 等其余源：GDStudio 失败后加酷我兜底（每日30首等网易云匹配源）
      try {
        final u = await external
            .streamUrlFor(s.id, source: 'netease')
            .timeout(const Duration(seconds: 12));
        if (u != null && u.isNotEmpty) return (url: u, resolved: null);
      } catch (_) {}
      try {
        final r = await external
            .matchKuwoMatched(s.title, s.artist)
            .timeout(const Duration(seconds: 15));
        if (r != null) return (url: r.$1, resolved: r.$2);
      } catch (_) {}
      return emptyRec;
    }
    return (url: client.streamUrl(s.id).toString(), resolved: null);
  }

  /// 更新通知栏/锁屏显示的歌曲元数据。
  void _updateMediaItem(Song s) {
    try {
      Uri? art;
      if (s.coverUrl != null && s.coverUrl!.isNotEmpty) {
        art = Uri.tryParse(s.coverUrl!);
      } else if (s.coverArt != null) {
        art = client.coverUrl(s.coverArt!, size: 500);
      }
      audioHandler.setMediaItem(MediaItem(
        id: s.id,
        title: s.title,
        artist: s.artist,
        album: s.album,
        duration: s.durationSec != null ? Duration(seconds: s.durationSec!) : null,
        artUri: art,
      ));
    } catch (_) {}
  }

  /// 当前歌曲无封面时，自动按歌名+歌手搜索封面（网易云）。
  /// 搜索结果只取封面 URL，不改变歌曲音源/ID，避免串歌。
  Future<void> _autoFetchCover() async {
    final s = current;
    if (s == null) return;
    if ((s.coverUrl ?? '').isNotEmpty || (s.coverArt ?? '').isNotEmpty) return;
    final tk = ++_coverToken;
    try {
      final hit = await external.matchNetease(s.title, s.artist);
      if (hit == null || (hit.coverUrl ?? '').isEmpty) return;
      if (tk != _coverToken || index < 0 || index >= queue.length) return;
      final old = queue[index];
      if (old.id != s.id) return;
      final updated = Song(
        id: old.id,
        title: old.title,
        artist: old.artist,
        album: old.album,
        albumId: old.albumId,
        durationSec: old.durationSec,
        coverArt: old.coverArt,
        starred: old.starred,
        coverUrl: hit.coverUrl,
        streamUrl: old.streamUrl,
        fromExternal: old.fromExternal,
        externalSource: old.externalSource,
      );
      queue[index] = updated;
      _updateMediaItem(updated);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadAndPlay(int i, {bool autoplay = true}) async {
    if (i < 0 || i >= queue.length) return;
    // 车机识别：确保系统级 AudioService 就绪（首次 init 失败时播放前重试）。
    // 否则没有 MediaSession，车机桌面（迪友）枚举不到音素。
    await ensureSystemAudioHandler();
    final token = ++_playToken;
    final s = queue[i];
    // 外源歌兜底链较长，先置"加载中"，UI 显示加载反馈，避免用户以为点歌没反应
    loadingUrl = true;
    notifyListeners();
    String url;
    Song? resolved;
    try {
      final res = await _mediaUrlForSong(s);
      url = res.url;
      resolved = res.resolved;
    } finally {
      // 无论成功失败都复位加载态（成功由播放器缓冲态接管，失败由错误提示接管）
      if (token == _playToken) {
        loadingUrl = false;
        notifyListeners();
      }
    }
    if (token != _playToken) return; // 期间已切歌，放弃本次加载
    if (url.isEmpty) throw '无法获取播放地址';
    _updateMediaItem(s);
    await player.stop();
    // 等待player真正停止再加载新URL，防止双播
    try {
      await player.processingStateStream.firstWhere(
        (st) => st == ProcessingState.idle,
      ).timeout(const Duration(milliseconds: 1500));
    } catch (_) {}
    if (token != _playToken) return;
    await Future.delayed(const Duration(milliseconds: 200));
    if (token != _playToken) return;
    // B站音轨 CDN 需要 UA + Referer，否则 403/拒绝
    if (s.fromExternal && s.externalSource == 'bilibili') {
      await player.setUrl(url, headers: ExternalApi.biliPlayHeaders);
    } else {
      await player.setUrl(url);
    }
    if (token != _playToken) return;
    index = i;
    // [xmusic] 兜底换源命中真实曲目后，把队列项同步成"实际在播的这首歌"：
    // 标题/歌手/专辑/封面/歌词源一起换，否则界面和歌词还是原曲（每日30首错配根因）。
    if (resolved != null) {
      final rs = resolved!;
      queue[i] = Song(
        id: rs.id,
        title: rs.title,
        artist: rs.artist,
        album: rs.album,
        coverArt: rs.coverArt,
        coverUrl: rs.coverUrl,
        durationSec: rs.durationSec,
        fromExternal: true,
        externalSource: rs.externalSource,
      );
    }
    _updateMediaItem(queue[i]);
    notifyListeners();
    _applyLoopMode();
    _loadLyrics();
    // 开始播放时若歌曲无封面，自动按歌名+歌手搜索封面（网易云），成功后刷新播放页/通知栏
    unawaited(_autoFetchCover());
    if (autoplay) {
      await player.play();
    }
    // [xmusic] 2026-09-24 试听片段检测（用户反馈：排行榜/每日30首部分歌只有 11/30 秒）：
    // 酷我 /nf/ 试听已在 external_api.kuwoStreamUrl 拦截；这里兜底检测"声明时长>60s
    // 但实际可播时长<40s"的试听（如 QQ vkey 非会员 30s 试听），自动换 GDStudio 网易云完整版重播。
    if (s.fromExternal && (s.durationSec ?? 0) > 60 && token == _playToken) {
      try {
        await player.processingStateStream.firstWhere(
          (st) => st == ProcessingState.ready,
        ).timeout(const Duration(seconds: 8));
        final realDur = player.duration?.inSeconds ?? 0;
        if (realDur > 0 && realDur < 40 && token == _playToken) {
          // 试听确认：用歌名+歌手匹配网易云，GDStudio 对 VIP 歌实测也返回完整文件
          final m = await external
              .matchNetease(s.title, s.artist)
              .timeout(const Duration(seconds: 10));
          if (m != null && token == _playToken) {
            final u2 = await external
                .streamUrlFor(m.id, source: 'netease')
                .timeout(const Duration(seconds: 10));
            if (u2 != null && u2.isNotEmpty && token == _playToken) {
              // [xmusic] 2026-09-24 同步更新队列元数据为网易云匹配结果：
              // 换源重播后界面必须显示"实际在播的歌"（原实现只换 URL 不换标题/歌手/专辑，
              // 若匹配到同名不同版/翻唱，会出现播放与显示对不上号）。
              queue[i] = Song(
                id: m.id,
                title: m.title,
                artist: m.artist,
                album: m.album,
                coverArt: m.coverArt,
                coverUrl: m.coverUrl,
                durationSec: m.durationSec,
                fromExternal: true,
                externalSource: 'netease',
              );
              await player.stop();
              try {
                await player.processingStateStream.firstWhere(
                  (st) => st == ProcessingState.idle,
                ).timeout(const Duration(milliseconds: 1500));
              } catch (_) {}
              await player.setUrl(u2);
              index = i;
              notifyListeners();
              _applyLoopMode();
              _loadLyrics();
              if (autoplay) await player.play();
              unawaited(saveLastState());
            }
          }
        }
      } catch (_) {}
    }
    // 每次切歌/开始播放都保存最新状态（曲目+进度），
    // 退出或清后台后恢复的就是退出时正在播的歌，而不是停留在最初点开的那首。
    unawaited(saveLastState());
  }

  void _checkStuck() {
    if (!player.playing) return;
    if (player.processingState != ProcessingState.ready) return;
    final now = player.position;
    if (now == _prevStuckPos && now.inMilliseconds < 500) {
      unawaited(player.seek(Duration(milliseconds: 500)));
      unawaited(player.play());
    }
    _prevStuckPos = now;
  }

  Future<void> playQueue(List<Song> songs, int startIndex) async {
    queue = List.of(songs);
    index = startIndex;
    notifyListeners();
    try {
      await _loadAndPlay(startIndex, autoplay: true);
    } catch (e) {
      debugPrint('playQueue failed: $e');
      lastError = e.toString();
      notifyListeners();
    }
  }

  Future<void> enqueue(Song s) async {
    queue = List.of(queue)..add(s);
    notifyListeners();
  }

  Future<void> playAt(int i) async {
    if (i < 0 || i >= queue.length) return;
    try {
      await _loadAndPlay(i);
    } catch (e) { lastError = e.toString(); notifyListeners(); }
  }

  void _onCompleted() {
    if (_repeat == PlayMode.repeatOne) return;
    next();
  }

  void _playRandom() {
    if (queue.length <= 1) return;
    var ni = index;
    while (ni == index) { ni = _rnd.nextInt(queue.length); }
    unawaited(_loadAndPlay(ni));
  }

  Future<void> _loadLyrics() async {
    final s = current;
    if (s == null) return;
    final token = ++_loadToken;
    lyrics = null;
    lyricsLoading = true;
    notifyListeners();
    try {
      var result;
      final src = s.externalSource;
      if (src == 'qq') {
        // QQ直连歌词；无歌词时不再回退网易云（ID体系不同）
        result = await external.qqLyric(s.id);
      } else if (s.fromExternal) {
        // 用歌曲自己的音源查歌词；仅网易云源在无歌词时回退网易云
        // （其他音源的ID与网易云不一致，回退也是空查，反而拖慢刷新）
        result = await external.lyricFor(s.id, source: src ?? 'netease');
        if (src == 'netease' && (result == null || result.lines.isEmpty)) {
          result = await external.lyricFor(s.id, source: 'netease');
        }
      } else {
        // 本地文件歌：优先同目录 .lrc；其次 Navidrome 歌词；最后按歌名+歌手搜网易云兜底
        result = null;
        if ((s.streamUrl ?? '').startsWith('file://')) {
          try {
            final lrc = await LocalLibrary.lrcFor(s);
            if (lrc != null && lrc.trim().isNotEmpty) {
              result = Lyrics.fromLrc(lrc);
            }
          } catch (_) {}
        }
        result ??= await client.lyricsFor(s);
        if (result == null || result.lines.isEmpty) {
          try {
            final hits = await external
                .searchNeteaseDirect('${s.title} ${s.artist}', limit: 3);
            for (final cand in hits) {
              final lr = await external.lyricFor(cand.id, source: 'netease');
              if (lr != null && lr.lines.isNotEmpty) {
                result = lr;
                break;
              }
            }
          } catch (_) {}
        }
      }
      if (token != _loadToken) return;
      lyrics = (result == null || result.lines.isEmpty) ? null : result;
    } catch (e) {
      debugPrint('lyrics failed: $e');
    }
    lyricsLoading = false;
    notifyListeners();
  }

  void reloadLyrics() => _loadLyrics();

  // ---- 下载 ----

  Future<String> downloadSongToLocal(Song s) async {
    final url = (await _mediaUrlForSong(s)).url;
    if (url.isEmpty) return '无法获取下载地址';
    final bytes = await http.get(
      Uri.parse(url),
      headers: (s.fromExternal && s.externalSource == 'bilibili')
          ? ExternalApi.biliPlayHeaders
          : const {},
    );
    if (bytes.statusCode != 200) return '下载失败 HTTP ${bytes.statusCode}';
    // 优先使用用户配置的下载路径；未配置时回退到应用专属外部存储目录
    String base;
    if (settings.downloadPath.trim().isNotEmpty) {
      base = settings.downloadPath.trim();
    } else {
      base = (await getExternalStorageDirectory())?.path ??
          (await getApplicationDocumentsDirectory()).path;
    }
    final dir = Directory(base);
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
    } catch (_) {
      return '无法创建目录 $base，请在系统设置中授予存储权限';
    }
    final safe = _safeName('${s.artist} - ${s.title}');
    final file = File('${dir.path}/$safe.mp3');
    try {
      await file.writeAsBytes(bytes.bodyBytes);
    } catch (_) {
      return '保存失败：无写入权限，请授予存储权限后重试';
    }
    return '已保存到 ${file.path}';
  }

  Future<String> uploadSongToNas(Song s) async {
    if (!settings.webdavConfigured) return '未配置 NAS (WebDAV) 地址';
    final url = (await _mediaUrlForSong(s)).url;
    if (url.isEmpty) return '无法获取下载地址';
    final media = await http.get(Uri.parse(url));
    if (media.statusCode != 200) return '获取歌曲失败 HTTP ${media.statusCode}';
    final base = settings.webdavUrl.replaceAll(RegExp(r'/+$'), '');
    final sub = (settings.webdavPath.trim().isEmpty ? 'Music/xmusic' : settings.webdavPath.trim()).replaceAll(RegExp(r'^/|/$'), '');
    final path = '$base/$sub/${_safeName("${s.artist} - ${s.title}")}.mp3';
    final auth = '${settings.webdavUser}:${settings.webdavPass}';
    final encoded = base64Encode(utf8.encode(auth));
    final resp = await http.put(
      Uri.parse(path),
      headers: {
        'Authorization': 'Basic $encoded',
        'Content-Type': 'audio/mpeg',
      },
      body: media.bodyBytes,
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return '已上传到 NAS: $path';
    }
    return 'NAS 上传失败 HTTP ${resp.statusCode}';
  }

  Future<String> downloadCurrentToLocal() async {
    final s = current;
    if (s == null) return '没有正在播放的歌曲';
    return downloadSongToLocal(s);
  }

  Future<String> uploadCurrentToNas() async {
    final s = current;
    if (s == null) return '没有正在播放的歌曲';
    return uploadSongToNas(s);
  }

  static String _safeName(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  Future<void> next() async {
    if (_repeat == PlayMode.shuffle) { _playRandom(); return; }
    if (queue.isEmpty) return;
    // [xmusic] 切歌治本：外源歌（QQ/B站）地址解析失败时自动跳过，不再卡在旧歌
    final n = queue.length;
    var i = (index + 1) % n;
    for (var tried = 0; tried < n; tried++) {
      try {
        await _loadAndPlay(i);
        return;
      } catch (_) {
        i = (i + 1) % n;
      }
    }
    lastError = '队列内歌曲均无法播放';
    notifyListeners();
  }

  Future<void> previous() async {
    if (player.position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
      return;
    }
    if (queue.isEmpty) return;
    final n = queue.length;
    var i = index <= 0 ? n - 1 : index - 1;
    for (var tried = 0; tried < n; tried++) {
      try {
        await _loadAndPlay(i);
        return;
      } catch (_) {
        i = i <= 0 ? n - 1 : i - 1;
      }
    }
    lastError = '队列内歌曲均无法播放';
    notifyListeners();
  }

  void togglePlay() {
    if (player.playing) {
      unawaited(player.pause());
    } else {
      audioHandler.allowPlay = true;
      unawaited(player.play());
    }
  }

  bool get currentStarred => current?.starred ?? false;

  Future<void> toggleStar() async {
    final s = current;
    if (s == null) return;
    final nowStarred = !s.starred;
    queue[index] = Song(
      id: s.id,
      title: s.title,
      artist: s.artist,
      album: s.album,
      albumId: s.albumId,
      durationSec: s.durationSec,
      coverArt: s.coverArt,
      starred: nowStarred,
      coverUrl: s.coverUrl,
      streamUrl: s.streamUrl,
      fromExternal: s.fromExternal,
      externalSource: s.externalSource,
    );
    notifyListeners();
    if (s.fromExternal) return;
    try {
      if (nowStarred) {
        await client.starSong(s.id);
      } else {
        await client.unstarSong(s.id);
      }
    } catch (e) {
      debugPrint('star toggle failed: $e');
    }
  }

  @override
  void dispose() {
    _completedSub.cancel();
    _playingSub.cancel();
    _positionSub.cancel();
    _stuckTimer.cancel();
    super.dispose();
  }
}
