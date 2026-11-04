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
import 'package:zenmusic/web/web_theme.dart';
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
          theme: zenTheme(Brightness.light),
          darkTheme: zenTheme(Brightness.dark),
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

class _Dest {
  const _Dest(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _WebShellState extends State<WebShell> {
  int _tab = 0;

  static const List<_Dest> _destinations = [
    _Dest(Icons.home_outlined, Icons.home_rounded, 'Home'),
    _Dest(Icons.search_rounded, Icons.search_rounded, 'Search'),
    _Dest(Icons.bookmark_border_rounded, Icons.bookmark_rounded, 'Saved'),
    _Dest(Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
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

    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              SizedBox(
                width: 84,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _destinations.length; i++)
                      _RailItem(
                        dest: _destinations[i],
                        selected: _tab == i,
                        onTap: () => setState(() => _tab = i),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: pages),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: bar,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: pages),
            bar,
            _FloatingNav(
              destinations: _destinations,
              selected: _tab,
              onSelected: (i) => setState(() => _tab = i),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom pill navigation: the selected item expands into a white pill.
class _FloatingNav extends StatelessWidget {
  const _FloatingNav({
    required this.destinations,
    required this.selected,
    required this.onSelected,
  });

  final List<_Dest> destinations;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < destinations.length; i++)
            _NavPill(
              dest: destinations[i],
              selected: selected == i,
              onTap: () => onSelected(i),
            ),
        ],
      ),
    );
  }
}

class _NavPill extends StatelessWidget {
  const _NavPill({
    required this.dest,
    required this.selected,
    required this.onTap,
  });

  final _Dest dest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.surface : cs.onSurface;
    return Semantics(
      button: true,
      label: dest.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: selected ? 22 : 14,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: selected ? cs.onSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Row(
            children: [
              Icon(selected ? dest.selectedIcon : dest.icon, color: fg),
              if (selected) ...[
                const SizedBox(width: 8),
                Text(
                  dest.label,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.dest,
    required this.selected,
    required this.onTap,
  });

  final _Dest dest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Tooltip(
        message: dest.label,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Container(
            width: 56,
            height: 48,
            decoration: BoxDecoration(
              color: selected ? cs.onSurface : Colors.transparent,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(
              selected ? dest.selectedIcon : dest.icon,
              color: selected ? cs.surface : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
