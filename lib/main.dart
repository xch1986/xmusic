import 'package:flutter/material.dart';

import 'pages/library_page.dart';
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

  // One fixed seed. Light/dark follows the system; player colors never come
  // from album art.
  static const _seed = Color(0xFF3D5AFE);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Player',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
      ),
      home: Root(settings: settings),
    );
  }
}

/// Switches between the login screen and the library depending on login state
/// and owns the [PlayerController] for the logged-in session.
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
      _controller = PlayerController(_client!);
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
    return LibraryPage(settings: widget.settings, controller: controller);
  }
}
