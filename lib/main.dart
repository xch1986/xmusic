import 'package:flutter/material.dart';

import 'pages/home_shell.dart';
import 'pages/login_page.dart';
import 'player_controller.dart';
import 'settings.dart';
import 'subsonic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings();
  await settings.load();
  runApp(MyApp(settings: settings));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.settings});

  final AppSettings settings;

  // One fixed seed. Light/dark follows the system (or user override);
  // player colors never come from album art.
  static const _seed = Color(0xFF3D5AFE);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return MaterialApp(
          title: 'xmusic',
          debugShowCheckedModeBanner: false,
          themeMode: switch (settings.themeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          theme: ThemeData(
            scaffoldBackgroundColor: const Color(0x99E8F0FF),
            appBarTheme: const AppBarTheme(
                backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0),
            navigationBarTheme: NavigationBarThemeData(
                backgroundColor: const Color(0x55FFFFFF),
                elevation: 0,
                indicatorColor: _seed.withOpacity(0.12),
                labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12))),
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: _seed,
              brightness: Brightness.light,
            ),
          ),
          darkTheme: ThemeData(
            scaffoldBackgroundColor: const Color(0x990F1218),
            appBarTheme: const AppBarTheme(
                backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0),
            navigationBarTheme: NavigationBarThemeData(
                backgroundColor: const Color(0x221A1F2E),
                elevation: 0,
                indicatorColor: _seed.withOpacity(0.2),
                labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12))),
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: _seed,
              brightness: Brightness.dark,
            ),
          ),
          home: Root(settings: settings),
        );
      },
    );
  }
}

/// Switches between the login screen and the main shell depending on login
/// state and owns the [PlayerController] for the logged-in session.
class Root extends StatefulWidget {
  const Root({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  PlayerController? _controller;
  SubsonicClient? _client;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettings);
    _sync();
  }

  void _sync() {
    final s = widget.settings;
    if (!s.hasLogin) {
      _controller?.dispose();
      _controller = null;
      _client = null;
    } else if (_client == null) {
      _client = s.buildClient();
      _controller = PlayerController(_client!, s);
      _controller!.restoreLastState();
    }
  }

  void _onSettings() {
    setState(_sync);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettings);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return LoginPage(settings: widget.settings);
    return HomeShell(settings: widget.settings, controller: controller);
  }
}
