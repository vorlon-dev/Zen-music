// ZenMusic · vorlon-dev

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
        if (!loggedIn) return const SizedBox.shrink();
        if (_loading && !_fetchedOnce) {
          return const ShelfSkeleton();
        }
        if (_shelves.isEmpty) {
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


