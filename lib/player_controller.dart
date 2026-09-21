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
import 'main.dart';
import 'settings.dart';
import 'subsonic.dart';

/// Playback mode: sequential, shuffle or repeat-one.
enum PlayMode { sequential, shuffle, repeatOne }

/// Owns the audio player, the play queue and the current song's lyrics.
class PlayerController extends ChangeNotifier {
  PlayerController(this.client, this.settings) {
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
  }

  final SubsonicClient client;
  final AppSettings settings;
  AudioPlayer get player => audioHandler.player;

  ExternalApi get external => ExternalApi(settings.externalApiUrl);

  List<Song> queue = const [];
  int index = -1;
  Lyrics? lyrics;
  bool lyricsLoading = false;
  PlayMode _repeat = PlayMode.sequential;
  final Random _rnd = Random();

  late final StreamSubscription<ProcessingState> _completedSub;
  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<Duration> _positionSub;
  late final Timer _stuckTimer;
  Duration _lastPos = Duration.zero;
  DateTime _lastPosTime = DateTime.now();
  int _loadToken = 0;
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
      try {
        await _loadAndPlay(index, autoplay: settings.autoPlay);
      } catch (_) {}
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

  Future<String> _mediaUrlForSong(Song s) async {
    if (s.streamUrl != null) return s.streamUrl!;
    if (s.fromExternal) {
      return (await external.streamUrlFor(s.id, source: s.externalSource ?? 'qq')) ?? '';
    }
    return client.streamUrl(s.id).toString();
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

  Future<void> _loadAndPlay(int i, {bool autoplay = true}) async {
    if (i < 0 || i >= queue.length) return;
    final s = queue[i];
    final url = await _mediaUrlForSong(s);
    if (url.isEmpty) throw '无法获取播放地址';
    _updateMediaItem(s);
    await player.stop();
    await player.setUrl(url);
    index = i;
    notifyListeners();
    _applyLoopMode();
    if (autoplay) await player.play();
    _loadLyrics();
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
      saveLastState();
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
      final result = s.fromExternal
          ? await external.lyricFor(s.id, source: s.externalSource ?? 'qq')
          : await client.lyricsFor(s);
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
    final url = await _mediaUrlForSong(s);
    if (url.isEmpty) return '无法获取下载地址';
    final bytes = await http.get(Uri.parse(url));
    if (bytes.statusCode != 200) return '下载失败 HTTP ${bytes.statusCode}';
    final dir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final safe = _safeName('${s.artist} - ${s.title}');
    final file = File('${dir.path}/$safe.mp3');
    await file.writeAsBytes(bytes.bodyBytes);
    return '已保存到 ${file.path}';
  }

  Future<String> uploadSongToNas(Song s) async {
    if (!settings.webdavConfigured) return '未配置 NAS (WebDAV) 地址';
    final url = await _mediaUrlForSong(s);
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
    try {
      await _loadAndPlay((index + 1) % queue.length);
    } catch (e) { lastError = e.toString(); notifyListeners(); }
  }

  Future<void> previous() async {
    if (player.position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
      return;
    }
    if (queue.isEmpty) return;
    try {
      await _loadAndPlay(index <= 0 ? queue.length - 1 : index - 1);
    } catch (e) { lastError = e.toString(); notifyListeners(); }
  }

  void togglePlay() {
    if (player.playing) {
      unawaited(player.pause());
    } else {
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
