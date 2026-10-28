// ZenMusic Desktop — ported from Echo Music (GPL-3.0). ZenMusic remains GPL-3.0.
// PORT: /browse and /chip are TOP-LEVEL (marked deviation). R8e complete:
// backup_storage/about/downloads/privacy/player/ytmusic/appearance routes live.
// /listen = Listen Together. /video = mobile video watch (native bridge).
// /settings/player/equalizer = device EQ. /chart_details = REAL page.
// SP-6: /saved/spotify_library and /saved/spotify_playlist added.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:zenmusic/desktop/screens/home/home_page.dart';
import 'package:zenmusic/desktop/screens/search/search_page.dart';
import 'package:zenmusic/desktop/screens/player/player_page.dart';
import 'package:zenmusic/desktop/screens/browse/browse_page.dart';
import 'package:zenmusic/desktop/screens/chip/chip_page.dart';
import 'package:zenmusic/desktop/screens/video/video_watch_page.dart';
import 'package:zenmusic/desktop/screens/settings/settings_page.dart';
import 'package:zenmusic/desktop/screens/settings/backup_storage/backup_storage_page.dart';
import 'package:zenmusic/desktop/screens/settings/about/about_page.dart';
import 'package:zenmusic/desktop/screens/settings/privacy/privacy_page.dart';
import 'package:zenmusic/desktop/screens/settings/player/player_settings_page.dart';
import 'package:zenmusic/desktop/screens/settings/player/equalizer_page.dart';
import 'package:zenmusic/desktop/screens/settings/services/ytmusic/yt_music_page.dart';
import 'package:zenmusic/desktop/screens/settings/appearance/appearance_page.dart';
import 'package:zenmusic/desktop/screens/library/library_page.dart';
import 'package:zenmusic/desktop/screens/library/favourites/favourites_page.dart';
import 'package:zenmusic/desktop/screens/library/playlist/playlist_details_page.dart';
import 'package:zenmusic/desktop/screens/library/history/history_page.dart';
import 'package:zenmusic/desktop/screens/library/downloads/downloads_page.dart';
import 'package:zenmusic/desktop/screens/library/downloads/downloading/downloading_page.dart';
import 'package:zenmusic/desktop/screens/library/downloads/playlist/download_playlist_page.dart';
import 'package:zenmusic/desktop/screens/library/spotify/spotify_library_page.dart';
import 'package:zenmusic/desktop/screens/library/spotify/spotify_playlist_page.dart';
import 'package:zenmusic/desktop/screens/listen_together/listen_together_page.dart';
import 'package:zenmusic/desktop/screens/chart/chart_details_page.dart';
import 'package:zenmusic/desktop/services/chart_model.dart';
import 'package:zenmusic/desktop/screens/shell/app_shell.dart';
import 'package:zenmusic/desktop/spotify/spotify_login_page.dart';
import 'package:zenmusic/desktop/ytmusic/ytm_login_page.dart'; // SP-62


final router = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => child,
      routes: [
        StatefulShellRoute(
          branches: branches,
          builder: (context, state, navigationShell) => AppShell(
            navigationShell: navigationShell,
          ),
          navigatorContainerBuilder: (context, navigationShell, children) =>
              MyPageView(
                currentIndex: navigationShell.currentIndex,
                children: children,
              ),
        ),
        GoRoute(
          path: '/player',
          pageBuilder: (context, state) {
            final videoId = state.extra as String?;
            return CustomTransitionPage(
              key: state.pageKey,
              child: PlayerPage(videoId: videoId),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                const begin = Offset(0.0, 1.0);
                const end = Offset.zero;
                final curve = Curves.ease;
                final tween = Tween(begin: begin, end: end)
                    .chain(CurveTween(curve: curve));
                return SlideTransition(
                  position: animation.drive(tween),
                  child: child,
                );
              },
            );
          },
        ),
        GoRoute(
          path: '/browse',
          builder: (context, state) {
            final args = state.extra as Map<String, dynamic>? ?? {};
            return BrowsePage(
              endpoint: args['endpoint'] as Map<String, dynamic> ?? {},
              isMore: args['isMore'] as bool? ?? false,
            );
          },
        ),
        GoRoute(
          path: '/chip',
          builder: (context, state) {
            final args = state.extra as Map<String, dynamic>? ?? {};
            return ChipPage(
              title: args['title'] ?? '',
              endpoint: args['endpoint'] as Map<String, dynamic>? ?? {},
            );
          },
        ),
        GoRoute(
          path: '/listen',
          builder: (context, state) => const ListenTogetherPage(),
        ),
        GoRoute(
          path: '/spotify-login',
          builder: (context, state) => const SpotifyLoginPage(),
        ),
        // SP-62: embedded YouTube Music login (device-code OAuth webview).
        GoRoute(
          path: '/ytm-login',
          builder: (context, state) => const YtmLoginPage(),
        ),
        GoRoute(
          path: '/video',
          builder: (context, state) {
            final videoId = state.extra as String? ?? '';
            return VideoWatchPage(videoId: videoId);
          },
        ),
        GoRoute(
          path: '/chart_details',
          builder: (context, state) {
            final chart = state.extra as ChartURL?;
            if (chart == null) {
              return const Scaffold(
                  body: Center(child: Text('Chart not available')));
            }
            return ChartDetailsPage(chart: chart);
          },
        ),
      ],
    ),
  ],
);

List<StatefulShellBranch> branches = [
  StatefulShellBranch(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomePage(),
      ),
    ],
  ),
  StatefulShellBranch(
    routes: [
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchPage(),
      ),
    ],
  ),
  StatefulShellBranch(
    routes: [
      GoRoute(
        path: '/saved',
        builder: (context, state) => const LibraryPage(),
        routes: [
          GoRoute(
            path: 'favourites_page',
            builder: (context, state) => const FavouritesPage(),
          ),
          GoRoute(
            path: 'downloads_page',
            builder: (context, state) => const DownloadsPage(),
            routes: [
              GoRoute(
                path: 'downloading_page',
                builder: (context, state) => const DownloadingPage(),
              ),
              GoRoute(
                path: 'download_playlist_page',
                builder: (context, state) {
                  final args = state.extra as Map<String, dynamic>? ?? {};
                  return DownloadPlaylistPage(
                    playlistId: args['playlistId'] as String? ?? '',
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: 'history_page',
            builder: (context, state) => const HistoryPage(),
          ),
          GoRoute(
            path: 'playlist_details',
            builder: (context, state) {
              final args = state.extra as Map<String, dynamic>? ?? {};
              return PlaylistDetailsPage(
                playlistkey: args['playlistkey'] as String? ?? '',
              );
            },
          ),
          // SP-6: Spotify account library routes.
          GoRoute(
            path: 'spotify_library',
            builder: (context, state) => const SpotifyLibraryPage(),
          ),
          GoRoute(
            path: 'spotify_playlist',
            builder: (context, state) {
              final args = state.extra as Map<String, dynamic>? ?? {};
              return SpotifyPlaylistPage(
                playlistId: args['playlistId'] as String? ?? '',
                title: args['title'] as String?,
              );
            },
          ),
        ],
      ),
    ],
  ),
  StatefulShellBranch(
    routes: [
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
        routes: [
          GoRoute(
            path: 'player',
            builder: (context, state) => const PlayerSettingsPage(),
          ),
          GoRoute(
            path: 'player/equalizer',
            builder: (context, state) => const EqualizerPage(),
          ),
          GoRoute(
            path: 'appearance',
            builder: (context, state) => const AppearancePage(),
          ),
          GoRoute(
            path: 'services/ytmusic',
            builder: (context, state) => const YTMusicPage(),
          ),
          GoRoute(
            path: 'backup_storage',
            builder: (context, state) => const BackupStoragePage(),
          ),
          GoRoute(
            path: 'privacy',
            builder: (context, state) => const PrivacyPage(),
          ),
          GoRoute(
            path: 'about',
            builder: (context, state) => const AboutPage(),
          ),
        ],
      ),
    ],
  ),
];

class MyPageView extends StatefulWidget {
  final int currentIndex;
  final List<Widget> children;

  const MyPageView(
      {super.key, required this.currentIndex, required this.children});

  @override
  MyPageViewViewState createState() => MyPageViewViewState();
}

class MyPageViewViewState extends State<MyPageView> {
  final PageController controller = PageController(initialPage: 0);

  @override
  void didUpdateWidget(covariant MyPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      controller.animateToPage(widget.currentIndex,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      scrollDirection: Axis.vertical,
      physics: const NeverScrollableScrollPhysics(),
      controller: controller,
      children: widget.children,
    );
  }
}