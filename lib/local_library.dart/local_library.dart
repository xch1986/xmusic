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
      coverUrl: _findCover(f),
      durationSec: null,
      fromExternal: false,
      streamUrl: Uri.file(path).toString(), // file:///...
    );
  }

  /// 找本地封面：优先同名图片（<歌名>.jpg 等），其次同目录 cover/folder/albumart。
  /// 命中返回 file:// URI，供 CoverImage 直接渲染本地图。
  static String? _findCover(File f) {
    final base = f.path.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final dir = f.parent.path;
    const exts = ['.jpg', '.jpeg', '.png', '.webp'];
    final candidates = <String>[
      for (final e in exts) '$base$e',
      for (final e in exts) '$dir/cover$e',
      for (final e in exts) '$dir/folder$e',
      for (final e in exts) '$dir/albumart$e',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return Uri.file(c).toString();
    }
    return null;
  }

  /// 提取 MP3 ID3v2 内嵌封面（APIC frame），写入应用缓存目录，返回 file:// URI。
  /// 仅支持 mp3（ID3v2）；flac/wav 等无 ID3v2 头返回 null。图片已存在缓存直接复用。
  static Future<String?> extractId3Cover(File f) async {
    try {
      if (!f.path.toLowerCase().endsWith('.mp3')) return null;
      final raf = f.openSync();
      try {
        if (raf.lengthSync() < 10) return null;
        final head = raf.readSync(10);
        if (head.length < 10 ||
            head[0] != 0x49 || head[1] != 0x44 || head[2] != 0x33) {
          return null;
        }
        final ver = head[3];
        if (ver != 3 && ver != 4) return null;
        final tagSize = ((head[6] & 0x7f) << 21) |
            ((head[7] & 0x7f) << 14) |
            ((head[8] & 0x7f) << 7) |
            (head[9] & 0x7f);
        var off = 10;
        while (off + 10 <= tagSize) {
          raf.setPositionSync(off);
          final frame = raf.readSync(10);
          if (frame.length < 10) break;
          final id = String.fromCharCodes(frame.sublist(0, 4));
          if (id.isEmpty || id.codeUnitAt(0) == 0) break;
          final int size;
          if (ver == 4) {
            size = ((frame[4] & 0x7f) << 21) |
                ((frame[5] & 0x7f) << 14) |
                ((frame[6] & 0x7f) << 7) |
                (frame[7] & 0x7f);
          } else {
            size = (frame[4] << 24) |
                (frame[5] << 16) |
                (frame[6] << 8) |
                frame[7];
          }
          if (id == 'APIC' && size > 0 && size < 8 * 1024 * 1024) {
            raf.setPositionSync(off + 10);
            final data = raf.readSync(size);
            if (data.length >= 4) {
              var i = 1; // encoding byte
              final mimeStart = i;
              while (i < data.length && data[i] != 0) i++;
              if (i >= data.length) return null;
              final mime = String.fromCharCodes(data.sublist(mimeStart, i));
              i++; // NUL
              i++; // picture type
              while (i < data.length && data[i] != 0) i++;
              i++; // description NUL
              if (i < data.length && data.length - i > 64) {
                final pic = data.sublist(i);
                final ext = mime == 'image/png'
                    ? '.png'
                    : (mime == 'image/webp' ? '.webp' : '.jpg');
                final dir = await getApplicationDocumentsDirectory();
                final coverDir = Directory('${dir.path}/xmusic_covers');
                try {
                  await coverDir.create(recursive: true);
                } catch (_) {}
                final h = (pic.length ^ f.path.hashCode).abs();
                final cf = File('${coverDir.path}/$h$ext');
                if (!await cf.exists()) {
                  try {
                    await cf.writeAsBytes(pic);
                  } catch (_) {
                    return null;
                  }
                }
                return Uri.file(cf.path).toString();
              }
            }
            break; // 已找到 APIC，无论成败都结束遍历
          }
          off += 10 + size;
        }
      } finally {
        raf.closeSync();
      }
    } catch (_) {}
    return null;
  }

  /// 找本地歌词：同目录同名 .lrc（<歌曲基名>.lrc），存在返回文件内容，否则 null。
  static Future<String?> lrcFor(Song s) async {
    try {
      final p = Uri.tryParse(s.streamUrl ?? '')?.toFilePath();
      if (p == null || p.isEmpty) return null;
      final base = p.replaceFirst(RegExp(r'\.[^.]+$'), '');
      for (final c in ['$base.lrc', '$base.LRC']) {
        final f = File(c);
        if (await f.exists()) return f.readAsString();
      }
    } catch (_) {}
    return null;
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
          coverUrl: m['coverUrl']?.toString(),
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
                'coverUrl': s.coverUrl,
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
            var s = songFromFile(e);
            if ((s.coverUrl ?? '').isEmpty) {
              final cover = await extractId3Cover(e);
              if (cover != null) {
                s = Song(
                  id: s.id,
                  title: s.title,
                  artist: s.artist,
                  album: s.album,
                  coverArt: null,
                  coverUrl: cover,
                  durationSec: s.durationSec,
                  fromExternal: false,
                  streamUrl: s.streamUrl,
                );
              }
            }
            songs.add(s);
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
