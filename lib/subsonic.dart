import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'lyrics.dart';

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
    this.songCount,
    this.year,
    this.starred = false,
  });

  final String id;
  final String name;
  final String artist;
  final String? coverArt;
  final int? songCount;
  final int? year;
  final bool starred;

  factory Album.fromJson(Map<String, dynamic> j) => Album(
        id: j['id'].toString(),
        name: (j['name'] ?? j['title'] ?? '').toString(),
        artist: (j['artist'] ?? '').toString(),
        coverArt: j['coverArt']?.toString(),
        songCount: (j['songCount'] as num?)?.toInt(),
        year: (j['year'] as num?)?.toInt(),
        starred: j['starred'] != null,
      );
}

class Artist {
  const Artist({
    required this.id,
    required this.name,
    this.albumCount,
    this.coverArt,
  });

  final String id;
  final String name;
  final int? albumCount;
  final String? coverArt;

  factory Artist.fromJson(Map<String, dynamic> j) => Artist(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        albumCount: (j['albumCount'] as num?)?.toInt(),
        coverArt: j['coverArt']?.toString(),
      );
}

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.songCount,
    this.coverArt,
    this.comment,
  });

  final String id;
  final String name;
  final int? songCount;
  final String? coverArt;
  final String? comment;

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        songCount: (j['songCount'] as num?)?.toInt(),
        coverArt: j['coverArt']?.toString(),
        comment: j['comment']?.toString(),
      );
}

class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.albumId,
    this.durationSec,
    this.coverArt,
    this.starred = false,
    this.coverUrl,
    this.streamUrl,
    this.fromExternal = false,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String? albumId;
  final int? durationSec;
  final String? coverArt;
  final bool starred;
  /// Direct cover image URL (external songs). Takes priority over [coverArt].
  final String? coverUrl;
  /// Direct stream URL (external songs). Takes priority over server stream.
  final String? streamUrl;
  final bool fromExternal;

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        id: j['id'].toString(),
        title: (j['title'] ?? '').toString(),
        artist: (j['artist'] ?? '').toString(),
        album: (j['album'] ?? '').toString(),
        albumId: j['albumId']?.toString(),
        durationSec: (j['duration'] as num?)?.toInt(),
        coverArt: j['coverArt']?.toString(),
        starred: j['starred'] != null,
      );
}

class SearchResults {
  const SearchResults({this.songs = const [], this.albums = const [], this.artists = const []});
  final List<Song> songs;
  final List<Album> albums;
  final List<Artist> artists;
}

/// Subsonic / OpenSubsonic client (works with Navidrome).
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

  Uri _uri(String method, [Map<String, String> extra = const {}]) {
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
      [Map<String, String> extra = const {}]) async {
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

  // ---- 专辑列表 ----
  Future<List<Album>> albumList({
    String type = 'newest',
    int size = 60,
    int offset = 0,
  }) async {
    final root = await _get('getAlbumList2', {
      'type': type,
      'size': '$size',
      'offset': '$offset',
    });
    final list = (root['albumList2']?['album'] as List?) ?? const [];
    return list.map((e) => Album.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Album>> newestAlbums({int size = 30}) =>
      albumList(type: 'newest', size: size);

  Future<List<Album>> recentAlbums({int size = 30}) =>
      albumList(type: 'recent', size: size);

  Future<List<Album>> frequentAlbums({int size = 30}) =>
      albumList(type: 'frequent', size: size);

  Future<List<Album>> randomAlbums({int size = 30}) =>
      albumList(type: 'random', size: size);

  // ---- 歌手 ----
  Future<List<Artist>> artists() async {
    final root = await _get('getArtists');
    final indexes = (root['artists']?['index'] as List?) ?? const [];
    final out = <Artist>[];
    for (final idx in indexes) {
      final list = (idx['artist'] as List?) ?? const [];
      for (final a in list) {
        out.add(Artist.fromJson(a as Map<String, dynamic>));
      }
    }
    return out;
  }

  Future<List<Album>> artistAlbums(String artistId) async {
    final root = await _get('getArtist', {'id': artistId});
    final list = (root['artist']?['album'] as List?) ?? const [];
    return list.map((e) => Album.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ---- 歌单 ----
  Future<List<Playlist>> playlists() async {
    final root = await _get('getPlaylists');
    final list = (root['playlists']?['playlist'] as List?) ?? const [];
    return list.map((e) => Playlist.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Song>> playlistSongs(String playlistId) async {
    final root = await _get('getPlaylist', {'id': playlistId});
    final raw = root['playlist']?['entry'];
    final list = raw is List ? raw : (raw is Map ? [raw] : const []);
    return list.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ---- 专辑歌曲 ----
  Future<List<Song>> albumSongs(String albumId) async {
    final root = await _get('getAlbum', {'id': albumId});
    final list = (root['album']?['song'] as List?) ?? const [];
    return list.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ---- 搜索 ----
  Future<SearchResults> search(String query, {int count = 30}) async {
    if (query.trim().isEmpty) return const SearchResults();
    final root = await _get('search3', {
      'query': query.trim(),
      'songCount': '$count',
      'albumCount': '$count',
      'artistCount': '$count',
    });
    final sr = (root['searchResult3'] as Map<String, dynamic>?) ?? const {};
    final songs = ((sr['song'] as List?) ?? const [])
        .map((e) => Song.fromJson(e as Map<String, dynamic>))
        .toList();
    final albums = ((sr['album'] as List?) ?? const [])
        .map((e) => Album.fromJson(e as Map<String, dynamic>))
        .toList();
    final artists = ((sr['artist'] as List?) ?? const [])
        .map((e) => Artist.fromJson(e as Map<String, dynamic>))
        .toList();
    return SearchResults(songs: songs, albums: albums, artists: artists);
  }

  // ---- 随机/收藏 ----
  Future<List<Song>> randomSongs({int size = 50}) async {
    final root = await _get('getRandomSongs', {'size': '$size'});
    final list = (root['randomSongs']?['song'] as List?) ?? const [];
    return list.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Song>> starredSongs() async {
    final root = await _get('getStarred2');
    final list = (root['starred2']?['song'] as List?) ?? const [];
    return list.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Album>> starredAlbums() async {
    final root = await _get('getStarred2');
    final list = (root['starred2']?['album'] as List?) ?? const [];
    return list.map((e) => Album.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> starSong(String id) => _get('star', {'id': id});
  Future<void> unstarSong(String id) => _get('unstar', {'id': id});

  Future<void> addToPlaylist(String playlistId, String songId) =>
      _get('updatePlaylist', {'playlistId': playlistId, 'songIdToAdd': songId});

  // ---- 播放/封面/歌词 ----
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
