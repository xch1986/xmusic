import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'lyrics.dart';
import 'subsonic.dart';

/// Playback mode: sequential, shuffle or repeat-one.
enum PlayMode { sequential, shuffle, repeatOne }

/// Owns the audio player, the play queue and the current song's lyrics.
class PlayerController extends ChangeNotifier {
  PlayerController(this.client) {
    _stateSub = player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) _onCompleted();
    });
    _playingSub = player.playingStream.listen((_) => notifyListeners());
  }

  final SubsonicClient client;
  final AudioPlayer player = AudioPlayer();

  List<Song> queue = const [];
  int index = -1;
  Lyrics? lyrics;
  bool lyricsLoading = false;
  PlayMode _repeat = PlayMode.sequential;
  final Random _rnd = Random();

  late final StreamSubscription<ProcessingState> _stateSub;
  late final StreamSubscription<bool> _playingSub;
  int _loadToken = 0;

  Song? get current =>
      (index >= 0 && index < queue.length) ? queue[index] : null;
  bool get hasNext => index + 1 < queue.length;
  bool get hasPrev => index > 0;
  bool get playing => player.playing;
  PlayMode get repeat => _repeat;

  void cycleRepeat() {
    _repeat = PlayMode.values[(_repeat.index + 1) % PlayMode.values.length];
    notifyListeners();
  }

  Future<void> playQueue(List<Song> songs, int startIndex) async {
    queue = List.of(songs);
    await _load(startIndex);
  }

  /// Play the queue item at [i] (same queue, new index).
  Future<void> playAt(int i) async {
    if (i < 0 || i >= queue.length) return;
    await _load(i);
  }

  void _onCompleted() {
    switch (_repeat) {
      case PlayMode.repeatOne:
        unawaited(player.seek(Duration.zero));
        unawaited(player.play());
        break;
      case PlayMode.sequential:
        unawaited(next());
        break;
      case PlayMode.shuffle:
        _playRandom();
        break;
    }
  }

  void _playRandom() {
    if (queue.isEmpty) return;
    if (queue.length == 1) {
      unawaited(player.seek(Duration.zero));
      unawaited(player.play());
      return;
    }
    var nextIndex = index;
    while (nextIndex == index) {
      nextIndex = _rnd.nextInt(queue.length);
    }
    unawaited(_load(nextIndex));
  }

  Future<void> _load(int i) async {
    if (i < 0 || i >= queue.length) return;
    final song = queue[i];
    final token = ++_loadToken;
    index = i;
    lyrics = null;
    lyricsLoading = true;
    notifyListeners();

    // Fetch lyrics in parallel with starting playback.
    final lyricsFuture = client.lyricsFor(song);

    try {
      final url = song.streamUrl ?? client.streamUrl(song.id).toString();
      await player.setUrl(url);
      unawaited(player.play());
    } catch (e) {
      debugPrint('Playback failed: $e');
    }

    final result = await lyricsFuture;
    if (token != _loadToken) return; // user already skipped to another song
    lyrics = (result == null || result.lines.isEmpty) ? null : result;
    lyricsLoading = false;
    notifyListeners();
  }

  Future<void> next() async {
    switch (_repeat) {
      case PlayMode.shuffle:
        _playRandom();
        break;
      case PlayMode.repeatOne:
        await player.seek(Duration.zero);
        await player.play();
        break;
      case PlayMode.sequential:
        if (hasNext) {
          await _load(index + 1);
        } else {
          await player.pause();
          await player.seek(Duration.zero);
        }
        break;
    }
  }

  Future<void> previous() async {
    if (player.position > const Duration(seconds: 3) || !hasPrev) {
      await player.seek(Duration.zero);
    } else {
      await _load(index - 1);
    }
  }

  void togglePlay() {
    if (player.playing) {
      unawaited(player.pause());
    } else {
      unawaited(player.play());
    }
  }

  @override
  void dispose() {
    _stateSub.cancel();
    _playingSub.cancel();
    player.dispose();
    super.dispose();
  }
}
