import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'subsonic.dart';
import 'widgets.dart';

enum AppThemeMode { system, light, dark }

class AppSettings extends ChangeNotifier {
  static const double minScale = 0.7;
  static const double maxScale = 2.0;
  static const double scaleStep = 0.1;

  static const _kScale = 'lyric_scale';
  static const _kScaleP = 'lyric_scale_p';
  static const _kScaleL = 'lyric_scale_l';
  static const _kUrl = 'server_url';
  static const _kUser = 'username';
  static const _kSalt = 'salt';
  static const _kToken = 'token';
  static const _kTheme = 'theme_mode';
  static const _kExternal = 'external_api_url';
  static const _kDavUrl = 'webdav_url';
  static const _kDavUser = 'webdav_user';
  static const _kDavPass = 'webdav_pass';
  static const _kDavPath = 'webdav_path';
  static const _kDavName = 'webdav_name';
  static const _kBgColor = 'bg_color';
  static const _kCoverColorBg = 'cover_color_bg';
  static const _kLyricActive = 'lyric_active';
  static const _kLyricPast = 'lyric_past';
  static const _kLyricFuture = 'lyric_future';
  static const _kAutoPlay = 'auto_play';
  static const _kDownloadPath = 'download_path';
  static const _kQqCookie = 'qq_cookie';
  static const _kFilterOld = 'filter_old';
  static const _kOldYear = 'old_year';
  static const _kBlacklist = 'blacklist';
  static const _kSyncNas = 'sync_nas';
  static const _kEqPreset = 'eq_preset';
  static const _kEqCustom = 'eq_custom';
  static const _kImportedQq = 'imported_qq_playlists';
  static const _kNavHintDismissed = 'nav_hint_dismissed';
  static const _kSleepEnabled = 'sleep_timer_enabled';
  static const _kSleepMinutes = 'sleep_timer_minutes';
  static const _kSleepFade = 'sleep_fade_volume';
  /// 歌词默认色（"跟随默认"/从未设置时使用；避免 0 值在浅色主题被当成黑色）。
  /// [xmusic] 2026-09-27 修复：未设置或选"跟随默认"时当前走 onSurface（浅色=黑）。
  static const int lyricActiveDefault = 0xfffdd475; // 暖黄（当前行）
  static const int lyricPastDefault = 0xffdddddd;   // 浅灰（已唱）
  static const int lyricFutureDefault = 0xff00ff88; // 亮绿（未唱）

  late final SharedPreferences _prefs;

  String serverUrl = '';
  String username = '';
  String salt = '';
  String token = '';
  String externalApiUrl = '';
  String webdavUrl = '';
  String webdavUser = '';
  String webdavPass = '';
  String webdavPath = '';
  String webdavName = '';
  double _lyricScalePortrait = 1.0;
  double _lyricScaleLandscape = 1.0;
  int _bgColor = 0;
  bool _coverColorBg = true;
  int _lyricActive = lyricActiveDefault;
  int _lyricPast = lyricPastDefault;
  int _lyricFuture = lyricFutureDefault;
  bool _autoPlay = true;
  bool _filterOld = true;
  Set<String> _blacklist = {};
  bool _syncNas = false;
  int _blacklistRev = 0;
  int get blacklistRev => _blacklistRev;
  /// EQ 预设：off/pop/rock/electronic/classical/bass/vocal/custom。
  String eqPreset = 'off';
  /// 自定义 EQ 增益（逗号分隔 dB，如 "3,1,-1,1,3"）。
  String eqCustom = '';
  int _oldYear = 1995;
  bool _navHintDismissed = false;
  /// 未配置 Navidrome 时的"前往配置"提醒是否已勾选"下次不再提醒"。
  bool get navHintDismissed => _navHintDismissed;
  // ---- 睡前模式 ----
  bool _sleepEnabled = false;
  int _sleepMinutes = 30;
  bool _sleepFade = true;
  bool get sleepEnabled => _sleepEnabled;
  int get sleepMinutes => _sleepMinutes;
  bool get sleepFade => _sleepFade;
  Future<void> setSleepEnabled(bool v) async {
    _sleepEnabled = v;
    await _prefs.setBool(_kSleepEnabled, v);
    notifyListeners();
  }
  Future<void> setSleepMinutes(int v) async {
    _sleepMinutes = v.clamp(10, 90);
    await _prefs.setInt(_kSleepMinutes, _sleepMinutes);
    notifyListeners();
  }
  Future<void> setSleepFade(bool v) async {
    _sleepFade = v;
    await _prefs.setBool(_kSleepFade, v);
    notifyListeners();
  }
  String downloadPath = '';
  String qqCookie = '';
  /// 导入的 QQ 歌单列表（id + 歌单名），音乐库"导入歌单"门类使用。
  List<Map<String, String>> importedQqPlaylists = [];
  AppThemeMode _themeMode = AppThemeMode.system;

  double get lyricScale => _lyricScalePortrait;
  double lyricScaleFor(bool land) => land ? _lyricScaleLandscape : _lyricScalePortrait;
  int get bgColor => _bgColor;
  bool get coverColorBg => _coverColorBg;
  int get lyricActive => _lyricActive;
  int get lyricPast => _lyricPast;
  int get lyricFuture => _lyricFuture;
  bool get autoPlay => _autoPlay;
  bool get filterOld => _filterOld;
  int get oldYear => _oldYear;
  AppThemeMode get themeMode => _themeMode;
  bool get canIncreaseLyric => _lyricScalePortrait < maxScale - 1e-9;
  bool get canDecreaseLyric => _lyricScalePortrait > minScale + 1e-9;
  bool canIncreaseLyricFor(bool land) => (land ? _lyricScaleLandscape : _lyricScalePortrait) < maxScale - 1e-9;
  bool canDecreaseLyricFor(bool land) => (land ? _lyricScaleLandscape : _lyricScalePortrait) > minScale + 1e-9;
  bool get webdavConfigured => webdavUrl.trim().isNotEmpty;
  bool get syncNas => _syncNas;
  Future<void> setSyncNas(bool v) async {
    _syncNas = v;
    await _prefs.setBool(_kSyncNas, v);
    notifyListeners();
  }

  Future<void> setEqPreset(String v) async {
    eqPreset = v;
    notifyListeners();
    await _prefs.setString(_kEqPreset, v);
  }

  Future<void> setEqCustom(String v) async {
    eqCustom = v;
    notifyListeners();
    await _prefs.setString(_kEqCustom, v);
  }

  Future<void> setNavHintDismissed(bool v) async {
    _navHintDismissed = v;
    await _prefs.setBool(_kNavHintDismissed, v);
    notifyListeners();
  }

  bool get hasLogin =>
      serverUrl.isNotEmpty && username.isNotEmpty &&
      salt.isNotEmpty && token.isNotEmpty;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    serverUrl = _prefs.getString(_kUrl) ?? '';
    username = _prefs.getString(_kUser) ?? '';
    salt = _prefs.getString(_kSalt) ?? '';
    token = _prefs.getString(_kToken) ?? '';
    externalApiUrl = _prefs.getString(_kExternal) ?? '';
    webdavUrl = _prefs.getString(_kDavUrl) ?? '';
    webdavUser = _prefs.getString(_kDavUser) ?? '';
    webdavPass = _prefs.getString(_kDavPass) ?? '';
    webdavPath = _prefs.getString(_kDavPath) ?? '';
    webdavName = _prefs.getString(_kDavName) ?? '';
    _lyricScalePortrait = (_prefs.getDouble(_kScaleP) ?? _prefs.getDouble(_kScale) ?? 1.0).clamp(minScale, maxScale);
    _lyricScaleLandscape = (_prefs.getDouble(_kScaleL) ?? _lyricScalePortrait).clamp(minScale, maxScale);
    _themeMode = AppThemeMode.values[_prefs.getInt(_kTheme) ?? 0];
    _bgColor = _prefs.getInt(_kBgColor) ?? 0;
    _coverColorBg = true; // 用户明确要求封面透出，忽略旧 prefs 的 false
    _lyricActive = _prefs.getInt(_kLyricActive) ?? lyricActiveDefault;
    _lyricPast = _prefs.getInt(_kLyricPast) ?? lyricPastDefault;
    _lyricFuture = _prefs.getInt(_kLyricFuture) ?? lyricFutureDefault;
    _autoPlay = _prefs.getBool(_kAutoPlay) ?? true;
    _filterOld = _prefs.getBool(_kFilterOld) ?? true;
    _oldYear = _prefs.getInt(_kOldYear) ?? 1995;
    _blacklist = (_prefs.getStringList(_kBlacklist) ?? const []).toSet();
    _syncNas = _prefs.getBool(_kSyncNas) ?? false;
    eqPreset = _prefs.getString(_kEqPreset) ?? 'off';
    eqCustom = _prefs.getString(_kEqCustom) ?? '';
    _navHintDismissed = _prefs.getBool(_kNavHintDismissed) ?? false;
    _sleepEnabled = _prefs.getBool(_kSleepEnabled) ?? false;
    _sleepMinutes = (_prefs.getInt(_kSleepMinutes) ?? 30).clamp(10, 90);
    _sleepFade = _prefs.getBool(_kSleepFade) ?? true;
    unawaited(syncBlacklistPull()); // 启动时从 NAS 拉取合并黑名单
    downloadPath = _prefs.getString(_kDownloadPath) ?? '';
    qqCookie = _prefs.getString(_kQqCookie) ?? '';
    importedQqPlaylists = ((_prefs.getStringList(_kImportedQq) ?? const [])
        .map((e) => (jsonDecode(e) as Map).cast<String, String>())
        .toList());
  }

  SubsonicClient buildClient() {
    return SubsonicClient(
      baseUrl: serverUrl,
      username: username,
      salt: salt,
      token: token,
    );
  }

  Future<void> saveLogin(SubsonicClient client) async {
    serverUrl = client.baseUrl.trim();
    username = client.username.trim();
    salt = client.salt;
    token = client.token;
    notifyListeners();
    await _prefs.setString(_kUrl, serverUrl);
    await _prefs.setString(_kUser, username);
    await _prefs.setString(_kSalt, salt);
    await _prefs.setString(_kToken, token);
  }

  Future<void> clearLogin() async {
    serverUrl = '';
    username = '';
    salt = '';
    token = '';
    notifyListeners();
    await _prefs.remove(_kUrl);
    await _prefs.remove(_kUser);
    await _prefs.remove(_kSalt);
    await _prefs.remove(_kToken);
  }

  /// QQ音乐 Cookie（设置里填写后解锁 QQ 榜单/播放）。
  Future<void> setQqCookie(String v) async {
    qqCookie = v.trim();
    notifyListeners();
    if (qqCookie.isEmpty) {
      await _prefs.remove(_kQqCookie);
    } else {
      await _prefs.setString(_kQqCookie, qqCookie);
    }
  }

  /// 添加导入的 QQ 歌单（同 id 去重并置顶）。
  Future<void> addImportedQqPlaylist(String id, String name,
      {String cover = ''}) async {
    importedQqPlaylists.removeWhere((e) => e['id'] == id);
    importedQqPlaylists.insert(0, {
      'id': id,
      'name': name,
      if (cover.isNotEmpty) 'cover': cover,
    });
    notifyListeners();
    await _prefs.setStringList(
        _kImportedQq, importedQqPlaylists.map((e) => jsonEncode(e)).toList());
    unawaited(syncBlacklistPush()); // 同步导入歌单到 NAS
  }

  /// 补写导入歌单的封面（旧版导入的数据无 cover 字段，进 ID 歌单页时懒加载回写）。
  Future<void> updateImportedQqCover(String id, {String? cover}) async {
    if (cover == null || cover.trim().isEmpty) return;
    final i = importedQqPlaylists.indexWhere((e) => e['id'] == id);
    if (i < 0) return;
    final old = importedQqPlaylists[i];
    if ((old['cover'] ?? '').toString() == cover.trim()) return;
    importedQqPlaylists[i] = {
      'id': id,
      'name': old['name'] ?? '',
      'cover': cover.trim(),
    };
    notifyListeners();
    await _prefs.setStringList(
        _kImportedQq, importedQqPlaylists.map((e) => jsonEncode(e)).toList());
    // 不主动 push NAS（批量补封面避免刷屏），下次同步时自动带上 cover。
  }

  /// 删除导入的 QQ 歌单。
  Future<void> removeImportedQqPlaylist(String id) async {
    importedQqPlaylists.removeWhere((e) => e['id'] == id);
    notifyListeners();
    await _prefs.setStringList(
        _kImportedQq, importedQqPlaylists.map((e) => jsonEncode(e)).toList());
    unawaited(syncBlacklistPush());
  }

  /// 重命名导入的 QQ 歌单（改本地名并同步 NAS）。
  Future<void> renameImportedQqPlaylist(String id, String name) async {
    final i = importedQqPlaylists.indexWhere((e) => e['id'] == id);
    if (i < 0) return;
    importedQqPlaylists[i] = {'id': id, 'name': name};
    notifyListeners();
    await _prefs.setStringList(
        _kImportedQq, importedQqPlaylists.map((e) => jsonEncode(e)).toList());
    unawaited(syncBlacklistPush());
  }

  Future<void> setLyricScale(double v) async {
    v = v.clamp(minScale, maxScale);
    if ((v - _lyricScalePortrait).abs() < 0.01) return;
    _lyricScalePortrait = v;
    notifyListeners();
    await _prefs.setDouble(_kScale, v);
  }

  void increaseLyric() => setLyricScale(_lyricScalePortrait + scaleStep);
  void decreaseLyric() => setLyricScale(_lyricScalePortrait - scaleStep);

  Future<void> setLyricScaleFor(bool land, double v) async {
    v = v.clamp(minScale, maxScale);
    final cur = land ? _lyricScaleLandscape : _lyricScalePortrait;
    if ((v - cur).abs() < 0.01) return;
    if (land) { _lyricScaleLandscape = v; } else { _lyricScalePortrait = v; }
    notifyListeners();
    await _prefs.setDouble(land ? _kScaleL : _kScaleP, v);
  }

  void increaseLyricFor(bool land) => setLyricScaleFor(land, (land ? _lyricScaleLandscape : _lyricScalePortrait) + scaleStep);
  void decreaseLyricFor(bool land) => setLyricScaleFor(land, (land ? _lyricScaleLandscape : _lyricScalePortrait) - scaleStep);

  Future<void> setBgColor(int v) async {
    _bgColor = v;
    notifyListeners();
    await _prefs.setInt(_kBgColor, v);
  }

  Future<void> setCoverColorBg(bool v) async {
    _coverColorBg = v;
    notifyListeners();
    await _prefs.setBool(_kCoverColorBg, v);
  }

  Future<void> setLyricColors({int? active, int? past, int? future}) async {
    if (active != null) _lyricActive = active;
    if (past != null) _lyricPast = past;
    if (future != null) _lyricFuture = future;
    notifyListeners();
    await _prefs.setInt(_kLyricActive, _lyricActive);
    await _prefs.setInt(_kLyricPast, _lyricPast);
    await _prefs.setInt(_kLyricFuture, _lyricFuture);
  }

  Future<void> setAutoPlay(bool v) async {
    _autoPlay = v;
    notifyListeners();
    await _prefs.setBool(_kAutoPlay, v);
  }

  Future<void> setDownloadPath(String v) async {
    final path = v.trim();
    if (path == downloadPath) return;
    downloadPath = path;
    notifyListeners();
    await _prefs.setString(_kDownloadPath, path);
  }

  /// 是否过滤老歌（默认开）：仅剔除能确认发行年份早于阈值的歌，年份缺失不误杀。
  Future<void> setFilterOld(bool v) async {
    _filterOld = v;
    notifyListeners();
    await _prefs.setBool(_kFilterOld, v);
  }

  Future<void> setOldYear(int v) async {
    _oldYear = v;
    notifyListeners();
    await _prefs.setInt(_kOldYear, v);
  }

  /// 歌曲是否属于老歌（被过滤）：年份能确认且早于阈值。
  bool isOld(Song s) => s.year != null && s.year! < _oldYear;

  /// 歌曲黑名单（不喜欢）：跨源按 "标题|歌手" 判重，加入后不再出现在排行榜/歌单/推荐。
  // 黑名单按歌手过滤：加入一首即屏蔽该歌手全部（解决热歌榜同歌手刷屏）
  static String _songKey(Song s) =>
      (s.artist.isNotEmpty ? s.artist : s.title).toLowerCase().trim();
  bool isBlacklisted(Song s) {
    final a = (s.artist.isNotEmpty ? s.artist : s.title).toLowerCase().trim();
    if (a.isEmpty) return false;
    // 部分匹配：榜单/歌单里的歌手可能带 feat、多歌手（如"檀健次、王心凌"），黑名单含其主歌手即滤
    return _blacklist.any((k) {
      final kk = k.toLowerCase().trim();
      if (kk.isEmpty) return false;
      return a == kk || a.contains(kk) || kk.contains(a);
    });
  }
  Future<void> addBlacklist(Song s) async {
    _blacklist.add(_songKey(s));
    _blacklistRev++;
    notifyListeners();
    await _prefs.setStringList(_kBlacklist, _blacklist.toList());
    unawaited(syncBlacklistPush());
  }
  Future<void> removeBlacklist(Song s) async {
    _blacklist.remove(_songKey(s));
    _blacklistRev++;
    notifyListeners();
    await _prefs.setStringList(_kBlacklist, _blacklist.toList());
    unawaited(syncBlacklistPush());
  }

  /// 黑名单条目（歌手/歌名），供设置界面查看
  List<String> get blacklistItems => _blacklist.toList();

  /// 按 key 删除黑名单条目
  Future<void> removeBlacklistKey(String key) async {
    _blacklist.remove(key);
    _blacklistRev++;
    notifyListeners();
    await _prefs.setStringList(_kBlacklist, _blacklist.toList());
    unawaited(syncBlacklistPush());
  }

  // ---- 黑名单 NAS(WebDAV) 同步：收藏在 Navidrome 服务器端自动互通，黑名单本机存储需云同步 ----
  String _nasUrl(String file) {
    final base = webdavUrl.replaceAll(RegExp(r'/+$'), '');
    final sub = (webdavPath.trim().isEmpty ? 'Music/xmusic' : webdavPath.trim())
        .replaceAll(RegExp(r'^/|/$'), '');
    return '$base/$sub/$file';
  }
  Map<String, String> _davHeaders() {
    final auth = base64Encode(utf8.encode('${webdavUser}:${webdavPass}'));
    return {
      'Authorization': 'Basic $auth',
      'Content-Type': 'application/json',
    };
  }
  /// 上传黑名单 + 导入歌单到 NAS；返回 null=成功，否则为可展示的失败原因。
  Future<String?> syncBlacklistPush() async {
    if (!_syncNas) return '未开启"同步到 NAS"开关';
    if (!webdavConfigured) return '未配置 WebDAV 地址';
    try {
      final url = Uri.parse(_nasUrl('xmusic_blacklist.json'));
      // 尝试用 MKCOL 自动创建目录（失败忽略，PUT 仍会执行并返回真实错误）
      try {
        final dir = Uri.parse(_nasUrl(''));
        final mk = http.Request('MKCOL', dir);
        mk.headers['Authorization'] = _davHeaders()['Authorization']!;
        await mk.send().timeout(const Duration(seconds: 8));
      } catch (_) {}
      final resp = await http
          .put(url, headers: _davHeaders(), body: jsonEncode({
            'blacklist': _blacklist.toList(),
            'qqplaylists': importedQqPlaylists,
          }))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode < 300) return null;
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return 'NAS 拒绝访问(${resp.statusCode})：检查 WebDAV 账号密码';
      }
      if (resp.statusCode == 404 || resp.statusCode == 409) {
        return 'NAS 返回 ${resp.statusCode}：检查 WebDAV 地址路径和 Music/xmusic 目录';
      }
      return 'NAS 返回 ${resp.statusCode}';
    } catch (e) {
      return '连接失败：${e.runtimeType}（检查地址/端口/frpc 转发）';
    }
  }
  /// 从 NAS 拉取黑名单 + 导入歌单并合并
  Future<void> syncBlacklistPull() async {
    if (!_syncNas || !webdavConfigured) return;
    try {
      final resp = await http.get(
        Uri.parse(_nasUrl('xmusic_blacklist.json')),
        headers: {'Authorization': _davHeaders()['Authorization']!},
      );
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
        if (decoded is List) {
          // 旧格式：只有黑名单
          final merged = {..._blacklist, ...decoded.cast<String>().toSet()};
          if (merged.length != _blacklist.length) {
            _blacklist = merged;
            await _prefs.setStringList(_kBlacklist, _blacklist.toList());
            notifyListeners();
          }
        } else if (decoded is Map) {
          final merged =
              {..._blacklist, ...((decoded['blacklist'] as List?) ?? const []).cast<String>().toSet()};
          if (merged.length != _blacklist.length) {
            _blacklist = merged;
            await _prefs.setStringList(_kBlacklist, _blacklist.toList());
            notifyListeners();
          }
          final remotePl = ((decoded['qqplaylists'] as List?) ?? const [])
              .cast<Map>()
              .map((m) => {
                    'id': (m['id'] ?? '').toString(),
                    'name': (m['name'] ?? '').toString(),
                    if (((m['cover'] ?? '') as String).isNotEmpty)
                      'cover': (m['cover'] ?? '').toString(),
                  })
              .toList();
          var plChanged = false;
          for (final rp in remotePl) {
            if (rp['id']!.isEmpty) continue;
            if (!importedQqPlaylists.any((e) => e['id'] == rp['id'])) {
              importedQqPlaylists.add(rp);
              plChanged = true;
            }
          }
          if (plChanged) {
            await _prefs.setStringList(_kImportedQq,
                importedQqPlaylists.map((e) => jsonEncode(e)).toList());
            notifyListeners();
          }
        }
      }
    } catch (_) {}
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _prefs.setInt(_kTheme, mode.index);
  }

  Future<void> setExternalApiUrl(String url) async {
    final v = url.trim();
    if (v == externalApiUrl) return;
    externalApiUrl = v;
    notifyListeners();
    await _prefs.setString(_kExternal, v);
  }

  Future<void> setWebdav(String url, String user, String pass, {String path = '', String name = ''}) async {
    webdavUrl = url.trim();
    webdavUser = user.trim();
    webdavPass = pass;
    webdavPath = path.trim();
    webdavName = name.trim();
    notifyListeners();
    await _prefs.setString(_kDavUrl, webdavUrl);
    await _prefs.setString(_kDavUser, webdavUser);
    await _prefs.setString(_kDavPass, webdavPass);
    await _prefs.setString(_kDavPath, webdavPath);
    await _prefs.setString(_kDavName, webdavName);
  }
}
