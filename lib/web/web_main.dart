// ZenMusic · vorlon-dev
//
// Web player entry point. Build with:
//   flutter build web -t lib/web/web_main.dart
//
// Self-contained: it imports nothing that needs dart:io, so the Android and
// Windows apps are unaffected by this file.

import 'package:flutter/material.dart';
import 'package:zenmusic/web/web_api.dart';
import 'package:zenmusic/web/web_now_playing.dart';
import 'package:zenmusic/web/web_pages.dart';
import 'package:zenmusic/web/web_player.dart';
import 'package:zenmusic/web/web_store.dart';
import 'package:zenmusic/web/web_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await WebStore.open();
  runApp(ZenWebApp(store: store));
}

class ZenWebApp extends StatefulWidget {
  const ZenWebApp({super.key, required this.store});
  final WebStore store;

  @override
  State<ZenWebApp> createState() => _ZenWebAppState();
}

class _ZenWebAppState extends State<ZenWebApp> {
  late final WebApi _api = WebApi();
  late final WebPlayer _player = WebPlayer(_api);

  @override
  void initState() {
    super.initState();
    _player.onTrackStarted = widget.store.addToHistory;
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorSchemeSeed: const Color(0xFF7C6CF0),
      scaffoldBackgroundColor:
          dark ? const Color(0xFF0E0E12) : const Color(0xFFF7F6FB),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => WebScope(
        api: _api,
        player: _player,
        store: widget.store,
        child: MaterialApp(
          title: 'ZenMusic',
          debugShowCheckedModeBanner: false,
          themeMode: widget.store.themeMode,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          home: const WebShell(),
        ),
      ),
    );
  }
}

class WebShell extends StatefulWidget {
  const WebShell({super.key});

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  int _tab = 0;

  static const List<NavigationDestination> _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.search_rounded),
      selectedIcon: Icon(Icons.search_rounded),
      label: 'Search',
    ),
    NavigationDestination(
      icon: Icon(Icons.library_music_outlined),
      selectedIcon: Icon(Icons.library_music_rounded),
      label: 'Library',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: 'Settings',
    ),
  ];

  void _openPlayer() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NowPlayingPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final pages = IndexedStack(
      index: _tab,
      children: const [
        HomePage(),
        SearchPage(),
        LibraryPage(),
        SettingsPage(),
      ],
    );
    final bar = ListenableBuilder(
      listenable: Listenable.merge([scope.player, scope.store]),
      builder: (context, _) => PlayerBar(onOpen: _openPlayer),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'ZenMusic',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: wide
                  ? Row(
                      children: [
                        NavigationRail(
                          selectedIndex: _tab,
                          onDestinationSelected: (i) =>
                              setState(() => _tab = i),
                          labelType: NavigationRailLabelType.all,
                          destinations: [
                            for (final d in _destinations)
                              NavigationRailDestination(
                                icon: d.icon,
                                selectedIcon: d.selectedIcon,
                                label: Text(d.label),
                              ),
                          ],
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: pages),
                      ],
                    )
                  : pages,
            ),
            bar,
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: _destinations,
            ),
    );
  }
}
