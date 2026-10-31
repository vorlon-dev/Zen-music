// ZenMusic — SP-68: the signed-in YouTube Music account as a Home section.
//
// When a cookie session is connected (YtmAuth), Home grows a set of
// taste shelves built from the user's OWN library — the same surfaces
// the YouTube Music app shows in its Library tab:
//   * "Listen again"   — FEmusic_history (recently played tracks)
//   * "Liked music"    — FEmusic_liked_videos (thumbs-upped songs/videos)
//   * "Your playlists" — FEmusic_liked_playlists (the user's playlists)
//
// The personalized quick-picks in the feed below come from FEmusic_home
// with the merged auth headers (SP-65); THIS section adds the library
// shelves that the home browse does not contain. Everything renders
// through the stock SectionItem shelf widget, so track taps play via
// playSong and playlist taps open /browse exactly like the rest of Home.
//
// Failure doctrine (same as the Spotify section): every tier is isolated
// — a dead shelf disappears quietly with a "[ytm-account]" log line and
// must never break the sections below it. Logged out, the section
// collapses to a slim connect banner that opens the sign-in flow.

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:zenmusic/desktop/core/widgets/section_item.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart'; // YTMusic + YtmAuth

class YtmAccountSection extends StatefulWidget {
  const YtmAccountSection({super.key});

  @override
  State<YtmAccountSection> createState() => YtmAccountSectionState();
}

/// State is PUBLIC so HomePage's pull-to-refresh can re-fetch through a
/// GlobalKey<YtmAccountSectionState> (mirrors SpotifyHomeSectionState).
class YtmAccountSectionState extends State<YtmAccountSection> {
  bool _loading = false;
  bool _fetchedOnce = false;
  List<Map<String, dynamic>> _shelves = const [];

  @override
  void initState() {
    super.initState();
    // The boot load() in main.dart is synchronous, so a restored session is
    // already visible here; mid-session logins land through the listener.
    if (YtmAuth.instance.loggedIn.value) {
      _load();
    }
    YtmAuth.instance.loggedIn.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    YtmAuth.instance.loggedIn.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (YtmAuth.instance.loggedIn.value) {
      _load();
    } else {
      // Logout: drop the account shelves immediately.
      setState(() {
        _shelves = const [];
        _fetchedOnce = false;
        _loading = false;
      });
    }
  }

  /// Pull-to-refresh hook (HomePage).
  void reload() {
    if (YtmAuth.instance.loggedIn.value) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    final yt = GetIt.I<YTMusic>();
    final shelves = <Map<String, dynamic>>[];

    // Tier 1 — recently played ("Listen again"). History returns day
    // shelves (Today / Yesterday / …); the first two hold the freshest
    // tracks, which is exactly the "last listening" surface.
    try {
      final history = await yt.getHistory();
      final contents = <Map<String, dynamic>>[];
      for (final sec in history.take(2)) {
        final items = (sec['contents'] as List?) ?? const [];
        for (final it in items) {
          if (it is Map && it['videoId'] != null) {
            contents.add(Map<String, dynamic>.from(it));
          }
        }
      }
      if (contents.isNotEmpty) {
        shelves.add({
          'title': 'Listen again',
          'contents': contents.take(24).toList(),
        });
      }
      // SP-71: count even when empty — "0 day-shelves" in the log means
      // the account answered (empty/off history), not that parsing died.
      debugPrint('[ytm-account] history: ${history.length} day-shelves -> '
          '${contents.length} playable rows');
    } catch (e) {
      debugPrint('[ytm-account] history skipped: $e');
    }

    // Tier 2 — liked songs / liked videos.
    try {
      final liked = await yt.getLibrarySongs();
      final items = ((liked['contents'] as List?) ?? const [])
          .whereType<Map>()
          .where((m) => m['videoId'] != null)
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      if (items.isNotEmpty) {
        shelves.add({
          'title': 'Liked music',
          'contents': items.take(24).toList(),
        });
      }
    } catch (e) {
      debugPrint('[ytm-account] liked songs skipped: $e');
    }

    // Tier 3 — the user's playlists (two-row cards; SectionItem opens
    // their browse endpoint on tap).
    try {
      final pls = await yt.getLibraryPlaylists();
      final items = ((pls['contents'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      if (items.isNotEmpty) {
        shelves.add({
          'title': 'Your playlists',
          'contents': items.take(24).toList(),
        });
      }
    } catch (e) {
      debugPrint('[ytm-account] playlists skipped: $e');
    }

    if (!mounted) return;
    setState(() {
      _shelves = shelves;
      _loading = false;
      _fetchedOnce = true;
    });
    debugPrint('[ytm-account] ${shelves.length} shelves loaded '
        '(${shelves.map((s) => s['title']).join(', ')})');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: YtmAuth.instance.loggedIn,
      builder: (BuildContext context, bool loggedIn, Widget? _) {
        if (!loggedIn) return const _YtmConnectBanner();
        if (_loading && !_fetchedOnce) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          );
        }
        if (_shelves.isEmpty) {
          // SP-71: a fresh/quiet library used to render nothing at all,
          // which read as "the feature is broken". Say what fills it.
          return const Padding(
            padding: EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Text(
              'Nothing in your YouTube Music library yet — play and like '
              'songs and your Listen again, Liked music and playlists '
              'will show up here.',
              style: TextStyle(fontSize: 12),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final shelf in _shelves) SectionItem(section: shelf),
          ],
        );
      },
    );
  }
}

// ── logged out ─────────────────────────────────────────────────────────

class _YtmConnectBanner extends StatelessWidget {
  const _YtmConnectBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: AdaptiveInkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/ytm-login'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Icon(Icons.account_circle_rounded,
                    size: 18, color: Theme.of(context).colorScheme.onPrimary),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Connect YouTube Music',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(
                        'Your last listening, liked music and playlists will '
                        'show up here.',
                        style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              Text('Connect',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary)),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right,
                  size: 20, color: Theme.of(context).colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
