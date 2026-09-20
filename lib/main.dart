import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ===== lyrics.dart =====
class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

class Lyrics {
  const Lyrics(this.lines, {required this.synced});

  final List<LyricLine> lines;

  /// True when every line carries a timestamp (LRC / OpenSubsonic synced).
  final bool synced;

  /// Index of the line being sung at [position], or -1 before the first line.
  int indexAt(Duration position) {
    if (!synced || lines.isEmpty) return -1;
    var lo = 0, hi = lines.length - 1, answer = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].time <= position) {
        answer = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return answer;
  }

  static final _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  static final _metaTag = RegExp(r'^\[[A-Za-z]+:.*\]$');

  /// Parses LRC text. Falls back to plain (unsynced) lines when no timestamps
  /// are present.
  static Lyrics fromLrc(String raw) {
    final timed = <LyricLine>[];
    final plain = <LyricLine>[];

    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final matches = _timeTag.allMatches(line).toList();
      final text = line.replaceAll(_timeTag, '').trim();

      if (matches.isEmpty) {
        if (_metaTag.hasMatch(line.trim())) continue; // [ar:...], [ti:...]
        if (text.isNotEmpty) plain.add(LyricLine(Duration.zero, text));
        continue;
      }

      for (final m in matches) {
        final frac = m.group(3);
        final ms =
            frac == null ? 0 : int.parse(frac.padRight(3, '0').substring(0, 3));
        timed.add(LyricLine(
          Duration(
            minutes: int.parse(m.group(1)!),
            seconds: int.parse(m.group(2)!),
            milliseconds: ms,
          ),
          text,
        ));
      }
    }

    if (timed.isNotEmpty) {
      timed.sort((a, b) => a.time.compareTo(b.time));
      return Lyrics(timed, synced: true);
    }
    return Lyrics(plain, synced: false);
  }
}

// ===== subsonic.dart =====
class SubsonicException implements Exception {
  SubsonicException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Album {
  const Album({
    required this.id,
    required this.name,
    required this.artist,
    this.coverArt,
  });

  final String id;
  final String name;
  final String artist;
  final String? coverArt;

  factory Album.fromJson(Map<String, dynamic> j) => Album(
        id: j['id'].toString(),
        name: (j['name'] ?? j['title'] ?? '').toString(),
        artist: (j['artist'] ?? '').toString(),
        coverArt: j['coverArt']?.toString(),
      );
}

class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.durationSec,
    this.coverArt,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final int? durationSec;
  final String? coverArt;

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        id: j['id'].toString(),
        title: (j['title'] ?? '').toString(),
        artist: (j['artist'] ?? '').toString(),
        album: (j['album'] ?? '').toString(),
        durationSec: (j['duration'] as num?)?.toInt(),
        coverArt: j['coverArt']?.toString(),
      );
}

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.songCount,
    this.coverArt,
  });

  final String id;
  final String name;
  final int songCount;
  final String? coverArt;

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        songCount: (j['songCount'] as num?)?.toInt() ?? 0,
        coverArt: j['coverArt']?.toString(),
      );
}

class SearchResult {
  const SearchResult(this.albums, this.songs);
  final List<Album> albums;
  final List<Song> songs;
  bool get isEmpty => albums.isEmpty && songs.isEmpty;
}

/// Minimal Subsonic / OpenSubsonic client (works with Navidrome).
class SubsonicClient {
  SubsonicClient({
    required String baseUrl,
    required this.username,
    required this.salt,
    required this.token,
  }) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');

  final String baseUrl;
  final String username;
  final String salt;
  final String token;

  static String makeToken(String password, String salt) =>
      md5.convert(utf8.encode(password + salt)).toString();

  static String randomSalt([int length = 12]) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)])
        .join();
  }

  Uri _uri(String method, [Map<String, Object> extra = const {}]) {
    return Uri.parse('$baseUrl/rest/$method').replace(queryParameters: {
      'u': username,
      't': token,
      's': salt,
      'v': '1.16.1',
      'c': 'my_stream_player',
      'f': 'json',
      ...extra,
    });
  }

  Future<Map<String, dynamic>> _get(String method,
      [Map<String, Object> extra = const {}]) async {
    final res = await http.get(_uri(method, extra));
    if (res.statusCode != 200) {
      throw SubsonicException('HTTP ${res.statusCode}');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final root = body['subsonic-response'] as Map<String, dynamic>;
    if (root['status'] != 'ok') {
      final err = root['error'] as Map<String, dynamic>?;
      throw SubsonicException((err?['message'] ?? 'Unknown error').toString());
    }
    return root;
  }

  Future<void> ping() => _get('ping');

  /// [type]: newest, random, frequent, recent, alphabeticalByName, ...
  Future<List<Album>> albumList(String type,
      {int size = 20, int offset = 0}) async {
    final root = await _get('getAlbumList2', {
      'type': type,
      'size': '$size',
      'offset': '$offset',
    });
    final list = (root['albumList2']?['album'] as List?) ?? const [];
    return list.map((e) => Album.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Album>> newestAlbums({int size = 60, int offset = 0}) =>
      albumList('newest', size: size, offset: offset);

  Future<List<Song>> randomSongs({int size = 20}) async {
    final root = await _get('getRandomSongs', {'size': '$size'});
    return _list(root['randomSongs']?['song'], Song.fromJson);
  }

  Future<List<Song>> albumSongs(String albumId) async {
    final root = await _get('getAlbum', {'id': albumId});
    final list = (root['album']?['song'] as List?) ?? const [];
    return list.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
  }

  static List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
      ((v as List?) ?? const [])
          .map((e) => f(e as Map<String, dynamic>))
          .toList();

  Future<SearchResult> search(String query) async {
    final root = await _get('search3', {
      'query': query,
      'artistCount': '0',
      'albumCount': '20',
      'songCount': '50',
    });
    final r = root['searchResult3'];
    return SearchResult(
      _list(r?['album'], Album.fromJson),
      _list(r?['song'], Song.fromJson),
    );
  }

  Future<SearchResult> starred() async {
    final root = await _get('getStarred2');
    final r = root['starred2'];
    return SearchResult(
      _list(r?['album'], Album.fromJson),
      _list(r?['song'], Song.fromJson),
    );
  }

  Future<void> star({String? songId, String? albumId}) => _get('star', {
        if (songId != null) 'id': songId,
        if (albumId != null) 'albumId': albumId,
      });

  Future<void> unstar({String? songId, String? albumId}) => _get('unstar', {
        if (songId != null) 'id': songId,
        if (albumId != null) 'albumId': albumId,
      });

  Future<List<Playlist>> playlists() async {
    final root = await _get('getPlaylists');
    return _list(root['playlists']?['playlist'], Playlist.fromJson);
  }

  Future<List<Song>> playlistSongs(String playlistId) async {
    final root = await _get('getPlaylist', {'id': playlistId});
    return _list(root['playlist']?['entry'], Song.fromJson);
  }

  Future<void> createPlaylist(String name,
          {List<String> songIds = const []}) =>
      _get('createPlaylist', {
        'name': name,
        if (songIds.isNotEmpty) 'songId': songIds,
      });

  Future<void> addToPlaylist(String playlistId, List<String> songIds) =>
      _get('updatePlaylist', {
        'playlistId': playlistId,
        'songIdToAdd': songIds,
      });

  Future<void> removeFromPlaylist(String playlistId, int index) =>
      _get('updatePlaylist', {
        'playlistId': playlistId,
        'songIndexToRemove': '$index',
      });

  Future<void> renamePlaylist(String playlistId, String name) =>
      _get('updatePlaylist', {'playlistId': playlistId, 'name': name});

  Future<void> deletePlaylist(String playlistId) =>
      _get('deletePlaylist', {'id': playlistId});

  Uri streamUrl(String songId) => _uri('stream', {'id': songId});

  Uri? coverUrl(String? coverId, {int size = 600}) {
    if (coverId == null || coverId.isEmpty) return null;
    return _uri('getCoverArt', {'id': coverId, 'size': '$size'});
  }

  /// Tries OpenSubsonic `getLyricsBySongId` first, then classic `getLyrics`.
  Future<Lyrics?> lyricsFor(Song song) async {
    try {
      final root = await _get('getLyricsBySongId', {'id': song.id});
      final list = (root['lyricsList']?['structuredLyrics'] as List?) ?? const [];
      if (list.isNotEmpty) {
        final maps = list.cast<Map<String, dynamic>>();
        final pick = maps.firstWhere(
          (m) => m['synced'] == true,
          orElse: () => maps.first,
        );
        final synced = pick['synced'] == true;
        final lines = ((pick['line'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map((l) => LyricLine(
                  Duration(milliseconds: (l['start'] as num?)?.toInt() ?? 0),
                  (l['value'] ?? '').toString(),
                ))
            .toList();
        if (lines.isNotEmpty) return Lyrics(lines, synced: synced);
      }
    } catch (_) {
      // Server may not support the OpenSubsonic endpoint; fall through.
    }

    try {
      final root = await _get('getLyrics', {
        'artist': song.artist,
        'title': song.title,
      });
      final text = root['lyrics']?['value']?.toString() ?? '';
      if (text.trim().isNotEmpty) return Lyrics.fromLrc(text);
    } catch (_) {}

    return null;
  }
}

// ===== settings.dart =====
/// How the queue advances. (Named PlayMode on purpose — RepeatMode clashes.)
enum PlayMode { sequential, shuffle, repeatOne }

/// App-wide persisted settings: login info and the lyric size scale.
///
/// The password is never stored. On login we derive a Subsonic salt + token
/// (md5(password + salt)) and keep only those.
class AppSettings extends ChangeNotifier {
  static const double minScale = 0.7;
  static const double maxScale = 2.0;
  static const double scaleStep = 0.1;

  static const _kScale = 'lyric_scale';
  static const _kUrl = 'server_url';
  static const _kUser = 'username';
  static const _kSalt = 'salt';
  static const _kToken = 'token';
  static const _kTheme = 'theme_mode';
  static const _kPlayMode = 'play_mode';

  late final SharedPreferences _prefs;

  String serverUrl = '';
  String username = '';
  String salt = '';
  String token = '';
  double _lyricScale = 1.0;
  ThemeMode _themeMode = ThemeMode.system;
  PlayMode _playMode = PlayMode.sequential;

  ThemeMode get themeMode => _themeMode;
  PlayMode get playMode => _playMode;

  double get lyricScale => _lyricScale;
  bool get canIncreaseLyric => _lyricScale < maxScale - 1e-9;
  bool get canDecreaseLyric => _lyricScale > minScale + 1e-9;

  bool get hasLogin =>
      serverUrl.isNotEmpty &&
      username.isNotEmpty &&
      salt.isNotEmpty &&
      token.isNotEmpty;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    serverUrl = _prefs.getString(_kUrl) ?? '';
    username = _prefs.getString(_kUser) ?? '';
    salt = _prefs.getString(_kSalt) ?? '';
    token = _prefs.getString(_kToken) ?? '';
    _lyricScale =
        (_prefs.getDouble(_kScale) ?? 1.0).clamp(minScale, maxScale).toDouble();
    final theme = _prefs.getString(_kTheme);
    _themeMode = ThemeMode.values
        .firstWhere((m) => m.name == theme, orElse: () => ThemeMode.system);
    final mode = _prefs.getString(_kPlayMode);
    _playMode = PlayMode.values
        .firstWhere((m) => m.name == mode, orElse: () => PlayMode.sequential);
  }

  SubsonicClient buildClient() => SubsonicClient(
        baseUrl: serverUrl,
        username: username,
        salt: salt,
        token: token,
      );

  Future<void> saveLogin(SubsonicClient client) async {
    serverUrl = client.baseUrl;
    username = client.username;
    salt = client.salt;
    token = client.token;
    await _prefs.setString(_kUrl, serverUrl);
    await _prefs.setString(_kUser, username);
    await _prefs.setString(_kSalt, salt);
    await _prefs.setString(_kToken, token);
    notifyListeners();
  }

  Future<void> clearLogin() async {
    salt = '';
    token = '';
    await _prefs.remove(_kSalt);
    await _prefs.remove(_kToken);
    notifyListeners();
  }

  Future<void> setLyricScale(double value) async {
    final next = (value.clamp(minScale, maxScale) * 10).round() / 10;
    if (next == _lyricScale) return;
    _lyricScale = next;
    notifyListeners();
    await _prefs.setDouble(_kScale, next);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _prefs.setString(_kTheme, mode.name);
  }

  Future<void> setPlayMode(PlayMode mode) async {
    if (mode == _playMode) return;
    _playMode = mode;
    notifyListeners();
    await _prefs.setString(_kPlayMode, mode.name);
  }

  void increaseLyric() => setLyricScale(_lyricScale + scaleStep);
  void decreaseLyric() => setLyricScale(_lyricScale - scaleStep);
}

// ===== library_state.dart =====
/// Server-side user data: favorites (starred songs/albums) and playlists.
/// Changes are applied optimistically where it makes sense.
class LibraryState extends ChangeNotifier {
  LibraryState(this.client);

  final SubsonicClient client;

  final Set<String> _songIds = {};
  final Set<String> _albumIds = {};
  List<Song> starredSongs = const [];
  List<Album> starredAlbums = const [];
  List<Playlist> playlists = const [];
  bool loading = false;
  String? error;
  bool _disposed = false;

  bool isSongStarred(String id) => _songIds.contains(id);
  bool isAlbumStarred(String id) => _albumIds.contains(id);

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final starred = await client.starred();
      final lists = await client.playlists();
      starredSongs = starred.songs;
      starredAlbums = starred.albums;
      playlists = lists;
      _songIds
        ..clear()
        ..addAll(starred.songs.map((s) => s.id));
      _albumIds
        ..clear()
        ..addAll(starred.albums.map((a) => a.id));
    } catch (e) {
      error = '$e';
    }
    loading = false;
    notifyListeners();
  }

  // ---- favorites ---------------------------------------------------------

  void _applySong(Song s, bool starred) {
    if (starred) {
      _songIds.add(s.id);
      starredSongs = [s, ...starredSongs.where((x) => x.id != s.id)];
    } else {
      _songIds.remove(s.id);
      starredSongs = starredSongs.where((x) => x.id != s.id).toList();
    }
  }

  void _applyAlbum(Album a, bool starred) {
    if (starred) {
      _albumIds.add(a.id);
      starredAlbums = [a, ...starredAlbums.where((x) => x.id != a.id)];
    } else {
      _albumIds.remove(a.id);
      starredAlbums = starredAlbums.where((x) => x.id != a.id).toList();
    }
  }

  /// Returns false (and rolls back) if the server call fails.
  Future<bool> toggleSongStar(Song song) async {
    final was = isSongStarred(song.id);
    _applySong(song, !was);
    notifyListeners();
    try {
      if (was) {
        await client.unstar(songId: song.id);
      } else {
        await client.star(songId: song.id);
      }
      return true;
    } catch (_) {
      _applySong(song, was);
      notifyListeners();
      return false;
    }
  }

  Future<bool> toggleAlbumStar(Album album) async {
    final was = isAlbumStarred(album.id);
    _applyAlbum(album, !was);
    notifyListeners();
    try {
      if (was) {
        await client.unstar(albumId: album.id);
      } else {
        await client.star(albumId: album.id);
      }
      return true;
    } catch (_) {
      _applyAlbum(album, was);
      notifyListeners();
      return false;
    }
  }

  // ---- playlists (these throw on failure; callers show the error) --------

  Future<void> _reloadPlaylists() async {
    playlists = await client.playlists();
    notifyListeners();
  }

  Future<void> createPlaylist(String name,
      {List<String> songIds = const []}) async {
    await client.createPlaylist(name, songIds: songIds);
    await _reloadPlaylists();
  }

  Future<void> addToPlaylist(Playlist playlist, List<Song> songs) async {
    await client.addToPlaylist(playlist.id, songs.map((s) => s.id).toList());
    await _reloadPlaylists();
  }

  Future<void> removeFromPlaylist(String playlistId, int index) async {
    await client.removeFromPlaylist(playlistId, index);
    await _reloadPlaylists();
  }

  Future<void> renamePlaylist(Playlist playlist, String name) async {
    await client.renamePlaylist(playlist.id, name);
    await _reloadPlaylists();
  }

  Future<void> deletePlaylist(Playlist playlist) async {
    await client.deletePlaylist(playlist.id);
    await _reloadPlaylists();
  }
}

// ===== player_controller.dart =====
/// Owns the audio player, the play queue, the play mode and the current
/// song's lyrics.
class PlayerController extends ChangeNotifier {
  PlayerController(this.client, this.settings) {
    _stateSub = player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) next(auto: true);
    });
    _playingSub = player.playingStream.listen((_) => notifyListeners());
    _applyLoopMode();
  }

  final SubsonicClient client;
  final AppSettings settings;
  final AudioPlayer player = AudioPlayer();

  List<Song> queue = const [];
  int index = -1;
  Lyrics? lyrics;
  bool lyricsLoading = false;

  late final StreamSubscription<ProcessingState> _stateSub;
  late final StreamSubscription<bool> _playingSub;
  final Random _rng = Random();
  final List<int> _history = []; // for "previous" in shuffle mode
  int _loadToken = 0;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Song? get current =>
      (index >= 0 && index < queue.length) ? queue[index] : null;
  bool get playing => player.playing;
  PlayMode get mode => settings.playMode;

  // ---- play mode ---------------------------------------------------------

  void _applyLoopMode() {
    // Single-song repeat is handled natively by the player.
    unawaited(player
        .setLoopMode(mode == PlayMode.repeatOne ? LoopMode.one : LoopMode.off));
  }

  Future<void> setMode(PlayMode m) async {
    await settings.setPlayMode(m);
    _applyLoopMode();
    notifyListeners();
  }

  /// sequential → shuffle → repeat one → sequential …
  Future<void> cycleMode() =>
      setMode(PlayMode.values[(mode.index + 1) % PlayMode.values.length]);

  // ---- queue -------------------------------------------------------------

  Future<void> playQueue(List<Song> songs, int startIndex) async {
    queue = List.of(songs);
    _history.clear();
    await _load(startIndex);
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

  int _randomOther() {
    if (queue.length < 2) return 0;
    var i = _rng.nextInt(queue.length - 1);
    if (i >= index) i++;
    return i;
  }

  /// [auto] is true when the song ended by itself.
  Future<void> next({bool auto = false}) async {
    if (queue.isEmpty) return;

    if (auto && mode == PlayMode.repeatOne) {
      await player.seek(Duration.zero);
      unawaited(player.play());
      return;
    }

    if (mode == PlayMode.shuffle && queue.length > 1) {
      _history.add(index);
      if (_history.length > 200) _history.removeAt(0);
      await _load(_randomOther());
      return;
    }

    if (index + 1 < queue.length) {
      await _load(index + 1);
    } else if (auto && mode == PlayMode.sequential) {
      // Sequential mode: stop after the last song.
      await player.pause();
      await player.seek(Duration.zero);
    } else {
      await _load(0); // manual "next" on the last song wraps around
    }
  }

  Future<void> previous() async {
    if (queue.isEmpty) return;
    if (player.position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
      return;
    }
    if (mode == PlayMode.shuffle && _history.isNotEmpty) {
      await _load(_history.removeLast());
      return;
    }
    if (index > 0) {
      await _load(index - 1);
    } else {
      await player.seek(Duration.zero);
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
    _disposed = true;
    _stateSub.cancel();
    _playingSub.cancel();
    player.dispose();
    super.dispose();
  }
}

// ===== app_scope.dart =====
/// Gives every page (including ones pushed on the Navigator) access to the
/// logged-in session. It sits above the Navigator via MaterialApp.builder.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.settings,
    required this.player,
    required this.library,
    required super.child,
  });

  final AppSettings settings;
  final PlayerController player;
  final LibraryState library;

  SubsonicClient get client => player.client;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found above this context');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope old) =>
      settings != old.settings ||
      player != old.player ||
      library != old.library;
}

// ===== widgets.dart =====
/// Cover art loaded from the server, with a neutral placeholder.
/// Colors come from the current theme only — nothing is extracted from the art.
/// A failed load is retried automatically (twice) — flaky networks are common.
class CoverImage extends StatefulWidget {
  const CoverImage({
    super.key,
    required this.client,
    required this.coverId,
    this.size,
    this.radius = 12,
    this.requestSize = 600,
  });

  final SubsonicClient client;
  final String? coverId;
  final double? size;
  final double radius;
  final int requestSize;

  @override
  State<CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<CoverImage> {
  int _attempt = 0;
  Timer? _retry;

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  void _scheduleRetry() {
    if (_attempt >= 2 || (_retry?.isActive ?? false)) return;
    _retry = Timer(Duration(seconds: 1 + _attempt * 2), () {
      if (mounted) setState(() => _attempt++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url =
        widget.client.coverUrl(widget.coverId, size: widget.requestSize);

    final placeholder = ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.music_note_rounded, color: cs.onSurfaceVariant),
      ),
    );

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: url == null
            ? placeholder
            : Image.network(
                url.toString(),
                key: ValueKey('$url#$_attempt'),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  _scheduleRetry();
                  return placeholder;
                },
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : placeholder,
              ),
      ),
    );
  }
}

String formatDuration(Duration d) {
  final m = d.inMinutes.remainder(100).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

// ---- small helpers -------------------------------------------------------

/// Runs [action]; shows a SnackBar on success (optional) or failure.
Future<void> runAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (success != null) {
      messenger.showSnackBar(SnackBar(content: Text(success)));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('操作失败：$e')));
  }
}

Future<void> toggleStar(BuildContext context, Song song) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await AppScope.of(context).library.toggleSongStar(song);
  if (!ok) {
    messenger.showSnackBar(const SnackBar(content: Text('收藏失败，请检查网络')));
  }
}

void playSongs(BuildContext context, List<Song> songs, int index) {
  AppScope.of(context).player.playQueue(songs, index);
}

Future<bool> confirm(BuildContext context, String message,
    {String okLabel = '确定'}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(okLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(title: title, initial: initial, hint: hint),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.initial,
    required this.hint,
  });

  final String title;
  final String initial;
  final String hint;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _c.text.trim()),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// Bottom sheet: pick a playlist (or create one) to add [songs] to.
Future<void> showAddToPlaylistSheet(
    BuildContext context, List<Song> songs) async {
  final library = AppScope.of(context).library;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.6,
        ),
        child: ListenableBuilder(
          listenable: library,
          builder: (_, __) => ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('新建歌单'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final name = await promptText(context,
                      title: '新建歌单', hint: '歌单名称');
                  if (name == null || name.isEmpty || !context.mounted) return;
                  await runAction(
                    context,
                    () => library.createPlaylist(name,
                        songIds: songs.map((s) => s.id).toList()),
                    success: '已创建歌单「$name」',
                  );
                },
              ),
              for (final p in library.playlists)
                ListTile(
                  leading: const Icon(Icons.queue_music),
                  title: Text(p.name),
                  subtitle: Text('${p.songCount} 首'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    if (!context.mounted) return;
                    await runAction(
                      context,
                      () => library.addToPlaylist(p, songs),
                      success: '已添加到「${p.name}」',
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// One song row: cover (or track number), title, favorite heart and a menu.
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.index,
    this.onRemove,
  });

  final Song song;
  final VoidCallback onTap;

  /// When set, shows this number instead of the cover (album / playlist views).
  final int? index;

  /// When set, the menu gets a "remove from playlist" entry.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: app.library,
      builder: (context, _) {
        final starred = app.library.isSongStarred(song.id);
        final subtitle = index != null || song.album.isEmpty
            ? song.artist
            : '${song.artist} · ${song.album}';

        return ListTile(
          leading: index != null
              ? SizedBox(width: 28, child: Center(child: Text('$index')))
              : CoverImage(
                  client: app.client,
                  coverId: song.coverArt,
                  size: 44,
                  radius: 8,
                  requestSize: 120,
                ),
          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: starred ? '取消收藏' : '收藏',
                icon: Icon(
                  starred ? Icons.favorite : Icons.favorite_border,
                  color: starred ? cs.primary : null,
                ),
                onPressed: () => toggleStar(context, song),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'add') showAddToPlaylistSheet(context, [song]);
                  if (v == 'remove') onRemove?.call();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'add', child: Text('加入歌单')),
                  if (onRemove != null)
                    const PopupMenuItem(value: 'remove', child: Text('从歌单移除')),
                ],
              ),
            ],
          ),
          onTap: onTap,
        );
      },
    );
  }
}

/// "Play all / Add to playlist" strip shown above a song list.
class SongListHeader extends StatelessWidget {
  const SongListHeader({super.key, required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: songs.isEmpty ? null : () => playSongs(context, songs, 0),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('播放全部'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed:
                songs.isEmpty ? null : () => showAddToPlaylistSheet(context, songs),
            icon: const Icon(Icons.playlist_add),
            label: const Text('加入歌单'),
          ),
          const Spacer(),
          Text('${songs.length} 首', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}


extension PlayModeInfo on PlayMode {
  String get label => switch (this) {
        PlayMode.sequential => '顺序播放',
        PlayMode.shuffle => '随机播放',
        PlayMode.repeatOne => '单曲循环',
      };

  IconData get icon => switch (this) {
        PlayMode.sequential => Icons.format_list_numbered_rounded,
        PlayMode.shuffle => Icons.shuffle_rounded,
        PlayMode.repeatOne => Icons.repeat_one_rounded,
      };
}

// ===== pages/login_page.dart =====
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final _url = TextEditingController(text: widget.settings.serverUrl);
  late final _user = TextEditingController(text: widget.settings.username);
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final salt = SubsonicClient.randomSalt();
    final client = SubsonicClient(
      baseUrl: _url.text.trim(),
      username: _user.text.trim(),
      salt: salt,
      token: SubsonicClient.makeToken(_pass.text, salt),
    );

    try {
      await client.ping();
      await widget.settings.saveLogin(client); // Root swaps to the library
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '连接失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Text('连接到服务器',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 24),
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'https://music.example.com',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _user,
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  onSubmitted: (_) => _busy ? null : _login(),
                  decoration: const InputDecoration(
                    labelText: '密码',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _login,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('登录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===== pages/mini_player.dart =====
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, this.safeArea = true});

  /// Pad for the bottom system inset. Turn off when another bar sits below.
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final controller = app.player;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final song = controller.current;
        if (song == null) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;

        return Material(
          color: cs.surfaceContainerHigh,
          child: SafeArea(
            top: false,
            bottom: safeArea,
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PlayerPage()),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    CoverImage(
                      client: app.client,
                      coverId: song.coverArt,
                      size: 44,
                      radius: 8,
                      requestSize: 120,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall),
                          Text(song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(controller.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                      onPressed: controller.togglePlay,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ===== pages/player_page.dart =====
/// Full-screen player with separate portrait and landscape layouts.
///
/// Colors come only from the app's ColorScheme, which follows the system
/// (or user-chosen) light/dark setting. Nothing is extracted from album art.
class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final controller = app.player;

    return ListenableBuilder(
      listenable: Listenable.merge([controller, app.library]),
      builder: (context, _) {
        final song = controller.current;

        return Scaffold(
          appBar: AppBar(
            actions: [
              if (song != null)
                IconButton(
                  tooltip: '加入歌单',
                  icon: const Icon(Icons.playlist_add),
                  onPressed: () => showAddToPlaylistSheet(context, [song]),
                ),
              LyricSizeControls(settings: app.settings),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: song == null
                ? const Center(child: Text('没有正在播放的歌曲'))
                : LayoutBuilder(
                    builder: (context, c) {
                      final landscape = c.maxWidth > c.maxHeight;
                      return landscape
                          ? _Landscape(song: song)
                          : _Portrait(song: song);
                    },
                  ),
          ),
        );
      },
    );
  }
}

/// Portrait: small cover + title on top, big lyrics, seek bar, controls.
class _Portrait extends StatelessWidget {
  const _Portrait({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(
            children: [
              CoverImage(
                client: app.client,
                coverId: song.coverArt,
                size: 72,
                radius: 12,
                requestSize: 240,
              ),
              const SizedBox(width: 16),
              Expanded(child: _TrackInfo(song: song)),
            ],
          ),
        ),
        Expanded(child: _LyricsArea(song: song, baseSize: 24)),
        const _SeekBar(),
        _Controls(song: song),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Landscape (car head units): cover, title, seek bar and controls on the
/// left; large lyrics on the right.
class _Landscape extends StatelessWidget {
  const _Landscape({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 12, 12),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: CoverImage(
                        client: app.client,
                        coverId: song.coverArt,
                        radius: 20,
                        requestSize: 800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _TrackInfo(song: song, center: true),
                const SizedBox(height: 4),
                const _SeekBar(),
                _Controls(song: song),
              ],
            ),
          ),
        ),
        Expanded(flex: 7, child: _LyricsArea(song: song, baseSize: 34)),
      ],
    );
  }
}

class _TrackInfo extends StatelessWidget {
  const _TrackInfo({required this.song, this.center = false});

  final Song song;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final align = center ? TextAlign.center : TextAlign.start;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(song.title,
            maxLines: 2,
            textAlign: align,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(song.artist,
            maxLines: 1,
            textAlign: align,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _LyricsArea extends StatelessWidget {
  const _LyricsArea({required this.song, required this.baseSize});

  final Song song;
  final double baseSize;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final controller = app.player;

    if (controller.lyricsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final lyrics = controller.lyrics;
    if (lyrics == null) {
      return Center(
        child: Text('暂无歌词',
            style: TextStyle(
                fontSize: baseSize * 0.7,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return LyricsView(
      key: ValueKey(song.id), // rebuild state when the song changes
      lyrics: lyrics,
      player: controller.player,
      settings: app.settings,
      baseFontSize: baseSize,
    );
  }
}

/// − 100% + buttons that change the lyric font scale (persisted).
class LyricSizeControls extends StatelessWidget {
  const LyricSizeControls({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '减小歌词字号',
              icon: const Icon(Icons.text_decrease),
              onPressed:
                  settings.canDecreaseLyric ? settings.decreaseLyric : null,
            ),
            SizedBox(
              width: 44,
              child: Text(
                '${(settings.lyricScale * 100).round()}%',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            IconButton(
              tooltip: '增大歌词字号',
              icon: const Icon(Icons.text_increase),
              onPressed:
                  settings.canIncreaseLyric ? settings.increaseLyric : null,
            ),
          ],
        );
      },
    );
  }
}

class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.lyrics,
    required this.player,
    required this.settings,
    this.baseFontSize = 22,
  });

  final Lyrics lyrics;
  final AudioPlayer player;
  final AppSettings settings;
  final double baseFontSize;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  static const double _anchor = 0.38; // where the active line rests (0 top, 1 bottom)

  final ItemScrollController _scroll = ItemScrollController();
  StreamSubscription<Duration>? _positionSub;
  int _current = -1;

  @override
  void initState() {
    super.initState();
    if (widget.lyrics.synced) {
      _positionSub = widget.player.positionStream.listen((pos) {
        final i = widget.lyrics.indexAt(pos);
        if (i != _current) {
          setState(() => _current = i);
          _follow();
        }
      });
    }
    widget.settings.addListener(_onScaleChanged);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onScaleChanged);
    _positionSub?.cancel();
    super.dispose();
  }

  // Line heights change with the font size, so re-anchor after layout.
  void _onScaleChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow(jump: true));
  }

  void _follow({bool jump = false}) {
    if (_current < 0 || !_scroll.isAttached) return;
    if (jump) {
      _scroll.jumpTo(index: _current, alignment: _anchor);
    } else {
      _scroll.scrollTo(
        index: _current,
        alignment: _anchor,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = widget.lyrics.lines;
    final synced = widget.lyrics.synced;

    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        final scale = widget.settings.lyricScale;

        return LayoutBuilder(
          builder: (context, constraints) {
            return ScrollablePositionedList.builder(
              itemScrollController: _scroll,
              itemCount: lines.length,
              padding: EdgeInsets.symmetric(
                horizontal: 24,
                vertical: constraints.maxHeight * 0.4,
              ),
              itemBuilder: (context, i) {
                final line = lines[i];
                final active = !synced || i == _current;

                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: synced ? () => widget.player.seek(line.time) : null,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8 * scale),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: widget.baseFontSize * scale,
                        height: 1.4,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active
                            ? cs.onSurface
                            : cs.onSurface.withOpacity(0.45),
                      ),
                      child: Text(line.text.isEmpty ? '♪' : line.text),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar();

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player.player;
    final style = Theme.of(context).textTheme.bodySmall;

    return StreamBuilder<Duration?>(
      stream: player.durationStream,
      builder: (context, durationSnap) {
        final total = durationSnap.data ?? Duration.zero;
        final maxMs =
            total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0;

        return StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, positionSnap) {
            final pos = positionSnap.data ?? Duration.zero;
            final value =
                (_dragMs ?? pos.inMilliseconds.toDouble()).clamp(0.0, maxMs);

            return Column(
              children: [
                Slider(
                  value: value.toDouble(),
                  max: maxMs,
                  onChanged: (v) => setState(() => _dragMs = v),
                  onChangeEnd: (v) {
                    player.seek(Duration(milliseconds: v.round()));
                    setState(() => _dragMs = null);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(formatDuration(Duration(milliseconds: value.round())),
                          style: style),
                      Text(formatDuration(total), style: style),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// [mode] · previous · play/pause · next · favorite
class _Controls extends StatelessWidget {
  const _Controls({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final controller = app.player;
    final cs = Theme.of(context).colorScheme;
    final mode = controller.mode;
    final starred = app.library.isSongStarred(song.id);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: mode.label,
          iconSize: 28,
          icon: Icon(
            mode.icon,
            color: mode == PlayMode.sequential ? null : cs.primary,
          ),
          onPressed: () {
            final next =
                PlayMode.values[(mode.index + 1) % PlayMode.values.length];
            controller.cycleMode();
            final height = MediaQuery.of(context).size.height;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                content: Text(next.label, textAlign: TextAlign.center),
                duration: const Duration(milliseconds: 900),
                behavior: SnackBarBehavior.floating,
                // keep it near the top so it never covers the controls
                margin: EdgeInsets.only(
                    left: 48, right: 48, bottom: (height - 150).clamp(0.0, 2000.0).toDouble()),
              ));
          },
        ),
        IconButton.filledTonal(
          iconSize: 32,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: controller.previous,
        ),
        IconButton.filled(
          iconSize: 44,
          icon: Icon(controller.playing
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded),
          onPressed: controller.togglePlay,
        ),
        IconButton.filledTonal(
          iconSize: 32,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: controller.next,
        ),
        IconButton(
          tooltip: starred ? '取消收藏' : '收藏',
          iconSize: 28,
          icon: Icon(
            starred ? Icons.favorite : Icons.favorite_border,
            color: starred ? cs.primary : null,
          ),
          onPressed: () => toggleStar(context, song),
        ),
      ],
    );
  }
}

// ===== pages/album_page.dart =====
/// Grid of album covers; used by the Albums and Favorites tabs.
class AlbumGrid extends StatelessWidget {
  const AlbumGrid({super.key, required this.albums});

  final List<Album> albums;

  @override
  Widget build(BuildContext context) {
    final client = AppScope.of(context).client;

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.74,
      ),
      itemCount: albums.length,
      itemBuilder: (context, i) {
        final a = albums[i];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AlbumPage(album: a)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CoverImage(
                    client: client,
                    coverId: a.coverArt,
                    requestSize: 360,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall),
              Text(a.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        );
      },
    );
  }
}

class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key, required this.album});

  final Album album;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  Future<List<Song>>? _songs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _songs ??= AppScope.of(context).client.albumSongs(widget.album.id);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album.name),
        actions: [
          ListenableBuilder(
            listenable: app.library,
            builder: (context, _) {
              final starred = app.library.isAlbumStarred(widget.album.id);
              return IconButton(
                tooltip: starred ? '取消收藏专辑' : '收藏专辑',
                icon: Icon(
                  starred ? Icons.favorite : Icons.favorite_border,
                  color: starred ? cs.primary : null,
                ),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await app.library.toggleAlbumStar(widget.album);
                  if (!ok) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('收藏失败，请检查网络')),
                    );
                  }
                },
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Song>>(
        future: _songs,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('加载失败：${snap.error}'));
          }
          final songs = snap.data!;
          return ListView.builder(
            itemCount: songs.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) return SongListHeader(songs: songs);
              final s = songs[i - 1];
              return SongTile(
                song: s,
                index: i,
                onTap: () => playSongs(context, songs, i - 1),
              );
            },
          );
        },
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

// ===== pages/playlist_page.dart =====
class PlaylistPage extends StatefulWidget {
  const PlaylistPage({super.key, required this.playlist});

  final Playlist playlist;

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  Future<List<Song>>? _songs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _songs ??= AppScope.of(context).client.playlistSongs(widget.playlist.id);
  }

  void _reload() {
    setState(() {
      _songs = AppScope.of(context).client.playlistSongs(widget.playlist.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;

    return Scaffold(
      appBar: AppBar(title: Text(widget.playlist.name)),
      body: FutureBuilder<List<Song>>(
        future: _songs,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('加载失败：${snap.error}'));
          }
          final songs = snap.data!;
          if (songs.isEmpty) {
            return const Center(child: Text('这个歌单还是空的'));
          }
          return ListView.builder(
            itemCount: songs.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) return SongListHeader(songs: songs);
              final index = i - 1;
              final s = songs[index];
              return SongTile(
                song: s,
                onTap: () => playSongs(context, songs, index),
                onRemove: () async {
                  await runAction(
                    context,
                    () => library.removeFromPlaylist(widget.playlist.id, index),
                    success: '已从歌单移除',
                  );
                  if (mounted) _reload();
                },
              );
            },
          );
        },
      ),
    );
  }
}

// ===== pages/albums_tab.dart =====
/// "Albums" page of the library, with a few sort orders.
class AlbumsBody extends StatefulWidget {
  const AlbumsBody({super.key});

  @override
  State<AlbumsBody> createState() => _AlbumsBodyState();
}

class _AlbumsBodyState extends State<AlbumsBody>
    with AutomaticKeepAliveClientMixin {
  static const _types = [
    ('最近添加', 'newest'),
    ('按名称', 'alphabeticalByName'),
    ('随机', 'random'),
  ];

  String _type = 'newest';
  Future<List<Album>>? _albums;

  @override
  bool get wantKeepAlive => true;

  Future<List<Album>> _fetch() =>
      AppScope.of(context).client.albumList(_type, size: 300);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _albums ??= _fetch();
  }

  Future<void> _refresh() async {
    final future = _fetch();
    setState(() => _albums = future);
    try {
      await future;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              for (final t in _types)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(t.$1),
                    selected: _type == t.$2,
                    onSelected: (_) {
                      _type = t.$2;
                      _refresh();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Album>>(
            future: _albums,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('加载失败：${snap.error}'),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: _refresh, child: const Text('重试')),
                    ],
                  ),
                );
              }
              final albums = snap.data!;
              return RefreshIndicator(
                onRefresh: _refresh,
                child: albums.isEmpty
                    ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
                        SizedBox(height: 200),
                        Center(child: Text('服务器上还没有专辑')),
                      ])
                    : AlbumGrid(albums: albums),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ===== pages/playlists_tab.dart =====
/// "Playlists" page of the library.
class PlaylistsBody extends StatelessWidget {
  const PlaylistsBody({super.key});

  Future<void> _create(BuildContext context) async {
    final library = AppScope.of(context).library;
    final name = await promptText(context, title: '新建歌单', hint: '歌单名称');
    if (name == null || name.isEmpty || !context.mounted) return;
    await runAction(
      context,
      () => library.createPlaylist(name),
      success: '已创建歌单「$name」',
    );
  }

  Future<void> _rename(BuildContext context, Playlist p) async {
    final library = AppScope.of(context).library;
    final name = await promptText(context, title: '重命名歌单', initial: p.name);
    if (name == null || name.isEmpty || name == p.name || !context.mounted) {
      return;
    }
    await runAction(context, () => library.renamePlaylist(p, name));
  }

  Future<void> _delete(BuildContext context, Playlist p) async {
    final library = AppScope.of(context).library;
    final ok = await confirm(context, '删除歌单「${p.name}」？歌曲本身不会被删除。',
        okLabel: '删除');
    if (!ok || !context.mounted) return;
    await runAction(context, () => library.deletePlaylist(p), success: '已删除');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final library = app.library;

    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        if (library.loading && library.playlists.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (library.error != null && library.playlists.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('加载失败：${library.error}'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: library.refresh,
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }

        final playlists = library.playlists;
        return RefreshIndicator(
          onRefresh: library.refresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: playlists.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.add)),
                  title: const Text('新建歌单'),
                  subtitle: playlists.isEmpty ? const Text('还没有歌单') : null,
                  onTap: () => _create(context),
                );
              }
              final p = playlists[i - 1];
              return ListTile(
                leading: CoverImage(
                  client: app.client,
                  coverId: p.coverArt,
                  size: 52,
                  radius: 8,
                  requestSize: 120,
                ),
                title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${p.songCount} 首'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'rename') _rename(context, p);
                    if (v == 'delete') _delete(context, p);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('重命名')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PlaylistPage(playlist: p)),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ===== pages/favorites_tab.dart =====
/// "Liked songs" page of the library.
class FavoriteSongsBody extends StatelessWidget {
  const FavoriteSongsBody({super.key});

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;

    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final songs = library.starredSongs;
        if (library.loading && songs.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return RefreshIndicator(
          onRefresh: library.refresh,
          child: songs.isEmpty
              ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
                  SizedBox(height: 200),
                  Center(child: Text('还没有收藏的歌曲，点歌曲右侧的爱心')),
                ])
              : ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: songs.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) return SongListHeader(songs: songs);
                    return SongTile(
                      song: songs[i - 1],
                      onTap: () => playSongs(context, songs, i - 1),
                    );
                  },
                ),
        );
      },
    );
  }
}

/// "Liked albums" page of the library.
class FavoriteAlbumsBody extends StatelessWidget {
  const FavoriteAlbumsBody({super.key});

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;

    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final albums = library.starredAlbums;
        if (library.loading && albums.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return RefreshIndicator(
          onRefresh: library.refresh,
          child: albums.isEmpty
              ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
                  SizedBox(height: 200),
                  Center(child: Text('还没有收藏的专辑，在专辑页点右上角的爱心')),
                ])
              : AlbumGrid(albums: albums),
        );
      },
    );
  }
}

// ===== pages/library_tab.dart =====
/// Music library: albums, playlists, liked songs, liked albums.
class LibraryTab extends StatelessWidget {
  const LibraryTab({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('音乐库'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '专辑'),
              Tab(text: '歌单'),
              Tab(text: '喜欢的歌曲'),
              Tab(text: '喜欢的专辑'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AlbumsBody(),
            PlaylistsBody(),
            FavoriteSongsBody(),
            FavoriteAlbumsBody(),
          ],
        ),
      ),
    );
  }
}

// ===== pages/search_tab.dart =====
class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _controller = TextEditingController();
  Timer? _debounce;
  SearchResult? _result;
  bool _loading = false;
  String? _error;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(text));
    setState(() {}); // refresh the clear button
  }

  Future<void> _search(String text) async {
    final q = text.trim();
    _query = q;
    if (q.isEmpty) {
      setState(() {
        _result = null;
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await AppScope.of(context).client.search(q);
      if (!mounted || q != _query) return; // a newer query took over
      setState(() {
        _result = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || q != _query) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Widget _body(BuildContext context) {
    final client = AppScope.of(context).client;
    final result = _result;

    if (_query.isEmpty) {
      return const Center(child: Text('输入关键词搜索歌曲和专辑'));
    }
    if (_error != null) return Center(child: Text('搜索失败：$_error'));
    if (result == null) return const Center(child: CircularProgressIndicator());
    if (result.isEmpty) return const Center(child: Text('没有找到结果'));

    final titleStyle = Theme.of(context).textTheme.titleSmall;

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (result.albums.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('专辑', style: titleStyle),
          ),
          for (final a in result.albums)
            ListTile(
              leading: CoverImage(
                client: client,
                coverId: a.coverArt,
                size: 48,
                radius: 8,
                requestSize: 120,
              ),
              title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle:
                  Text(a.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AlbumPage(album: a)),
              ),
            ),
        ],
        if (result.songs.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('歌曲', style: titleStyle),
          ),
          for (var i = 0; i < result.songs.length; i++)
            SongTile(
              song: result.songs[i],
              onTap: () => playSongs(context, result.songs, i),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: '搜索歌曲、专辑',
            border: InputBorder.none,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      _search('');
                    },
                  ),
          ),
        ),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: _body(context),
    );
  }
}

// ===== pages/home_tab.dart =====
/// Home: recommendations built from your own library —
/// random songs plus rows of newest / random / most-played / recent albums.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  static const _rows = [
    ('最近添加', 'newest'),
    ('随机专辑', 'random'),
    ('最常播放', 'frequent'),
    ('最近播放', 'recent'),
  ];

  bool _loaded = false;
  late Future<List<Song>> _songs;
  late Map<String, Future<List<Album>>> _albums;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  void _load() {
    final client = AppScope.of(context).client;
    _songs = client.randomSongs(size: 10);
    _albums = {
      for (final r in _rows) r.$2: client.albumList(r.$2, size: 20),
    };
  }

  Future<void> _refresh() async {
    setState(_load);
    try {
      await Future.wait<Object>([_songs, ..._albums.values]);
    } catch (_) {}
  }

  void _reshuffleSongs() {
    setState(() {
      _songs = AppScope.of(context).client.randomSongs(size: 10);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('首页')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _RecommendedSongs(future: _songs, onReshuffle: _reshuffleSongs),
            for (final r in _rows)
              _AlbumRow(title: r.$1, future: _albums[r.$2]!),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _RecommendedSongs extends StatelessWidget {
  const _RecommendedSongs({required this.future, required this.onReshuffle});

  final Future<List<Song>> future;
  final VoidCallback onReshuffle;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Song>>(
      future: future,
      builder: (context, snap) {
        final songs = snap.data ?? const <Song>[];
        final done = snap.connectionState == ConnectionState.done;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              title: '为你推荐',
              actions: [
                TextButton.icon(
                  onPressed: onReshuffle,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('换一批'),
                ),
                FilledButton.tonalIcon(
                  onPressed:
                      songs.isEmpty ? null : () => playSongs(context, songs, 0),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('播放'),
                ),
                const SizedBox(width: 8),
              ],
            ),
            if (!done)
              const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (snap.hasError)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('加载失败：${snap.error}'),
              )
            else if (songs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('服务器上还没有歌曲'),
              )
            else
              for (var i = 0; i < songs.length; i++)
                SongTile(
                  song: songs[i],
                  onTap: () => playSongs(context, songs, i),
                ),
          ],
        );
      },
    );
  }
}

class _AlbumRow extends StatelessWidget {
  const _AlbumRow({required this.title, required this.future});

  final String title;
  final Future<List<Album>> future;

  static const double _card = 132;

  @override
  Widget build(BuildContext context) {
    final client = AppScope.of(context).client;

    return FutureBuilder<List<Album>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(title: title),
              const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          );
        }
        if (snap.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(title: title),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('加载失败：${snap.error}'),
              ),
            ],
          );
        }
        final albums = snap.data!;
        if (albums.isEmpty) return const SizedBox.shrink(); // e.g. nothing played yet

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title: title),
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: albums.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final a = albums[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => AlbumPage(album: a)),
                    ),
                    child: SizedBox(
                      width: _card,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CoverImage(
                            client: client,
                            coverId: a.coverArt,
                            size: _card,
                            requestSize: 360,
                          ),
                          const SizedBox(height: 6),
                          Text(a.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall),
                          Text(a.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ===== pages/settings_tab.dart =====
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final settings = app.settings;
    final player = app.player;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListenableBuilder(
        listenable: Listenable.merge([settings, player]),
        builder: (context, _) {
          final scale = settings.lyricScale;

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const _Section('外观'),
              ListTile(
                title: const Text('主题'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                          value: ThemeMode.system, label: Text('跟随系统')),
                      ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (s) => settings.setThemeMode(s.first),
                  ),
                ),
              ),
              const _Section('播放'),
              ListTile(
                title: const Text('歌词字号'),
                trailing: Text('${(scale * 100).round()}%'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Slider(
                  value: scale,
                  min: AppSettings.minScale,
                  max: AppSettings.maxScale,
                  divisions: 13,
                  onChanged: settings.setLyricScale,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '歌词预览 Lyrics preview',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22 * scale,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                title: const Text('播放模式'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SegmentedButton<PlayMode>(
                    showSelectedIcon: false,
                    segments: [
                      for (final m in PlayMode.values)
                        ButtonSegment(value: m, label: Text(m.label)),
                    ],
                    selected: {player.mode},
                    onSelectionChanged: (s) => player.setMode(s.first),
                  ),
                ),
              ),
              const _Section('账号'),
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('服务器'),
                subtitle: Text(settings.serverUrl),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('用户名'),
                subtitle: Text(settings.username),
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('退出登录'),
                onTap: () async {
                  final ok = await confirm(context, '退出登录？', okLabel: '退出');
                  if (ok) settings.clearLogin();
                },
              ),
              const _Section('关于'),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('My Player'),
                subtitle: Text('基于 Subsonic / Navidrome 的个人音乐播放器'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

// ===== pages/home_shell.dart =====
/// Bottom-navigation shell: Home / Library / Search / Settings,
/// with the mini player docked above the bar.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          HomeTab(),
          LibraryTab(),
          SearchTab(),
          SettingsTab(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(safeArea: false),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: '首页',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: '音乐库',
              ),
              NavigationDestination(
                icon: Icon(Icons.search),
                label: '搜索',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '设置',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===== main.dart =====
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings();
  await settings.load();
  runApp(MyApp(settings: settings));
}

/// Everything that exists only while logged in.
class Session {
  Session(this.client, AppSettings settings)
      : player = PlayerController(client, settings),
        library = LibraryState(client) {
    library.refresh();
  }

  final SubsonicClient client;
  final PlayerController player;
  final LibraryState library;

  void dispose() {
    player.dispose();
    library.dispose();
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // One fixed seed. Light/dark follows the system by default (or the
  // user's choice in Settings); colors never come from album art.
  static const _seed = Color(0xFF3D5AFE);

  Session? _session;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettings);
    _sync();
  }

  void _sync() {
    final s = widget.settings;
    if (!s.hasLogin) {
      _session?.dispose();
      _session = null;
    } else if (_session == null) {
      _session = Session(s.buildClient(), s);
    }
  }

  void _onSettings() => setState(_sync);

  @override
  void dispose() {
    widget.settings.removeListener(_onSettings);
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;

    return MaterialApp(
      title: 'My Player',
      debugShowCheckedModeBanner: false,
      themeMode: widget.settings.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
      ),
      // AppScope must sit above the Navigator so pushed pages can see it.
      builder: (context, child) {
        if (session == null || child == null) {
          return child ?? const SizedBox.shrink();
        }
        return AppScope(
          settings: widget.settings,
          player: session.player,
          library: session.library,
          child: child,
        );
      },
      home: session == null
          ? LoginPage(settings: widget.settings)
          : const HomeShell(),
    );
  }
}
