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

  Future<List<Album>> newestAlbums({int size = 60, int offset = 0}) async {
    final root = await _get('getAlbumList2', {
      'type': 'newest',
      'size': '$size',
      'offset': '$offset',
    });
    final list = (root['albumList2']?['album'] as List?) ?? const [];
    return list.map((e) => Album.fromJson(e as Map<String, dynamic>)).toList();
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

  late final SharedPreferences _prefs;

  String serverUrl = '';
  String username = '';
  String salt = '';
  String token = '';
  double _lyricScale = 1.0;

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
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Song? get current =>
      (index >= 0 && index < queue.length) ? queue[index] : null;
  bool get hasNext => index + 1 < queue.length;
  bool get hasPrev => index > 0;
  bool get playing => player.playing;

  Future<void> playQueue(List<Song> songs, int startIndex) async {
    queue = List.of(songs);
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
class CoverImage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = client.coverUrl(coverId, size: requestSize);

    final placeholder = ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.music_note_rounded, color: cs.onSurfaceVariant),
      ),
    );

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: url == null
            ? placeholder
            : Image.network(
                url.toString(),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder,
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
/// Full-screen player.
///
/// Colors come only from the app's ColorScheme, which follows the system
/// light/dark setting. Nothing is extracted from the album art.
class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final controller = app.player;
    final settings = app.settings;

    return ListenableBuilder(
      listenable: Listenable.merge([controller, app.library]),
      builder: (context, _) {
        final song = controller.current;
        final theme = Theme.of(context);
        final starred = song != null && app.library.isSongStarred(song.id);

        return Scaffold(
          appBar: AppBar(
            actions: [
              if (song != null) ...[
                IconButton(
                  tooltip: starred ? '取消收藏' : '收藏',
                  icon: Icon(
                    starred ? Icons.favorite : Icons.favorite_border,
                    color: starred ? theme.colorScheme.primary : null,
                  ),
                  onPressed: () => toggleStar(context, song),
                ),
                IconButton(
                  tooltip: '加入歌单',
                  icon: const Icon(Icons.playlist_add),
                  onPressed: () => showAddToPlaylistSheet(context, [song]),
                ),
              ],
              LyricSizeControls(settings: settings),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: song == null
                ? const Center(child: Text('没有正在播放的歌曲'))
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                        child: Row(
                          children: [
                            CoverImage(
                              client: controller.client,
                              coverId: song.coverArt,
                              size: 72,
                              radius: 12,
                              requestSize: 240,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(song.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleLarge),
                                  const SizedBox(height: 2),
                                  Text(song.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                              color: theme.colorScheme
                                                  .onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _lyricsArea(
                            context, controller, settings, song.id),
                      ),
                      _SeekBar(player: controller.player),
                      _Controls(controller: controller),
                      const SizedBox(height: 8),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _lyricsArea(BuildContext context, PlayerController controller,
      AppSettings settings, String songId) {
    if (controller.lyricsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final lyrics = controller.lyrics;
    if (lyrics == null) {
      return Center(
        child: Text('暂无歌词',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return LyricsView(
      key: ValueKey(songId), // rebuild state when the song changes
      lyrics: lyrics,
      player: controller.player,
      settings: settings,
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
  });

  final Lyrics lyrics;
  final AudioPlayer player;
  final AppSettings settings;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  static const double _baseFontSize = 22;
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
                      style: TextStyle(
                        fontSize: _baseFontSize * scale,
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
  const _SeekBar({required this.player});

  final AudioPlayer player;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;

    return StreamBuilder<Duration?>(
      stream: widget.player.durationStream,
      builder: (context, durationSnap) {
        final total = durationSnap.data ?? Duration.zero;
        final maxMs =
            total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0;

        return StreamBuilder<Duration>(
          stream: widget.player.positionStream,
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
                    widget.player.seek(Duration(milliseconds: v.round()));
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

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          iconSize: 32,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: controller.previous,
        ),
        const SizedBox(width: 20),
        IconButton.filled(
          iconSize: 44,
          icon: Icon(controller.playing
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded),
          onPressed: controller.togglePlay,
        ),
        const SizedBox(width: 20),
        IconButton.filledTonal(
          iconSize: 32,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: controller.hasNext ? controller.next : null,
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
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

// ===== pages/albums_tab.dart =====
class AlbumsTab extends StatefulWidget {
  const AlbumsTab({super.key});

  @override
  State<AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends State<AlbumsTab> {
  Future<List<Album>>? _albums;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _albums ??= AppScope.of(context).client.newestAlbums();
  }

  Future<void> _refresh() async {
    final future = AppScope.of(context).client.newestAlbums();
    setState(() => _albums = future);
    try {
      await future;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('专辑'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') app.settings.clearLogin();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('退出登录')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<Album>>(
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
                  FilledButton(onPressed: _refresh, child: const Text('重试')),
                ],
              ),
            );
          }
          final albums = snap.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: albums.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 200),
                    Center(child: Text('服务器上还没有专辑')),
                  ])
                : AlbumGrid(albums: albums),
          );
        },
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

// ===== pages/playlists_tab.dart =====
class PlaylistsTab extends StatelessWidget {
  const PlaylistsTab({super.key});

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('歌单'),
        actions: [
          IconButton(
            tooltip: '新建歌单',
            icon: const Icon(Icons.add),
            onPressed: () => _create(context),
          ),
        ],
      ),
      body: ListenableBuilder(
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
          return RefreshIndicator(
            onRefresh: library.refresh,
            child: library.playlists.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 200),
                    Center(child: Text('还没有歌单，点右上角 + 新建')),
                  ])
                : ListView.builder(
                    itemCount: library.playlists.length,
                    itemBuilder: (context, i) {
                      final p = library.playlists[i];
                      return ListTile(
                        leading: CoverImage(
                          client: app.client,
                          coverId: p.coverArt,
                          size: 52,
                          radius: 8,
                          requestSize: 120,
                        ),
                        title: Text(p.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
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
                          MaterialPageRoute(
                            builder: (_) => PlaylistPage(playlist: p),
                          ),
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

// ===== pages/favorites_tab.dart =====
class FavoritesTab extends StatelessWidget {
  const FavoritesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('收藏'),
          bottom: const TabBar(tabs: [Tab(text: '歌曲'), Tab(text: '专辑')]),
        ),
        body: ListenableBuilder(
          listenable: library,
          builder: (context, _) {
            final songs = library.starredSongs;
            final albums = library.starredAlbums;

            if (library.loading && songs.isEmpty && albums.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            return TabBarView(
              children: [
                RefreshIndicator(
                  onRefresh: library.refresh,
                  child: songs.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 200),
                          Center(child: Text('还没有收藏的歌曲，点歌曲右侧的爱心')),
                        ])
                      : ListView.builder(
                          itemCount: songs.length + 1,
                          itemBuilder: (context, i) {
                            if (i == 0) return SongListHeader(songs: songs);
                            return SongTile(
                              song: songs[i - 1],
                              onTap: () => playSongs(context, songs, i - 1),
                            );
                          },
                        ),
                ),
                RefreshIndicator(
                  onRefresh: library.refresh,
                  child: albums.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 200),
                          Center(child: Text('还没有收藏的专辑，在专辑页点右上角的爱心')),
                        ])
                      : AlbumGrid(albums: albums),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ===== pages/home_shell.dart =====
/// Bottom-navigation shell: Albums / Search / Playlists / Favorites,
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
          AlbumsTab(),
          SearchTab(),
          PlaylistsTab(),
          FavoritesTab(),
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
                icon: Icon(Icons.album_outlined),
                selectedIcon: Icon(Icons.album),
                label: '专辑',
              ),
              NavigationDestination(
                icon: Icon(Icons.search),
                label: '搜索',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: '歌单',
              ),
              NavigationDestination(
                icon: Icon(Icons.favorite_border),
                selectedIcon: Icon(Icons.favorite),
                label: '收藏',
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
  Session(this.client)
      : player = PlayerController(client),
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
  // One fixed seed. Light/dark follows the system; player colors never come
  // from album art.
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
      _session = Session(s.buildClient());
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
      themeMode: ThemeMode.system,
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
