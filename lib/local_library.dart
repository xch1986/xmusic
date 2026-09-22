import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'subsonic.dart';

/// 真本地扫描：扫“设置里的本地下载路径”目录下的音频文件，
/// 解析成可播放的歌曲（file:// 直连本地文件），缓存列表避免每次启动重扫。
/// 与服务器(Navidrome)无关，纯粹扫描本机下载目录里的音乐。
class LocalLibrary {
  static const _fileName = 'xmusic_local_cache.json';

  static const Set<String> _audioExts = {
    '.mp3', '.flac', '.wav', '.m4a', '.aac', '.ogg', '.opus', '.ape', '.wma',
  };

  static Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static bool isAudio(String path) {
    final i = path.lastIndexOf('.');
    if (i < 0) return false;
    return _audioExts.contains(path.substring(i).toLowerCase());
  }

  /// 从文件名解析 歌手 - 标题（兼容 -、–、— 分隔）。
  static Song songFromFile(File f) {
    final path = f.path;
    final name = path.split(Platform.pathSeparator).last;
    final base = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    var artist = '本地';
    var title = base;
    final m = RegExp(r'^(.*?)\s*[-–—]\s*(.+)$').firstMatch(base);
    if (m != null && m.group(1)!.trim().isNotEmpty) {
      artist = m.group(1)!.trim();
      title = m.group(2)!.trim();
    }
    final dirName = f.parent.path.split(Platform.pathSeparator).last;
    return Song(
      id: path,
      title: title.isEmpty ? base : title,
      artist: artist,
      album: (dirName.isEmpty || dirName == f.path) ? '本地文件' : dirName,
      coverArt: null,
      durationSec: null,
      fromExternal: false,
      streamUrl: Uri.file(path).toString(), // file:///...
    );
  }

  /// 读取本地文件缓存；无缓存或损坏返回空列表。
  static Future<List<Song>> load() async {
    try {
      final f = await _cacheFile();
      if (!await f.exists()) return const [];
      final list = jsonDecode(await f.readAsString()) as List;
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return Song(
          id: (m['id'] ?? '').toString(),
          title: (m['title'] ?? '').toString(),
          artist: (m['artist'] ?? '').toString(),
          album: (m['album'] ?? '').toString(),
          streamUrl: m['streamUrl']?.toString(),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<Song> songs) async {
    try {
      final f = await _cacheFile();
      await f.writeAsString(jsonEncode(songs
          .map((s) => {
                'id': s.id,
                'title': s.title,
                'artist': s.artist,
                'album': s.album,
                'streamUrl': s.streamUrl,
              })
          .toList()));
    } catch (_) {}
  }

  /// 递归扫描 [rootPath]（设置的本地下载路径）下的所有音频文件。
  /// [onFile] 每发现一个文件回调（参数为当前已发现数量），用于刷新进度。
  static Future<List<Song>> scan(
    String rootPath, {
    void Function(int found)? onFile,
  }) async {
    final songs = <Song>[];
    final queue = <Directory>[Directory(rootPath)];
    while (queue.isNotEmpty) {
      final dir = queue.removeLast();
      try {
        final entries = await dir.list(followLinks: false).toList();
        for (final e in entries) {
          if (e is Directory) {
            queue.add(e);
          } else if (e is File && isAudio(e.path)) {
            songs.add(songFromFile(e));
            onFile?.call(songs.length);
          }
        }
      } catch (_) {
        // 无权限/损坏目录跳过，不中断整体扫描
      }
    }
    return songs;
  }
}
