# My Player

A small Flutter client for Navidrome (or any Subsonic / OpenSubsonic server).

- Lyric size: `−` / `+` buttons in the player's app bar (70 %–200 %, saved between launches).
- Theme: the whole app, including the player, follows the system light/dark setting.
  Colors come from one fixed Material 3 seed; nothing is extracted from album art.
- Synced lyrics (OpenSubsonic `getLyricsBySongId`, falling back to `getLyrics` / LRC).
  Tap a line to seek.
- The password is not stored — only the Subsonic salt + token derived from it.

## Setup

Requires Flutter 3.22 or newer.

```bash
flutter create --project-name my_stream_player my_stream_player_tmp
cp -r my_stream_player_tmp/android my_stream_player_tmp/ios my_stream_player_tmp/macos \
      my_stream_player_tmp/windows my_stream_player_tmp/web .   # whichever platforms you want
rm -rf my_stream_player_tmp
flutter pub get
flutter run
```

(Or run `flutter create .` inside this folder; it keeps the existing `lib/` and `pubspec.yaml`.)

### Android

In `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<application ... android:usesCleartextTraffic="true">   <!-- only if your server is plain http -->
```

### iOS

If your server is plain http, add an App Transport Security exception in `ios/Runner/Info.plist`.

## Not included yet

Background playback and lock-screen controls (add `just_audio_background`),
search, playlists, offline cache, shuffle/repeat.
