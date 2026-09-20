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
