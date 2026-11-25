import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'subsonic.dart';
import 'widgets.dart';
import 'audio_handler.dart';

enum AppThemeMode { system, light, dark }

class AppSettings extends ChangeNotifier {
  static const double minScale = 0.2;
  static const double maxScale = 4.0;
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
  static const _kImportedQq = 'imported_qq_playlists';
  static const _kNavHintDismissed = 'nav_hint_dismissed';
  static const _kSleepEnabled = 'sleep_timer_enabled';
  static const _kSleepMinutes = 'sleep_timer_minutes';
  static const _kSleepFade = 'sleep_fade_volume';
  static const _kCarBottomInset = 'car_bottom_inset';
  static const _kListTextScale = 'list_text_scale';
  static const _kCarTopInset = 'car_top_inset';
  static const _kTvMode = 'tv_mode';
  // ---- 播放页布局自定义（倍率默认 1.0 = 原样；距顶/距底 dp 默认 0 = 用原值） ----
  static const _kPlayerCoverScale = 'player_cover_scale';
  static const _kPlayerLyricFontScale = 'player_lyric_font_scale';
  static const _kPlayerLyricLineScale = 'player_lyric_line_scale';
  static const _kPlayerControlGapScale = 'player_control_gap_scale';
  static const _kPlayerIconScale = 'player_icon_scale';
  static const _kPlayerMarginScale = 'player_margin_scale';
  static const _kPlayerTopPad = 'player_top_pad';
  static const _kPlayerBottomPad = 'player_bottom_pad';
  static const _kPlayerTopPadLand = 'player_top_pad_land';
  static const _kPlayerBottomPadLand = 'player_bottom_pad_land';
  // ---- 播放页高级细分参数（统一倍率 key，默认 1.0 = 原样） ----
  static const playerAdvKeys = <String>[
    'titleFont',        // 歌名字号
    'artistFont',       // 歌手/专辑字号
    'titleGap',         // 歌名-歌手间距
    'cornerIcon',       // 首页/返回图标大小
    'cornerGap',        // 首页/返回图标与歌名间距
    'controlIcon',      // 控制栏播放/上下曲图标大小
    'sideIcon',         // 侧栏图标大小（首页/返回钮不受此参数影响）
    'sideGap',          // 侧栏图标间距
    'lyricMargin',      // 歌词左右边距
    'seekGap',          // 进度条区上下间距
    'queueTitleFont',   // 播放列表歌名字号
    'queueArtistFont',  // 播放列表歌手字号
  ];
  static const _kPlayerAdvPrefix = 'player_adv_';
  // ---- 播放页区域纵向占比（倍率默认 1.0 = 原 flex/高度） ----
  static const playerAreaKeys = <String>[
    'pathArea',     // 路径区（来源文字行）高度占比
    'coverArea',    // 封面区高度/flex 占比
    'lyricArea',    // 歌词区高度/flex 占比
    'titleArea',    // 歌名区高度占比
    'controlArea',  // 控制栏区高度占比
  ];
  // ---- 播放页横屏双轴占比（x: 封面/歌词宽度；y: 路径/中部/歌名/控制栏） ----
  static const playerLandXKeys = <String>[
    'landXCover',   // 封面宽度占比
    'landXLyric',   // 歌词宽度占比（含左右侧栏）
  ];
  static const playerLandYKeys = <String>[
    'landYPath',    // 路径行高度占比
    'landYMid',     // 中部高度占比（封面+歌词统一调整）
    'landYTitle',   // 歌名区高度占比
    'landYControl', // 控制栏+进度条高度占比
  ];
  /// 全部区域 key（竖屏 5 + 横屏 x2 + 横屏 y4），load/reset 用。
  static List<String> get playerAllAreaKeys =>
      <String>[...playerAreaKeys, ...playerLandXKeys, ...playerLandYKeys];
  static const _kPlayerAreaPrefix = 'player_area_';
  // ---- EQ / 封面样式 ----
  static const _kEqPreset = 'eq_preset';
  static const _kEqCustom = 'eq_custom';
  static const _kCoverStyle = 'cover_style';
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
  int _oldYear = 1995;
  bool _navHintDismissed = false;
  /// 未配置 Navidrome 时的"前往配置"提醒是否已勾选"下次不再提醒"。
  bool get navHintDismissed => _navHintDismissed;
  // ---- 睡前模式 ----
  bool _sleepEnabled = false;
  int _sleepMinutes = 30;
  bool _sleepFade = true;
  /// 车机横屏底部避让高度（dp）：迪友桌面自绘导航条不进入 WindowInsets，
  /// 需要在设置里按实机调整，默认 48dp。
  double _carBottomInset = 48.0;
  double get carBottomInset => _carBottomInset;
  static const double minCarBottomInset = 0.0;
  static const double maxCarBottomInset = 120.0;
  Future<void> setCarBottomInset(double v) async {
    _carBottomInset = v.clamp(minCarBottomInset, maxCarBottomInset);
    await _prefs.setDouble(_kCarBottomInset, _carBottomInset);
    notifyListeners();
  }
  /// 车机横屏顶部避让（dp）：迪友桌面顶部状态条是自绘悬浮层，不进 WindowInsets。
  /// 默认 0 = 顶部不留白；若顶部内容被状态条盖住，在设置里按实机调大。
  double _carTopInset = 0.0;
  double get carTopInset => _carTopInset;
  static const double minCarTopInset = 0.0;
  static const double maxCarTopInset = 120.0;
  Future<void> setCarTopInset(double v) async {
    _carTopInset = v.clamp(minCarTopInset, maxCarTopInset);
    await _prefs.setDouble(_kCarTopInset, _carTopInset);
    notifyListeners();
  }
  /// TV 模式（遥控器操作）开关。开启后：
  /// 1) 顶部/底部避让改为电视过扫描安全区，不再套用「车机迪友桌面」避让；
  /// 2) 列表项与按钮获得焦点边框，方向键可导航、OK/确认键激活；
  /// 3) 支持遥控器媒体键（播放/暂停/上一曲/下一曲）。
  bool _tvMode = false;
  bool get tvMode => _tvMode;
  Future<void> setTvMode(bool v) async {
    if (v == _tvMode) return;
    _tvMode = v;
    await _prefs.setBool(_kTvMode, v);
    notifyListeners();
  }
  // ---- 播放页布局参数（全部中性默认，保证零回归） ----
  static const double minPlayerScale = 0.5;
  static const double maxPlayerScale = 2.0;
  /// [xmusic] 歌词字号独立范围：放宽 0.2~4.0x（原 0.5~2.0 限制解除）。
  static const double minLyricFontScale = 0.2;
  static const double maxLyricFontScale = 4.0;
  double _playerCoverScale = 1.0;
  double get playerCoverScale => _playerCoverScale;
  double _playerLyricFontScale = 1.0;
  double get playerLyricFontScale => _playerLyricFontScale;
  double _playerLyricLineScale = 1.0;
  double get playerLyricLineScale => _playerLyricLineScale;
  double _playerControlGapScale = 1.0;
  double get playerControlGapScale => _playerControlGapScale;
  double _playerIconScale = 1.0;
  double get playerIconScale => _playerIconScale;
  double _playerMarginScale = 1.0;
  double get playerMarginScale => _playerMarginScale;
  double _playerTopPad = 0.0;
  double get playerTopPad => _playerTopPad;
  double _playerBottomPad = 0.0;
  double get playerBottomPad => _playerBottomPad;
  double _playerTopPadLand = 0.0;
  double get playerTopPadLand => _playerTopPadLand;
  double _playerBottomPadLand = 0.0;
  double get playerBottomPadLand => _playerBottomPadLand;
  Future<void> setPlayerCoverScale(double v) async {
    _playerCoverScale = v.clamp(minPlayerScale, maxPlayerScale);
    await _prefs.setDouble(_kPlayerCoverScale, _playerCoverScale);
    notifyListeners();
  }
  Future<void> setPlayerLyricFontScale(double v) async {
    _playerLyricFontScale = v.clamp(minLyricFontScale, maxLyricFontScale);
    await _prefs.setDouble(_kPlayerLyricFontScale, _playerLyricFontScale);
    notifyListeners();
  }
  Future<void> setPlayerLyricLineScale(double v) async {
    _playerLyricLineScale = v.clamp(minPlayerScale, maxPlayerScale);
    await _prefs.setDouble(_kPlayerLyricLineScale, _playerLyricLineScale);
    notifyListeners();
  }
  Future<void> setPlayerControlGapScale(double v) async {
    _playerControlGapScale = v.clamp(0.5, 3.0);
    await _prefs.setDouble(_kPlayerControlGapScale, _playerControlGapScale);
    notifyListeners();
  }
  Future<void> setPlayerIconScale(double v) async {
    _playerIconScale = v.clamp(0.5, 2.0);
    await _prefs.setDouble(_kPlayerIconScale, _playerIconScale);
    notifyListeners();
  }
  Future<void> setPlayerMarginScale(double v) async {
    _playerMarginScale = v.clamp(0.0, 3.0);
    await _prefs.setDouble(_kPlayerMarginScale, _playerMarginScale);
    notifyListeners();
  }
  Future<void> setPlayerTopPad(double v) async {
    _playerTopPad = v.clamp(-40.0, 120.0);
    await _prefs.setDouble(_kPlayerTopPad, _playerTopPad);
    notifyListeners();
  }
  Future<void> setPlayerBottomPad(double v) async {
    _playerBottomPad = v.clamp(-40.0, 120.0);
    await _prefs.setDouble(_kPlayerBottomPad, _playerBottomPad);
    notifyListeners();
  }
  Future<void> setPlayerTopPadLand(double v) async {
    _playerTopPadLand = v.clamp(-40.0, 120.0);
    await _prefs.setDouble(_kPlayerTopPadLand, _playerTopPadLand);
    notifyListeners();
  }
  Future<void> setPlayerBottomPadLand(double v) async {
    _playerBottomPadLand = v.clamp(-40.0, 120.0);
    await _prefs.setDouble(_kPlayerBottomPadLand, _playerBottomPadLand);
    notifyListeners();
  }
  // ---- 播放页高级细分参数：统一 Map 存储（默认 1.0 = 原样） ----
  final Map<String, double> _playerAdv = {};
  double playerAdv(String key) => _playerAdv[key] ?? 1.0;
  Future<void> setPlayerAdv(String key, double v) async {
    final val = v.clamp(0.3, 3.0);
    _playerAdv[key] = val;
    await _prefs.setDouble(_kPlayerAdvPrefix + key, val);
    notifyListeners();
  }
  // ---- 区域占比 Map（权重，归一化后 5 区总和恒为 100%，此消彼长） ----
  final Map<String, double> _playerArea = {};
  double playerAreaRaw(String key) => _playerArea[key] ?? 1.0;
  double get _playerAreaTotal {
    double t = 0;
    for (final k in playerAreaKeys) {
      t += (_playerArea[k] ?? 1.0);
    }
    return t <= 0 ? playerAreaKeys.length.toDouble() : t;
  }
  /// 归一化倍率：默认各 1.00x；某区调大，其余区自动变小（占比总和恒为 100%）。
  double playerArea(String key) =>
      playerAreaRaw(key) / _playerAreaTotal * playerAreaKeys.length;
  /// 该区百分比（5 区之和恒为 100%）。
  double playerAreaPct(String key) => playerAreaRaw(key) / _playerAreaTotal * 100.0;
  /// 设置某区占比百分比（2%~80%）：其余区按当前权重比例自动缩小（此消彼长）。
  Future<void> setPlayerAreaPct(String key, double pct) async {
    final p = (pct / 100.0).clamp(0.02, 0.80);
    double others = 0;
    for (final k in playerAreaKeys) {
      if (k != key) others += (_playerArea[k] ?? 1.0);
    }
    if (others <= 0) others = playerAreaKeys.length - 1.0;
    final val = (p * others / (1 - p)).clamp(0.05, 30.0);
    _playerArea[key] = val;
    await _prefs.setDouble(_kPlayerAreaPrefix + key, val);
    notifyListeners();
  }
  /// 分组内百分比（组内权重归一，总和恒 100%）。横屏 x/y 轴用。
  double groupPct(List<String> keys, String key) {
    double t = 0;
    for (final k in keys) {
      t += (_playerArea[k] ?? 1.0);
    }
    if (t <= 0) t = keys.length.toDouble();
    return (_playerArea[key] ?? 1.0) / t * 100.0;
  }
  /// 设置分组内某项百分比（2%~92%）：其余项按权重比例自动缩小（此消彼长）。
  Future<void> setGroupPct(List<String> keys, String key, double pct) async {
    final p = (pct / 100.0).clamp(0.02, 0.92);
    double others = 0;
    for (final k in keys) {
      if (k != key) others += (_playerArea[k] ?? 1.0);
    }
    if (others <= 0) others = keys.length - 1.0;
    final val = (p * others / (1 - p)).clamp(0.05, 30.0);
    _playerArea[key] = val;
    await _prefs.setDouble(_kPlayerAreaPrefix + key, val);
    notifyListeners();
  }
  // ---- 均衡器（EQ） ----
  /// 'off'/'flat'/'bass'/'vocal'/'stereo'/'pop'/'rock'/'classical'/'jazz'/'electronic'/'custom'
  String _eqPreset = 'off';
  List<double> _eqCustomGains = [0, 0, 0, 0, 0];
  String get eqPreset => _eqPreset;
  List<double> get eqCustomGains => _eqCustomGains;
  Future<void> _applyEq() =>
      applyEqualizer(preset: _eqPreset, customGains: _eqCustomGains);
  Future<void> setEqPreset(String v) async {
    _eqPreset = v;
    await _prefs.setString(_kEqPreset, v);
    await _applyEq();
    notifyListeners();
  }
  /// 拖自定义段滑块：自动切到 custom 预设并即时应用。
  Future<void> setEqCustomGain(int index, double v) async {
    _eqCustomGains[index] = v.clamp(-15.0, 15.0);
    _eqPreset = 'custom';
    await _prefs.setString(_kEqCustom, _eqCustomGains.join(','));
    await _prefs.setString(_kEqPreset, 'custom');
    await _applyEq();
    notifyListeners();
  }
  // ---- 封面样式：classic 经典 / vinyl 唱片 / iphone ----
  String _coverStyle = 'classic';
  String get coverStyle => _coverStyle;
  Future<void> setCoverStyle(String v) async {
    _coverStyle = v;
    await _prefs.setString(_kCoverStyle, v);
    notifyListeners();
  }

  // ---- 首页 UI：卡片图片大小 / 标题字号 ----
  double _homeCardScale = 1.0;
  double _homeTitleFont = 1.0;
  double get homeCardScale => _homeCardScale;
  double get homeTitleFont => _homeTitleFont;
  Future<void> setHomeCardScale(double v) async {
    _homeCardScale = v.clamp(0.6, 1.8);
    await _prefs.setDouble('home_card_scale', _homeCardScale);
    notifyListeners();
  }

  Future<void> setHomeTitleFont(double v) async {
    _homeTitleFont = v.clamp(0.6, 2.0);
    await _prefs.setDouble('home_title_font', _homeTitleFont);
    notifyListeners();
  }

  /// 播放页布局是否仍全部为中性默认（用于面板显示"恢复默认"状态）。
  bool get playerLayoutIsDefault =>
      _playerCoverScale == 1.0 && _playerLyricFontScale == 1.0 &&
      _playerLyricLineScale == 1.0 && _playerControlGapScale == 1.0 &&
      _playerIconScale == 1.0 && _playerMarginScale == 1.0 &&
      _playerTopPad == 0.0 && _playerBottomPad == 0.0 &&
      _playerTopPadLand == 0.0 && _playerBottomPadLand == 0.0 &&
      playerAdvKeys.every((k) => playerAdv(k) == 1.0) &&
      playerAllAreaKeys.every((k) => playerAreaRaw(k) == 1.0);
  Future<void> resetPlayerLayout() async {
    _playerCoverScale = 1.0; _playerLyricFontScale = 1.0;
    _playerLyricLineScale = 1.0; _playerControlGapScale = 1.0;
    _playerIconScale = 1.0; _playerMarginScale = 1.0;
    _playerTopPad = 0.0; _playerBottomPad = 0.0;
    _playerTopPadLand = 0.0; _playerBottomPadLand = 0.0;
    await _prefs.remove(_kPlayerCoverScale);
    await _prefs.remove(_kPlayerLyricFontScale);
    await _prefs.remove(_kPlayerLyricLineScale);
    await _prefs.remove(_kPlayerControlGapScale);
    await _prefs.remove(_kPlayerIconScale);
    await _prefs.remove(_kPlayerMarginScale);
    await _prefs.remove(_kPlayerTopPad);
    await _prefs.remove(_kPlayerBottomPad);
    await _prefs.remove(_kPlayerTopPadLand);
    await _prefs.remove(_kPlayerBottomPadLand);
    for (final k in playerAdvKeys) {
      _playerAdv.remove(k);
      await _prefs.remove(_kPlayerAdvPrefix + k);
    }
    for (final k in playerAllAreaKeys) {
      _playerArea.remove(k);
      await _prefs.remove(_kPlayerAreaPrefix + k);
    }
    notifyListeners();
  }
  /// 排行榜/歌单列表文字大小：车机全局 1.5x 缩放会把双行列表撑到一屏只剩 2 首，
  /// 列表页单独用这个缩放（默认 1.0），在设置里可调。
  double _listTextScale = 1.0;
  double get listTextScale => _listTextScale;
  static const double minListTextScale = 0.8;
  static const double maxListTextScale = 1.4;
  Future<void> setListTextScale(double v) async {
    _listTextScale = v.clamp(minListTextScale, maxListTextScale);
    await _prefs.setDouble(_kListTextScale, _listTextScale);
    notifyListeners();
  }

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
    _navHintDismissed = _prefs.getBool(_kNavHintDismissed) ?? false;
    _sleepEnabled = _prefs.getBool(_kSleepEnabled) ?? false;
    _sleepMinutes = (_prefs.getInt(_kSleepMinutes) ?? 30).clamp(10, 90);
    _sleepFade = _prefs.getBool(_kSleepFade) ?? true;
    _carBottomInset = (_prefs.getDouble(_kCarBottomInset) ?? 48.0)
        .clamp(minCarBottomInset, maxCarBottomInset);
    _listTextScale = (_prefs.getDouble(_kListTextScale) ?? 1.0)
        .clamp(minListTextScale, maxListTextScale);
    _carTopInset = (_prefs.getDouble(_kCarTopInset) ?? 0.0)
        .clamp(minCarTopInset, maxCarTopInset);
    _tvMode = _prefs.getBool(_kTvMode) ?? false;
    _playerCoverScale = (_prefs.getDouble(_kPlayerCoverScale) ?? 1.0).clamp(minPlayerScale, maxPlayerScale);
    _playerLyricFontScale = (_prefs.getDouble(_kPlayerLyricFontScale) ?? 1.0).clamp(minLyricFontScale, maxLyricFontScale);
    _playerLyricLineScale = (_prefs.getDouble(_kPlayerLyricLineScale) ?? 1.0).clamp(minPlayerScale, maxPlayerScale);
    _playerControlGapScale = (_prefs.getDouble(_kPlayerControlGapScale) ?? 1.0).clamp(0.5, 3.0);
    _playerIconScale = (_prefs.getDouble(_kPlayerIconScale) ?? 1.0).clamp(0.5, 2.0);
    _playerMarginScale = (_prefs.getDouble(_kPlayerMarginScale) ?? 1.0).clamp(0.0, 3.0);
    _playerTopPad = (_prefs.getDouble(_kPlayerTopPad) ?? 0.0).clamp(-40.0, 120.0);
    _playerBottomPad = (_prefs.getDouble(_kPlayerBottomPad) ?? 0.0).clamp(-40.0, 120.0);
    _playerTopPadLand = (_prefs.getDouble(_kPlayerTopPadLand) ?? 0.0).clamp(-40.0, 120.0);
    _playerBottomPadLand = (_prefs.getDouble(_kPlayerBottomPadLand) ?? 0.0).clamp(-40.0, 120.0);
    for (final k in playerAdvKeys) {
      final v = _prefs.getDouble(_kPlayerAdvPrefix + k);
      if (v != null) _playerAdv[k] = v.clamp(0.3, 3.0);
    }
    for (final k in playerAllAreaKeys) {
      final v = _prefs.getDouble(_kPlayerAreaPrefix + k);
      if (v != null) _playerArea[k] = v.clamp(0.05, 30.0);
    }
    // EQ / 封面样式恢复
    _eqPreset = _prefs.getString(_kEqPreset) ?? 'off';
    _eqCustomGains = (_prefs.getString(_kEqCustom) ?? '')
        .split(',')
        .map((e) => double.tryParse(e.trim()) ?? 0.0)
        .toList();
    while (_eqCustomGains.length < 5) {
      _eqCustomGains.add(0.0);
    }
    _coverStyle = _prefs.getString(_kCoverStyle) ?? 'classic';
    _homeCardScale = _prefs.getDouble('home_card_scale') ?? 1.0;
    _homeTitleFont = _prefs.getDouble('home_title_font') ?? 1.0;
    unawaited(_applyEq());
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

/// 车机横屏底部避让统一计算。
/// 迪友桌面（com.dy.launcher）的底部导航条是应用自绘的悬浮容器
/// （manifest 声明 SYSTEM_ALERT_WINDOW，布局 navigation_bar_container_layout.xml），
/// 不进入系统 WindowInsets；且 xmusic 横屏启用了 immersiveSticky，
/// MediaQuery.padding.bottom 会被清零，所以不能只看 padding。
/// 取「系统 viewPadding.bottom」与「设置里的车机避让值」的较大者；
/// 手机 / 车机竖屏沿用系统 inset。
double carBottomInsetOf(BuildContext context, AppSettings settings) {
  final mq = MediaQuery.of(context);
  final isCarScreen = mq.size.shortestSide >= 480;
  final isLandscape = mq.size.width > mq.size.height;
  // TV 模式：不走车机迪友桌面避让，改用电视过扫描安全区
  if (settings.tvMode) return tvSafeInsetOf(context);
  if (!isCarScreen || !isLandscape) return mq.padding.bottom;
  final sys = mq.viewPadding.bottom;
  return sys > settings.carBottomInset ? sys : settings.carBottomInset;
}

/// 电视过扫描安全区（TV safe area / overscan）：电视边缘约 5% 不显示内容，
/// 留出固定内边距避免画面被裁切。仅在 TV 模式生效；车机仍走迪友桌面避让。
double tvSafeInsetOf(BuildContext context) {
  return 48.0;
}

/// 车机横屏顶部避让统一计算。
/// 迪友桌面顶部状态条是自绘悬浮容器（status_bar_container_layout.xml，
/// layout_height=@dimen/dp_30），不进系统 WindowInsets，只能按实机调。
/// 原先 home_shell 写死 28dp 顶部 padding，叠加三个 tab 各自空 AppBar 的
/// 56dp 标题区（音乐库还有 48dp TabBar），形成一条没有内容的顶部空白。
/// 现在空标题区压到 0，顶部只取设置里的可调值（默认 0 = 不留白）；
/// 手机 / 车机竖屏保持原行为 0，由各自 Scaffold / AppBar 处理系统栏。
double carTopInsetOf(BuildContext context, AppSettings settings) {
  final mq = MediaQuery.of(context);
  final isCarScreen = mq.size.shortestSide >= 480;
  final isLandscape = mq.size.width > mq.size.height;
  // TV 模式：不走车机迪友桌面避让，改用电视过扫描安全区
  if (settings.tvMode) return tvSafeInsetOf(context);
  if (!isCarScreen || !isLandscape) return 0.0;
  return settings.carTopInset;
}
