import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';

import 'external_api.dart';
import 'lyrics.dart';
import 'settings.dart';
import 'subsonic.dart';

/// Playback mode: sequential, shuffle or repeat-one.
enum PlayMode { sequential, shuffle, repeatOne }

/// Owns the audio player, the play queue and the current song's lyrics.
///
/// 每首歌用 AudioSource.uri + MediaItem tag 装载（元数据同步到车机/通知栏），
/// 切歌时重建音源。带卡住自动恢复：playing=true 但位置长时间不动会强制重启播放。
class PlayerController extends ChangeNotifier {
  PlayerController(this.client, this.settings) {
    _idxSub = player.currentIndexStream.listen((i) {
      if (i != null && i != index) {
        index = i;
        _loadLyrics();
      }
    });
    _completedSub = player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) _onCompleted();
    });
    _playingSub = player.playingStream.listen((_) => notifyListeners());
    _positionSub = player.positionStream.listen((pos) {
      _lastPos = pos;
      _lastPosTime = DateTime.now();
    });
    _stuckTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkStuck());
  }

  final SubsonicClient client;
  final AppSettings settings;
  final AudioPlayer player = AudioPlayer();

  ExternalApi get external => ExternalApi(settings.externalApiUrl);

  List<Song> queue = const [];
  int index = -1;
  Lyrics? lyrics;
  bool lyricsLoading = false;
  PlayMode _repeat = PlayMode.sequential;
  final Random _rnd = Random();

  late final StreamSubscription<int?> _idxSub;
  late final StreamSubscription<ProcessingState> _completedSub;
  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<Duration> _positionSub;
  late final Timer _stuckTimer;
  Duration _lastPos = Duration.zero;
  DateTime _lastPosTime = DateTime.now();
  int _loadToken = 0;
  String? lastError;
  /// 上次检查时的位置，用于判断是否卡住。
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
          'fromExternal': s.fromExternal,
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
        fromExternal: e['fromExternal'] ?? false,
      )).toList();
      index = (m['index'] as int?) ?? 0;
      if (index >= queue.length) index = 0;
      notifyListeners();
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
      return (await external.streamUrlFor(s.id)) ?? '';
    }
    return client.streamUrl(s.id).toString();
  }

  Uri? _artUriFor(Song s) {
    if (s.coverUrl != null && s.coverUrl!.isNotEmpty) {
      return Uri.tryParse(s.coverUrl!);
    }
    return client.coverUrl(s.coverArt, size: 500);
  }

  /// 装载第 i 首歌并播放。带 MediaItem 元数据，系统 MediaSession 能同步歌名/封面。
  Future<void> _loadAndPlay(int i, {bool autoplay = true}) async {
    if (i < 0 || i >= queue.length) return;
    final s = queue[i];
    final url = await _mediaUrlForSong(s);
    if (url.isEmpty) throw '无法获取播放地址';
    await player.setAudioSource(
      AudioSource.uri(
        Uri.parse(url),
        tag: MediaItem(
          id: s.id,
          title: s.title,
          artist: s.artist,
          album: s.album,
          duration:
              s.durationSec != null ? Duration(seconds: s.durationSec!) : null,
          artUri: _artUriFor(s),
        ),
      ),
      initialPosition: Duration.zero,
    );
    index = i;
    notifyListeners();
    _applyLoopMode();
    if (autoplay) await player.play();
    _loadLyrics();
  }

  /// 卡住检测：playing=true 且连续 6 秒位置没动，强制回到开头重放。
  void _checkStuck() {
    if (!player.playing) return;
    if (player.processingState != ProcessingState.ready) return;
    final now = player.position;
    if (now == _prevStuckPos && now.inMilliseconds < 500) {
      // 位置长时间停在 0，强制 seek+play
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

  /// Append [s] to the end of the play queue (enqueue).
  Future<void> enqueue(Song s) async {
    queue = List.of(queue)..add(s);
    notifyListeners();
  }

  /// Play the queue item at [i] (same queue, new index).
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
          ? await external.lyricFor(s.id)
          : await client.lyricsFor(s);
      if (token != _loadToken) return;
      lyrics = (result == null || result.lines.isEmpty) ? null : result;
    } catch (e) {
      debugPrint('lyrics failed: $e');
    }
    lyricsLoading = false;
    notifyListeners();
  }

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
    _idxSub.cancel();
    _completedSub.cancel();
    _playingSub.cancel();
    _stuckTimer.cancel();
    player.dispose();
    super.dispose();
  }
}
