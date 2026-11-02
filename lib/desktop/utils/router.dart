// ZenMusic Desktop — ported from Echo Music (GPL-3.0). ZenMusic remains GPL-3.0.
// PORT: /browse and /chip are TOP-LEVEL (marked deviation). R8e complete:
// backup_storage/about/downloads/privacy/player/ytmusic/appearance routes live.
// /listen = Listen Together. /video = mobile video watch (native bridge).
// /settings/player/equalizer = device EQ. /chart_details = REAL page.
// SP-6: /saved/spotify_library and /saved/spotify_playlist added.
// SP-77: /artist = LastWave-style artist page; /player entrance on mobile is
// now the expressive spring (slide 85% + scale 0.85 bottom-anchored + fade),
// matching the reference player sheet. Windows keeps the plain slide.
// SP-79: /youtube is a 3rd shell branch (Home / Trending / Shorts feed);
// /yt_search, /yt_channel, /yt_playlist are pushed pages above the shell.
// Watch playback itself keeps using /video's VideoWatchPage engine.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:zenmusic/desktop/screens/artist/artist_page.dart';

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
// SP-83: the Jam route is BACK. SP-79's router rewrite accidentally fell
// back to the pre-SP-77 self-hosted Listen Together page (which SP-77
// deleted) — SP-80/SP-82 inherited that. /listen opens the LastWave-style
// JamPage again (rooms compatible with LastWave clients and the hosted
// Jam server).
import 'package:zenmusic/desktop/screens/listen_together/jam_page.dart';
import 'package:zenmusic/desktop/screens/chart/chart_details_page.dart';
import 'package:zenmusic/desktop/services/chart_model.dart';
import 'package:zenmusic/desktop/screens/youtube/yt_home_page.dart'; // SP-79
import 'package:zenmusic/desktop/screens/youtube/yt_search_page.dart'; // SP-79
import 'package:zenmusic/desktop/screens/youtube/yt_channel_page.dart'; // SP-79
import 'package:zenmusic/desktop/screens/youtube/yt_playlist_page.dart'; // SP-79
import 'package:zenmusic/desktop/screens/shell/app_shell.dart';
// SP-80: the LastWave-style mobile shell (phones only — Windows keeps the
// desktop AppShell untouched, as requested).
import 'package:zenmusic/mobile/shell/zen_mobile_shell.dart';
import 'package:zenmusic/desktop/spotify/spotify_login_page.dart';
import 'package:zenmusic/desktop/utils/expressive_motion.dart';
import 'package:zenmusic/desktop/ytmusic/ytm_login_page.dart'; // SP-62


final router = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => child,
      routes: [
        StatefulShellRoute(
          branches: branches,
          // SP-80: phones get the reference-style mobile shell (floating
          // dock, hide-on-scroll chrome); Windows keeps the desktop
          // AppShell exactly as it is (5 destinations, SP-79 order).
          builder: (context, state, navigationShell) =>
              ZenMobileShell.applies()
                  ? ZenMobileShell(navigationShell: navigationShell)
                  : AppShell(navigationShell: navigationShell),
          navigatorContainerBuilder: (context, navigationShell, children) =>
              MyPageView(
                currentIndex: navigationShell.currentIndex,
                children: children,
                // SP-82: swiping left/right moves between the 5 tabs and
                // the dock pill follows once the swipe settles — the
                // reference shell's HorizontalPager behaviour.
                onPageSettled: (i) {
                  if (i != navigationShell.currentIndex) {
                    navigationShell.goBranch(i, initialLocation: false);
                  }
                },
              ),
        ),
        GoRoute(
          path: '/player',
          pageBuilder: (context, state) {
            final videoId = state.extra as String?;
            final mobile = Platform.isAndroid || Platform.isIOS;
            return CustomTransitionPage(
              key: state.pageKey,
              // SP-77 mobile: the reference player-sheet entrance — the
              // sheet slides up the last 15% while scaling 0.85 → 1.0 from
              // a bottom-anchored origin and fading in, all on the same
              // expressive spring (≈280 ms, ~1.5% overshoot). Reverse on
              // pop is the same curve mirrored by the route animation.
              transitionDuration: mobile
                  ? const Duration(milliseconds: 460)
                  : const Duration(milliseconds: 300),
              reverseTransitionDuration: mobile
                  ? const Duration(milliseconds: 380)
                  : const Duration(milliseconds: 300),
              child: PlayerPage(videoId: videoId),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                const begin = Offset(0.0, 1.0);
                const end = Offset.zero;
                if (mobile) {
                  // Expressive spring slide + scale + fade.
                  // NOTE: CurvedAnimation evaluates BOTH curves at the same
                  // parent value t (1→0 while popping), so the reverse
                  // curves below are ordinary ease shapes — no `.flipped`.
                  final curved = CurvedAnimation(
                    parent: animation,
                    curve: const ExpressiveSpring(),
                    // Collapse: fast launch, soft settle — decisive, not
                    // springy (the reverse of the entrance feel).
                    reverseCurve: Curves.easeInCubic,
                  );
                  final slideTween = Tween(begin: begin, end: end);
                  final scaleTween = Tween(begin: 0.85, end: 1.0);
                  final fadeTween = Tween(begin: 0.0, end: 1.0);
                  final fade = CurvedAnimation(
                    parent: animation,
                    // Forward: fully opaque within the first 45% (~200 ms),
                    // like the reference's 180 ms fade.
                    curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
                    // Reverse: hold opaque until late in the pop, then fade.
                    reverseCurve:
                        const Interval(0.0, 0.45, curve: Curves.easeIn),
                  );
                  return SlideTransition(
                    position: curved.drive(slideTween),
                    child: ScaleTransition(
                      scale: curved.drive(scaleTween),
                      // Bottom-anchored: the sheet grows out of the
                      // mini-player corner of the screen.
                      alignment: Alignment.bottomCenter,
                      child: FadeTransition(
                        opacity: fade.drive(fadeTween),
                        child: child,
                      ),
                    ),
                  );
                }
                // Desktop: the historical ease slide (unchanged).
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
        // SP-77: LastWave-style artist page.
        GoRoute(
          path: '/artist',
          builder: (context, state) {
            final args = state.extra as Map<String, dynamic>? ?? {};
            return ArtistPage(
              name: args['name'] as String? ?? '',
              browseId: args['browseId'] as String?,
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
          builder: (context, state) {
            // A pasted invite link (...?code=ABC123) pre-fills the code.
            final code = state.uri.queryParameters['code'];
            return JamPage(initialCode: (code == null || code.isEmpty) ? null : code);
          },
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
        // ── SP-79: YouTube browse pages ────────────────────────────────
        GoRoute(
          path: '/yt_search',
          builder: (context, state) =>
              YtSearchPage(initialQuery: state.extra as String?),
        ),
        GoRoute(
          path: '/yt_channel',
          builder: (context, state) {
            final extra = state.extra;
            String id = '';
            String? title;
            if (extra is Map) {
              id = (extra['id'] ?? '').toString();
              final t = extra['title'];
              if (t != null) title = t.toString();
            } else if (extra is String) {
              id = extra;
            }
            if (id.isEmpty) {
              return const Scaffold(
                  body: Center(child: Text('Channel not available')));
            }
            return YtChannelPage(channelId: id, title: title);
          },
        ),
        GoRoute(
          path: '/yt_playlist',
          builder: (context, state) {
            final extra = state.extra;
            String id = '';
            String? title;
            if (extra is Map) {
              id = (extra['id'] ?? '').toString();
              final t = extra['title'];
              if (t != null) title = t.toString();
            } else if (extra is String) {
              id = extra;
            }
            if (id.isEmpty) {
              return const Scaffold(
                  body: Center(child: Text('Playlist not available')));
            }
            return YtPlaylistPage(playlistId: id, title: title);
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
  // SP-79: the YouTube section is the 3rd shell branch (rail / bottom-bar
  // index 2 — app_shell.dart destinations must stay in this order).
  StatefulShellBranch(
    routes: [
      GoRoute(
        path: '/youtube',
        builder: (context, state) => const YtHomePage(),
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

  /// SP-82: fired when a USER swipe left/right settles on a different
  /// tab — the shell then goBranches so the route, branch state and the
  /// dock pill follow the swipe. Deliberately driven from the SETTLED
  /// page (ScrollEndNotification), not onPageChanged: the reference
  /// shell notes that currentPage flips MID-drag and re-triggering the
  /// dock animation while the pager is still moving makes them fight
  /// ("settledPage on swipe keeps one clean transition").
  final ValueChanged<int>? onPageSettled;

  /// SP-82: horizontal swipe between tabs (the reference's
  /// HorizontalPager). Mobile only — desktop keeps mouse navigation;
  /// both slide horizontally on destination taps now (the old vertical
  /// PageView slide is gone).
  final bool swipeable;

  MyPageView(
      {super.key,
      required this.currentIndex,
      required this.children,
      this.onPageSettled,
      bool? swipeable})
      : swipeable =
            swipeable ?? (Platform.isAndroid || Platform.isIOS);

  @override
  MyPageViewViewState createState() => MyPageViewViewState();
}

class MyPageViewViewState extends State<MyPageView> {
  final PageController controller = PageController(initialPage: 0);

  bool _onScrollNotification(ScrollNotification n) {
    if (!widget.swipeable) return false;
    // ScrollEndNotification fires only when the drag/ballistic motion has
    // fully stopped — the settled moment.
    if (n is ScrollEndNotification && n.metrics.axis == Axis.horizontal) {
      final page = controller.page;
      if (page != null) {
        final target = page.round();
        if (target != widget.currentIndex) {
          widget.onPageSettled?.call(target);
        }
      }
    }
    return false;
  }

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
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: PageView(
        // SP-82: horizontal — the tabs sit side by side and slide
        // left/right, exactly like the reference shell.
        scrollDirection: Axis.horizontal,
        physics: widget.swipeable
            ? const PageScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        controller: controller,
        children: widget.children,
      ),
    );
  }
}