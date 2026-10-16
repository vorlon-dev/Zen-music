// ZenMusic Desktop — ported from Echo Music (GPL-3.0). ZenMusic remains GPL-3.0.
// PORT DEVIATIONS: S.of(...) l10n -> English literals; UpdateService deferred;
// rail labels made theme-correct and visible (user-approved); DEVIATION:
// Saved item carries a live download badge (DOWNLOADING/QUEUED count) via
// the DownloadManager notifier.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:zenmusic/desktop/services/download_manager.dart';
import 'widgets/bottom_player.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    Key? key,
    required this.navigationShell,
  }) : super(key: key ?? const ValueKey('AppShell'));
  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  void _goBranch(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  /// Saved icon with a live download-count badge (DOWNLOADING + QUEUED).
  Widget _savedIcon({required bool selected}) {
    final icon = selected
        ? const Icon(Icons.library_music, color: Colors.black)
        : const Icon(Icons.library_music_outlined);
    return ValueListenableBuilder<List<Map>>(
      valueListenable: GetIt.I<DownloadManager>().downloads,
      builder: (context, downloads, _) {
        final active = downloads
            .where((d) =>
        d['status'] == 'DOWNLOADING' || d['status'] == 'QUEUED')
            .length;
        if (active == 0) return icon;
        return Badge(
          label: Text('$active'),
          isLabelVisible: true,
          child: icon,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Row(
            children: [
              if (screenWidth >= 450)
                NavigationRail(
                  extended: true,
                  backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerLowest,
                  groupAlignment: 0.0,
                  destinations: [
                    NavigationRailDestination(
                      icon: const Icon(CupertinoIcons.music_house),
                      selectedIcon: const Icon(CupertinoIcons.music_house_fill,
                          color: Colors.black),
                      label: const Text('Home'),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(CupertinoIcons.search),
                      selectedIcon: const Icon(CupertinoIcons.search,
                          color: Colors.black),
                      label: const Text('Search'),
                    ),
                    NavigationRailDestination(
                      icon: _savedIcon(selected: false),
                      selectedIcon: _savedIcon(selected: true),
                      label: const Text('Saved'),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(CupertinoIcons.gear_alt),
                      selectedIcon: const Icon(CupertinoIcons.gear_alt_fill,
                          color: Colors.black),
                      label: const Text('Settings'),
                    )
                  ],
                  selectedIndex: widget.navigationShell.currentIndex,
                  onDestinationSelected: _goBranch,
                ),
              Expanded(
                child: widget.navigationShell,
              ),
            ],
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: BottomPlayer(),
          ),
        ],
      ),
      bottomNavigationBar: screenWidth < 450
          ? NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        destinations: [
          NavigationDestination(
            icon: const Icon(CupertinoIcons.music_house),
            selectedIcon: const Icon(CupertinoIcons.music_house_fill,
                color: Colors.black),
            label: 'Home',
          ),
          NavigationDestination(
            icon: const Icon(CupertinoIcons.search),
            selectedIcon:
            const Icon(CupertinoIcons.search, color: Colors.black),
            label: 'Search',
          ),
          NavigationDestination(
            icon: _savedIcon(selected: false),
            selectedIcon: _savedIcon(selected: true),
            label: 'Saved',
          ),
          NavigationDestination(
            icon: const Icon(CupertinoIcons.settings),
            selectedIcon: const Icon(CupertinoIcons.settings_solid,
                color: Colors.black),
            label: 'Settings',
          ),
        ],
        backgroundColor:
        Theme.of(context).colorScheme.surfaceContainerLowest,
        onDestinationSelected: _goBranch,
      )
          : null,
    );
  }
}