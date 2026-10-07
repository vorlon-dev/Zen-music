import 'package:flutter/material.dart';
import 'dart:async';
import '../main.dart';
import '../models/song.dart';
import '../services/music_recognition_service.dart';
import '../services/shazam_service.dart';
import '../theme/spotify_theme.dart';
import 'player_screen.dart';

/// Song recognition — Echo Nightly port (in-app variant). Pulsing mic
/// orb while listening, result card on match, "Play in ZenMusic" queues
/// the identified song as a radio through Shazam's YouTube link.
class RecognizeScreen extends StatefulWidget {
  const RecognizeScreen({super.key});

  @override
  State<RecognizeScreen> createState() => _RecognizeScreenState();
}

class _RecognizeScreenState extends State<RecognizeScreen>
    with SingleTickerProviderStateMixin {
  final _service = MusicRecognitionService.instance;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
    lowerBound: 0.0,
    upperBound: 1.0,
  );

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _pulse.dispose();
    // If the user backs out mid-listen, stop the mic.
    if (_service.state.value.phase == RecognitionPhase.listening) {
      _service.cancel();
    }
    super.dispose();
  }

  Future<void> _start() async {
    final ok = await _service.hasPermission();
    if (!ok) {
      _service.state.value = const RecognitionState.error(
          'Microphone permission is required to recognize songs.');
      return;
    }
    unawaited(_service.recognize());
  }

  void _playResult(ShazamResult r) {
    final vid = r.youtubeVideoId;
    if (vid == null || vid.isEmpty) return;
    audioHandler.startRadio(Song(
      id: vid,
      title: r.title,
      artist: r.artist,
      thumbnail: (r.coverArtHqUrl ?? r.coverArtUrl ?? '') .isNotEmpty
          ? (r.coverArtHqUrl ?? r.coverArtUrl)!
          : 'https://i.ytimg.com/vi/$vid/hqdefault.jpg',
      duration: Duration.zero,
    ));
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.background,
      appBar: AppBar(
        backgroundColor: SpotifyColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: SpotifyColors.textPrimary),
        title: const Text('Recognize',
            style: TextStyle(
                color: SpotifyColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
      ),
      body: ValueListenableBuilder<RecognitionState>(
        valueListenable: _service.state,
        builder: (context, st, _) {
          switch (st.phase) {
            case RecognitionPhase.listening:
              _pulse.repeat(reverse: true);
              return _orb('Listening…', 'Play zen near your phone');
            case RecognitionPhase.processing:
              _pulse.stop();
              return _orb('Identifying…', null,
                  child: const SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.6, color: SpotifyColors.green),
                  ));
            case RecognitionPhase.success:
              _pulse.stop();
              return _resultCard(st.result!);
            case RecognitionPhase.noMatch:
              _pulse.stop();
              return _messageCard(
                Icons.search_off_rounded,
                st.message ?? 'No matches found',
                'Try again with clearer audio',
              );
            case RecognitionPhase.error:
              _pulse.stop();
              return _messageCard(
                Icons.error_outline_rounded,
                st.message ?? 'Recognition failed',
                'Check your connection and try again',
              );
            case RecognitionPhase.idle:
              return const SizedBox.shrink();
          }
        },
      ),
    );
  }

  Widget _orb(String title, String? subtitle, {Widget? child}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(_pulse.value);
              return Container(
                width: 140,
                height: 140,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: SpotifyColors.green.withOpacity(0.10 + 0.08 * t),
                  border: Border.all(
                    color: SpotifyColors.green.withOpacity(0.35 + 0.3 * t),
                    width: 2,
                  ),
                ),
                child: child ??
                    Icon(Icons.graphic_eq_rounded,
                        size: 52,
                        color: SpotifyColors.green.withOpacity(0.7 + 0.3 * t)),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: SpotifyColors.textPrimary)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle,
                style: TextStyle(
                    fontSize: 13,
                    color: SpotifyColors.textSecondary.withOpacity(0.8))),
          ],
        ],
      ),
    );
  }

  Widget _resultCard(ShazamResult r) {
    final vid = r.youtubeVideoId;
    final cover = r.coverArtHqUrl ?? r.coverArtUrl ?? '';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('IDENTIFIED',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: SpotifyColors.green)),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: cover.isNotEmpty
                  ? Image.network(cover,
                  height: 180,
                  width: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _coverFallback())
                  : _coverFallback(),
            ),
            const SizedBox(height: 14),
            Text(r.title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: SpotifyColors.textPrimary)),
            Text(r.artist,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14,
                    color: SpotifyColors.textSecondary)),
            if (r.album != null && r.album!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(r.album!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      color: SpotifyColors.textTertiary)),
            ],
            const SizedBox(height: 22),
            if (vid != null && vid.isNotEmpty)
              SizedBox(
                height: 50,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: SpotifyColors.green,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25)),
                  ),
                  onPressed: () => _playResult(r),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_arrow_rounded,
                          color: Colors.black, size: 24),
                      SizedBox(width: 6),
                      Text('Play in ZenMusic',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.black)),
                    ],
                  ),
                ),
              )
            else
              const Text(
                  'No playable stream found for this match',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: SpotifyColors.textSecondary)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _start,
              child: const Text('Recognize another song',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: SpotifyColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverFallback() => Container(
    height: 180,
    width: 180,
    color: SpotifyColors.surfaceLight,
    child: const Icon(Icons.music_note_rounded,
        size: 56, color: SpotifyColors.textTertiary),
  );

  Widget _messageCard(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 52, color: SpotifyColors.textTertiary),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: SpotifyColors.textPrimary)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: SpotifyColors.textSecondary.withOpacity(0.85))),
            const SizedBox(height: 20),
            SizedBox(
              height: 46,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: SpotifyColors.green,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(23)),
                ),
                onPressed: _start,
                child: const Text('Try again',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.black)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}