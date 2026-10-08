import 'package:flutter/material.dart';

import '../main.dart';
import '../models/song.dart';
import '../services/home_service.dart';
import '../theme/spotify_theme.dart';
import '../utilities/zen_transitions.dart';
import '../widgets/wave_spinner.dart';
import '../widgets/youtube_thumbnail.dart';
import 'video_watch_screen.dart';

/// YouTube-style video browse tab: trending / personalized / charts
/// as YouTube feed cards (full-width 16:9 art, channel row, duration
/// badge). Every tap opens the dedicated watch page. Data comes from
/// the same verified home-service sources the home tab uses — no new
/// services, no guessed APIs.
class YoutubeTab extends StatefulWidget {
  const YoutubeTab({super.key});

  @override
  State<YoutubeTab> createState() => _YoutubeTabState();
}

class _YoutubeTabState extends State<YoutubeTab> {
  final _homeService = HomeService();

  List<Song> _trending = [];
  List<Song> _forYou = [];
  List<Song> _charts = [];
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _homeService.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _refreshing = true;
    if (mounted) setState(() {});
    try {
      final trendingF = _homeService.getYtTrendingSongs();
      final chartsF = _homeService.getTopCharts();
      final recent = storage.getPlayedHistory().take(3).toList();
      final forYouF = _homeService.getPersonalizedVideos(recent);

      final trending = await trendingF;
      final charts = await chartsF;
      final forYou = await forYouF;

      if (!mounted) return;
      setState(() {
        _trending = trending;
        _charts = charts;
        _forYou = forYou;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
    _refreshing = false;
    if (mounted) setState(() {});
  }

  void _open(Song video) {
    pushSharedAxisY(
      context,
      VideoWatchScreen(
        videoId: video.id,
        title: video.title,
        artist: video.artist,
        thumbnail: video.thumbnail,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty =
        _trending.isEmpty && _forYou.isEmpty && _charts.isEmpty;
    return RefreshIndicator(
      color: Colors.transparent,
      backgroundColor: Colors.transparent,
      onRefresh: _load,
      child: _loading
          ? _buildSkeletons()
          : ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // Bottom padding clears the floating mini player + nav bar.
        padding: const EdgeInsets.fromLTRB(0, 6, 0, 170),
        children: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Center(child: WaveSpinner(size: 26)),
            ),
          if (isEmpty)
            _emptyState()
          else ...[
            if (_trending.isNotEmpty) _section('Trending', _trending),
            if (_forYou.isNotEmpty) _section('Videos for you', _forYou),
            if (_charts.isNotEmpty) _section('Charts', _charts),
          ],
        ],
      ),
    );
  }

  Widget _section(String title, List<Song> videos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: SpotifyColors.textPrimary,
            ),
          ),
        ),
        // 10 per section — a browse surface, not an endless dump;
        // pull-to-refresh reloads.
        for (final v in videos.take(10))
          _VideoCard(video: v, onTap: () => _open(v)),
      ],
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 80, 40, 0),
      child: Column(
        children: [
          Icon(
            Icons.play_circle_outline_rounded,
            size: 56,
            color: SpotifyColors.textTertiary.withOpacity(0.6),
          ),
          const SizedBox(height: 16),
          const Text(
            'No videos right now',
            style: TextStyle(
              color: SpotifyColors.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pull to refresh',
            style: TextStyle(
              color: SpotifyColors.textTertiary.withOpacity(0.85),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletons() {
    final cardW = MediaQuery.sizeOf(context).width - 40;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 170),
      children: [
        for (var i = 0; i < 4; i++) ...[
          Container(
            width: double.infinity,
            height: cardW * 9 / 16,
            decoration: BoxDecoration(
              color: SpotifyColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            height: 44,
            decoration: BoxDecoration(
              color: SpotifyColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 22),
        ],
      ],
    );
  }
}

// ═════════════════════════════════════════════
// VIDEO CARD — YouTube feed card: full-width 16:9 thumb with a
// duration badge, letter avatar + title/channel row below.
// ═════════════════════════════════════════════

class _VideoCard extends StatelessWidget {
  final Song video;
  final VoidCallback onTap;

  const _VideoCard({required this.video, required this.onTap});

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width - 32;
    final hasDuration = video.duration > Duration.zero;
    final artist = video.artist.split(',').first.trim();

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                YoutubeThumbnail(
                  videoId: video.id,
                  imageUrl: video.thumbnail,
                  width: w,
                  height: w * 9 / 16,
                  borderRadius: 12,
                ),
                if (hasDuration)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _fmt(video.duration),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: SpotifyColors.green,
                  ),
                  child: Text(
                    artist.isNotEmpty ? artist[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: SpotifyColors.background,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          color: SpotifyColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: SpotifyColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}