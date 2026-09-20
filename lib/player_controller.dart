import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'lyrics.dart';
import 'subsonic.dart';

/// Owns the audio player, the play queue and the current song's lyrics.
class PlayerController extends ChangeNotifier {
  PlayerController(this.client) {
    _stateSub = player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) next();
    });
    _playingSub = player.playingStream.listen((_) => notifyListeners());
  }

  final SubsonicClient client;
  final AudioPlayer player = AudioPlayer();

  List<Song> queue = const [];
  int index = -1;
  Lyrics? lyrics;
  bool lyricsLoading = false;

  late final StreamSubscription<ProcessingState> _stateSub;
  late final StreamSubscription<bool> _playingSub;
  int _loadToken = 0;

  Song? get current =>
      (index >= 0 && index < queue.length) ? queue[index] : null;
  bool get hasNext => index + 1 < queue.length;
  bool get hasPrev => index > 0;
  bool get playing => player.playing;

  Future<void> playQueue(List<Song> songs, int startIndex) async {
    queue = List.of(songs);
    await _load(startIndex);
  }

  /// Play the queue item at [i] (same queue, new index).
  Future<void> playAt(int i) async {
    if (i < 0 || i >= queue.length) return;
    await _load(i);
  }

  Future<void> _load(int i) async {
    final song = queue[i];
    final token = ++_loadToken;
    index = i;
    lyrics = null;
    lyricsLoading = true;
    notifyListeners();

    // Fetch lyrics in parallel with starting playback.
    final lyricsFuture = client.lyricsFor(song);

    try {
      await player.setUrl(client.streamUrl(song.id).toString());
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
    if (hasNext) {
      await _load(index + 1);
    } else {
      await player.pause();
      await player.seek(Duration.zero);
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
