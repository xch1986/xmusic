import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'subsonic.dart';

enum AppThemeMode { system, light, dark }

class AppSettings extends ChangeNotifier {
  static const double minScale = 0.7;
  static const double maxScale = 2.0;
  static const double scaleStep = 0.1;

  static const _kScale = 'lyric_scale';
  static const _kGlass = 'glass_opacity';
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
  static const _kLyricActive = 'lyric_active';
  static const _kLyricPast = 'lyric_past';
  static const _kLyricFuture = 'lyric_future';
  static const _kAutoPlay = 'auto_play';
  static const _kDownloadPath = 'download_path';

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
  double _lyricScale = 1.0;
  double _glassOpacity = 0.15;
  int _bgColor = 0;
  int _lyricActive = 0;
  int _lyricPast = 0;
  int _lyricFuture = 0;
  bool _autoPlay = true;
  String downloadPath = '';
  AppThemeMode _themeMode = AppThemeMode.system;

  double get lyricScale => _lyricScale;
  double get glassOpacity => _glassOpacity;
  int get bgColor => _bgColor;
  int get lyricActive => _lyricActive;
  int get lyricPast => _lyricPast;
  int get lyricFuture => _lyricFuture;
  bool get autoPlay => _autoPlay;
  AppThemeMode get themeMode => _themeMode;
  bool get canIncreaseLyric => _lyricScale < maxScale - 1e-9;
  bool get canDecreaseLyric => _lyricScale > minScale + 1e-9;
  bool get webdavConfigured => webdavUrl.trim().isNotEmpty;

  bool get hasLogin =>
      serverUrl.isNotEmpty && username.isNotEmpty &&
      salt.isNotEmpty && token.isNotEmpty;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    serverUrl = _prefs.getString(_kUrl) ?? '';
    username = _prefs.getString(_kUser) ?? '';
    salt = _prefs.getString(_kSalt) ?? '';
    token = _prefs.getString(_kToken) ?? '';
    externalApiUrl = _prefs.getString(_kExternal) ?? 'https://music-api.gdstudio.xyz';
    webdavUrl = _prefs.getString(_kDavUrl) ?? '';
    webdavUser = _prefs.getString(_kDavUser) ?? '';
    webdavPass = _prefs.getString(_kDavPass) ?? '';
    webdavPath = _prefs.getString(_kDavPath) ?? '';
    webdavName = _prefs.getString(_kDavName) ?? '';
    _lyricScale = (_prefs.getDouble(_kScale) ?? 1.0).clamp(minScale, maxScale);
    _glassOpacity = (_prefs.getDouble(_kGlass) ?? 0.15).clamp(0.0, 1.0);
    _themeMode = AppThemeMode.values[_prefs.getInt(_kTheme) ?? 0];
    _bgColor = _prefs.getInt(_kBgColor) ?? 0;
    _lyricActive = _prefs.getInt(_kLyricActive) ?? 0;
    _lyricPast = _prefs.getInt(_kLyricPast) ?? 0;
    _lyricFuture = _prefs.getInt(_kLyricFuture) ?? 0;
    _autoPlay = _prefs.getBool(_kAutoPlay) ?? true;
    downloadPath = _prefs.getString(_kDownloadPath) ?? '';
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

  Future<void> setLyricScale(double v) async {
    v = v.clamp(minScale, maxScale);
    if ((v - _lyricScale).abs() < 0.01) return;
    _lyricScale = v;
    notifyListeners();
    await _prefs.setDouble(_kScale, v);
  }

  void increaseLyric() => setLyricScale(_lyricScale + scaleStep);
  void decreaseLyric() => setLyricScale(_lyricScale - scaleStep);

  Future<void> setGlassOpacity(double v) async {
    v = v.clamp(0.0, 1.0);
    if ((v - _glassOpacity).abs() < 0.01) return;
    _glassOpacity = v;
    notifyListeners();
    await _prefs.setDouble(_kGlass, v);
  }

  Future<void> setBgColor(int v) async {
    _bgColor = v;
    notifyListeners();
    await _prefs.setInt(_kBgColor, v);
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
