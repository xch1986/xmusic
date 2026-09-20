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
