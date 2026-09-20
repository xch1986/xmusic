import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'external_api.dart';
import 'lyrics.dart';
import 'settings.dart';
import 'subsonic.dart';

/// Playback mode: sequential, shuffle or repeat-one.
enum PlayMode { sequential, shuffle, repeatOne }

/// Owns the audio player, the play queue and the current song's lyrics.
///
/// The queue is handed to just_audio as a [ConcatenatingAudioSource], so the
/// system media notification and lock-screen controls work natively, playback
/// continues in the background, and next/prev buttons are handled by the
/// platform itself.
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
  int _loadToken = 0;

  Song? get current =>
      (index >= 0 && index < queue.length) ? queue[index] : null;
  bool get hasNext => player.hasNext;
  bool get hasPrev => player.hasPrevious;
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

  Future<void> playQueue(List<Song> songs, int startIndex) async {
    queue = List.of(songs);
    index = startIndex;
    notifyListeners();

    final children = <AudioSource>[];
    for (final s in songs) {
      final url = s.streamUrl ?? client.streamUrl(s.id).toString();
      final cover = s.coverUrl != null
          ? Uri.tryParse(s.coverUrl!)
          : client.coverUrl(s.coverArt, size: 500);
      children.add(AudioSource.uri(
        Uri.parse(url),
        tag: MediaItem(
          id: s.id,
          title: s.title,
          album: s.album,
          artist: s.artist,
          artUri: cover,
        ),
      ));
    }
    try {
      await player.setAudioSource(
        ConcatenatingAudioSource(children: children),
        initialIndex: startIndex,
      );
      _applyLoopMode();
      await player.play();
      _loadLyrics();
    } catch (e) {
      debugPrint('playQueue failed: $e');
    }
  }

  /// Play the queue item at [i] (same queue, new index).
  Future<void> playAt(int i) async {
    if (i < 0 || i >= queue.length) return;
    await player.seek(Duration.zero, index: i);
  }

  void _onCompleted() {
    // With LoopMode.one, just_audio repeats the current track itself.
    if (_repeat == PlayMode.repeatOne) return;
    if (_repeat == PlayMode.shuffle) {
      _playRandom();
    }
    // sequential: just_audio stops at the end of the list (no-op needed).
  }

  void _playRandom() {
    if (queue.length <= 1) return;
    var nextIndex = index;
    while (nextIndex == index) {
      nextIndex = _rnd.nextInt(queue.length);
    }
    unawaited(player.seek(Duration.zero, index: nextIndex));
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

  /// Resolve the direct media URL of [s] (external: already resolved in
  /// song.streamUrl; local: via the Subsonic stream endpoint).
  Future<String?> _mediaUrlFor(Song s) async {
    if (s.streamUrl != null) return s.streamUrl;
    if (s.fromExternal) {
      return external.streamUrlFor(s.id);
    }
    return client.streamUrl(s.id).toString();
  }

  /// Download the current song to shared external storage (Downloads).
  Future<String> downloadCurrentToLocal() async {
    final s = current;
    if (s == null) return '没有正在播放的歌曲';
    final url = await _mediaUrlFor(s);
    if (url == null) return '无法获取下载地址';
    final bytes = await http.get(Uri.parse(url));
    if (bytes.statusCode != 200) return '下载失败 HTTP ${bytes.statusCode}';
    final dir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final safe = _safeName('${s.artist} - ${s.title}');
    final file = File('${dir.path}/$safe.mp3');
    await file.writeAsBytes(bytes.bodyBytes);
    return '已保存到 ${file.path}';
  }

  /// Upload the current song to the configured WebDAV (NAS) server.
  Future<String> uploadCurrentToNas() async {
    final s = current;
    if (s == null) return '没有正在播放的歌曲';
    if (!settings.webdavConfigured) return '未配置 NAS (WebDAV) 地址';
    final url = await _mediaUrlFor(s);
    if (url == null) return '无法获取下载地址';
    final media = await http.get(Uri.parse(url));
    if (media.statusCode != 200) return '获取歌曲失败 HTTP ${media.statusCode}';

    final base = settings.webdavUrl.replaceAll(RegExp(r'/+$'), '');
    final path = '$base/${_safeName("${s.artist} - ${s.title}")}.mp3';
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

  static String _safeName(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  Future<void> next() async {
    if (_repeat == PlayMode.shuffle) {
      _playRandom();
    } else {
      await player.seekToNext();
    }
  }

  Future<void> previous() async {
    if (player.position > const Duration(seconds: 3) || !hasPrev) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
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
    player.dispose();
    super.dispose();
  }
}
