import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../theme/spotify_theme.dart';

/// Echo-style status chip between the slider's time labels.
/// State priority (matching the reference):
///   1. Sleep timer — green countdown ticking each second, or
///      "End of song" for the end-of-song sentinel
///   2. Crossfading — shown while two tracks overlap
///   3. Buffering — tiny spinner + label
///   4. Codec text — "AAC · 320 kbps", only when [showCodec] (the
///      player wires this to !showQualityBadge so codec info shows in
///      exactly one place)
/// Renders zero-width when idle so the time row layout is stable.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    this.playbackState,
    this.qualityStream,
    this.showCodec = true,
  });

  final Stream<PlaybackState>? playbackState;
  final Stream<Map<String, String?>>? qualityStream;
  final bool showCodec;

  @override
  Widget build(BuildContext context) {
    // 1. Sleep timer — the handler emits every second while counting
    // down, so this ticks live. Duration.zero is the end-of-song mode.
    return StreamBuilder<Duration?>(
      stream: audioHandler.sleepTimerStream,
      builder: (context, sleepSnap) {
        final sleep = sleepSnap.data;
        if (sleep != null) {
          return _chip(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  sleep == Duration.zero
                      ? FluentIcons.timer_24_filled
                      : FluentIcons.timer_24_regular,
                  size: 11,
                  color: SpotifyColors.green,
                ),
                const SizedBox(width: 4),
                Text(
                  sleep == Duration.zero
                      ? 'End of song'
                      : _fmtRemaining(sleep),
                  style: _chipStyle(color: SpotifyColors.green),
                ),
              ],
            ),
          );
        }

        // 2. Crossfading — fires only on transitions; a chip mounted
        // mid-fade shows nothing until the next fade, acceptable.
        return StreamBuilder<bool>(
          stream: audioHandler.crossfadeStream,
          builder: (context, xSnap) {
            if (xSnap.data == true) {
              return _chip(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      FluentIcons.arrow_sync_24_regular,
                      size: 11,
                      color: SpotifyColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text('Crossfading', style: _chipStyle()),
                  ],
                ),
              );
            }

            // 3. Buffering — always active regardless of codec gating.
            return StreamBuilder<PlaybackState>(
              stream: playbackState,
              builder: (context, stateSnap) {
                final st = stateSnap.data;
                final buffering = st != null &&
                    (st.processingState == AudioProcessingState.loading ||
                        st.processingState ==
                            AudioProcessingState.buffering);

                if (buffering) {
                  return _chip(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: SpotifyColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text('Buffering', style: _chipStyle()),
                      ],
                    ),
                  );
                }

                // 4. Codec text — gated so it never duplicates the
                // title's quality badge.
                if (!showCodec) return const SizedBox.shrink();
                return StreamBuilder<Map<String, String?>>(
                  stream: qualityStream,
                  builder: (context, qSnap) {
                    final type = qSnap.data?['type'];
                    final bitrate = qSnap.data?['bitrate'];
                    if (type == null || type.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    final text = '${type.toUpperCase()}'
                        '${bitrate != null && bitrate.isNotEmpty ? ' · $bitrate kbps' : ''}';
                    return _chip(child: Text(text, style: _chipStyle()));
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  String _fmtRemaining(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  TextStyle _chipStyle({Color color = SpotifyColors.textSecondary}) =>
      TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: color,
      );

  Widget _chip({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.white.withOpacity(0.12),
          width: 0.5,
        ),
      ),
      child: child,
    );
  }
}