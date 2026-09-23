import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../audio/zen_audio_handler.dart';
import '../theme/spotify_theme.dart';

/// Sleep timer button (icon reflects armed state) — drop into any row.
class SleepTimerButton extends StatelessWidget {
  const SleepTimerButton({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: audioHandler.sleepTimerStream,
      builder: (context, snap) {
        final active = snap.data != null;
        return IconButton(
          splashRadius: 20,
          icon: Icon(
            active
                ? FluentIcons.timer_24_filled
                : FluentIcons.timer_24_regular,
            color: active ? SpotifyColors.green : SpotifyColors.textSecondary,
            size: 22,
          ),
          tooltip: 'Sleep timer',
          onPressed: () => showSleepTimerSheet(context),
        );
      },
    );
  }
}

void showSleepTimerSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: SpotifyColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _SleepTimerSheet(),
  );
}

class _SleepTimerSheet extends StatefulWidget {
  const _SleepTimerSheet();

  @override
  State<_SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<_SleepTimerSheet> {
  int _hours = 0;
  int _minutes = 30;

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder<Duration?>(
        stream: audioHandler.sleepTimerStream,
        builder: (context, snap) {
          final state = snap.data;
          final active = state != null;

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(FluentIcons.timer_24_regular,
                        color: SpotifyColors.green),
                    SizedBox(width: 10),
                    Text('Sleep timer',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: SpotifyColors.textPrimary)),
                  ],
                ),
                const SizedBox(height: 20),

                if (active) ...[
                  Text(
                    state == Duration.zero
                        ? 'Stops at the end of this song'
                        : 'Music stops in ${_fmt(state)}',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: SpotifyColors.textPrimary),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: SpotifyColors.surfaceLight,
                      foregroundColor: SpotifyColors.textPrimary,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: () {
                      audioHandler.cancelSleepTimer();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Cancel timer'),
                  ),
                ] else ...[
                  _stepper('Hours', _hours, (v) => setState(() => _hours = v)),
                  const SizedBox(height: 12),
                  _stepper(
                      'Minutes', _minutes, (v) => setState(() => _minutes = v)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final mins in const [15, 30, 45, 60])
                        ActionChip(
                          label: Text('$mins min'),
                          backgroundColor: SpotifyColors.surfaceLight,
                          labelStyle: const TextStyle(
                              fontSize: 12,
                              color: SpotifyColors.textPrimary),
                          onPressed: () => setState(() {
                            _hours = mins ~/ 60;
                            _minutes = mins % 60;
                          }),
                        ),
                      ActionChip(
                        label: const Text('End of song'),
                        backgroundColor: SpotifyColors.surfaceLight,
                        labelStyle: const TextStyle(
                            fontSize: 12, color: SpotifyColors.textPrimary),
                        onPressed: () {
                          audioHandler.setSleepTimerEndOfSong();
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: SpotifyColors.green,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: (_hours == 0 && _minutes == 0)
                        ? null
                        : () {
                      audioHandler.setSleepTimer(
                          Duration(hours: _hours, minutes: _minutes));
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Set timer',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stepper(String label, int value, ValueChanged<int> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: SpotifyColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: SpotifyColors.textPrimary)),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_rounded,
                    color: SpotifyColors.textSecondary),
                onPressed: value > 0 ? () => onChanged(value - 1) : null,
              ),
              SizedBox(
                width: 44,
                child: Text('$value',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: SpotifyColors.textPrimary)),
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded,
                    color: SpotifyColors.textSecondary),
                onPressed: () => onChanged(value + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}