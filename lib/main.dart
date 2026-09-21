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

  // 清亮蓝色调，不发灰。
  static const _seed = Color(0xFF5B8DEF);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return MaterialApp(
          title: '音素',
          debugShowCheckedModeBanner: false,
          themeMode: switch (settings.themeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          theme: ThemeData(
            scaffoldBackgroundColor: const Color(0xFFEAF0FA),
            appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFFEAF0FA),
                elevation: 0,
                scrolledUnderElevation: 0),
            navigationBarTheme: const NavigationBarThemeData(
                backgroundColor: Color(0xFFEAF0FA),
                elevation: 0,
                labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12))),
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: _seed,
              brightness: Brightness.light,
              surface: const Color(0xFFEAF0FA),
              surfaceContainerHighest: const Color(0xFFD5E0F5),
              surfaceContainerLow: const Color(0xFFF0F4FC),
            ),
          ),
          darkTheme: ThemeData(
            scaffoldBackgroundColor: const Color(0xFF141820),
            appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFF141820),
                elevation: 0,
                scrolledUnderElevation: 0),
            navigationBarTheme: const NavigationBarThemeData(
                backgroundColor: Color(0xFF141820),
                elevation: 0,
                labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12))),
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: _seed,
              brightness: Brightness.dark,
              surface: const Color(0xFF1A1F2E),
              surfaceContainerHighest: const Color(0xFF252C40),
              surfaceContainerLow: const Color(0xFF1E2433),
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
