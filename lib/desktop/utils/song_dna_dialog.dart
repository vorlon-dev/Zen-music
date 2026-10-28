// ZenMusic — SP-68: the Song DNA sheet.
//
// Opened from the song options bottom modal ("Song DNA" entry): a compact
// card that unfurls the track's backstory — the release it belongs to, a
// short extract about the song, and a short artist biography. The fetch
// runs through SongDna (public Genius + Wikipedia endpoints, no keys) and
// every strand degrades to its own friendly placeholder, so the dialog
// always renders something useful even fully offline.
//
// Signature detail: the title's color slowly pulses between the theme's
// primary and tertiary while the strands resolve — the "reading a living
// thing" cue.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:zenmusic/desktop/services/song_dna.dart';

/// Opens the Song DNA card for a track map (the same shape the song
/// options modal receives).
void showSongDnaDialog(BuildContext context, Map song) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (context) => _SongDnaCard(song: song),
  );
}

class _SongDnaCard extends StatefulWidget {
  final Map song;
  const _SongDnaCard({required this.song});

  @override
  State<_SongDnaCard> createState() => _SongDnaCardState();
}

class _SongDnaCardState extends State<_SongDnaCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Animation<Color?>? _titleColor;
  late final Future<SongDnaInfo> _future;

  @override
  void initState() {
    super.initState();
    // Theme.of() must NOT run in initState (inherited-widget rule) — the
    // pulse colors are wired in didChangeDependencies below.
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    final (title, artist, album) = SongDna.idsFromSong(widget.song);
    _future = SongDna.fetch(title: title, artist: artist, album: album);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _titleColor ??= ColorTween(
      begin: Theme.of(context).colorScheme.primary,
      end: Theme.of(context).colorScheme.tertiary,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Dialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.fingerprint_rounded,
                    size: 30, color: cs.primary),
                const SizedBox(height: 8),
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => Text(
                    'Song DNA',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: _titleColor?.value ?? cs.primary,
                        ),
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: FutureBuilder<SongDnaInfo>(
                      future: _future,
                      builder: (context, snap) {
                        final info = snap.data;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _strand(
                              context,
                              'Movie / Album',
                              info == null
                                  ? 'Fetching…'
                                  : (info.album.isEmpty
                                      ? 'Unknown'
                                      : info.album),
                            ),
                            const SizedBox(height: 16),
                            _strand(
                              context,
                              'About the Song',
                              info == null
                                  ? 'Fetching info…'
                                  : (info.meaning.isEmpty
                                      ? 'Info not found.'
                                      : info.meaning),
                              muted: true,
                            ),
                            const SizedBox(height: 16),
                            _strand(
                              context,
                              'About the Artist',
                              info == null
                                  ? 'Fetching biography…'
                                  : (info.bio.isEmpty
                                      ? 'Biography not found.'
                                      : info.bio),
                              muted: true,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _strand(BuildContext context, String label, String value,
      {bool muted = false}) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                )),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: muted
                    ? cs.onSurfaceVariant
                    : cs.onSurface.withValues(alpha: 0.9),
              ),
        ),
      ],
    );
  }
}
