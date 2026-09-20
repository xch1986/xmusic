import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'subsonic.dart';

/// Theme mode persisted: 0 = system, 1 = light, 2 = dark.
enum AppThemeMode { system, light, dark }

/// App-wide persisted settings: login info, lyric size scale and theme mode.
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
  static const _kExternal = 'external_api_url';

  late final SharedPreferences _prefs;

  String serverUrl = '';
  String username = '';
  String salt = '';
  String token = '';
  String externalApiUrl = '';
  double _lyricScale = 1.0;
  AppThemeMode _themeMode = AppThemeMode.system;

  double get lyricScale => _lyricScale;
  AppThemeMode get themeMode => _themeMode;
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
    externalApiUrl = _prefs.getString(_kExternal) ?? '';
    _lyricScale =
        (_prefs.getDouble(_kScale) ?? 1.0).clamp(minScale, maxScale).toDouble();
    final themeIdx = _prefs.getInt(_kTheme) ?? 0;
    _themeMode = AppThemeMode.values[themeIdx.clamp(0, 2).toInt()];
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
}
