// ZenMusic Desktop — synced lyrics view (Echo Music style port).
//
// Auto-following, tap-to-seek lyric sheet:
//   * active line highlighted + smoothly animated (Echo's emphasized easing)
//   * auto-centers the current line, pauses 4 s when the user scrolls
//   * instrumental breaks (>6 s gaps) render a breathing "♪ ♪ ♪" indicator
//   * falls back to plain (untimed) text, instrumental card, empty states
//
// PURE WIDGET — no engine, no Hive, no network. Feed it a LyricsData from
// LyricsService.lookup() and a position stream from your player.
//
// ZERO new pubspec deps. R5 print policy: nothing printed here.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/lyrics_service.dart';

class SyncedLyricsView extends StatefulWidget {
  const SyncedLyricsView({
    super.key,
    required this.lyrics,
    required this.positionStream,
    this.initialPosition = Duration.zero,
    this.loading = false,
    this.onSeek,
    this.accentColor,
    this.inactiveColor,
    this.loadingText = 'Looking for lyrics…',
    this.notFoundText = 'No lyrics available for this track',
    this.textScale = 1.0,
  });

  /// Current track lyrics (from `LyricsService.lookup`). Null → empty state.
  final LyricsData? lyrics;

  /// Player position updates (media_kit / just_audio both expose one).
  final Stream<Duration>? positionStream;

  /// Position used for the first active-line evaluation (before the first
  /// stream event arrives).
  final Duration initialPosition;

  /// True while `LyricsService.lookup` is resolving.
  final bool loading;

  /// Called when the user taps a line (seek). Null → lines are not tappable.
  final Future<void> Function(Duration position)? onSeek;

  /// Active-line color. Defaults to the theme's primary color.
  final Color? accentColor;

  /// Inactive-line color. Defaults to a translucent onSurface.
  final Color? inactiveColor;

  final String loadingText;
  final String notFoundText;

  /// Global text scale knob (1.0 = default).
  final double textScale;

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<SyncedLyricsView> {
  static const Duration _lead = Duration(milliseconds: 220);
  static const int _interludeMinMs = 6000;
  static const int _interludeAfterMs = 1800;

  final ScrollController _scroll = ScrollController();
  List<GlobalKey> _keys = <GlobalKey>[];

  StreamSubscription<Duration>? _sub;
  int _active = -1;
  bool _interlude = false;
  bool _everFollowed = false;
  DateTime _manualUntil = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _listen();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _evaluate(widget.initialPosition.inMilliseconds);
    });
  }

  @override
  void didUpdateWidget(covariant SyncedLyricsView old) {
    super.didUpdateWidget(old);
    if (widget.positionStream != old.positionStream) {
      _sub?.cancel();
      _sub = null;
      _listen();
    }
    if (widget.lyrics != old.lyrics) {
      setState(() {
        _active = -1;
        _interlude = false;
        _everFollowed = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _evaluate(widget.initialPosition.inMilliseconds);
      });
    }
  }

  void _listen() {
    final s = widget.positionStream;
    if (s == null) return;
    _sub = s.listen((d) {
      if (!mounted) return;
      _evaluate(d.inMilliseconds);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  // --- position → active line ----------------------------------------------

  int get _lines => widget.lyrics?.synced?.length ?? 0;

  void _evaluate(int posMs) {
    if (!mounted || _lines == 0) return;
    final lyrics = widget.lyrics!.synced!;
    final target = posMs + _lead.inMilliseconds;

    var idx = -1;
    for (var i = 0; i < lyrics.length; i++) {
      if (lyrics[i].timeMs <= target) {
        idx = i;
      } else {
        break;
      }
    }

    var interlude = false;
    if (idx >= 0 && idx + 1 < lyrics.length) {
      final gap = lyrics[idx + 1].timeMs - lyrics[idx].timeMs;
      interlude =
          gap > _interludeMinMs && posMs > lyrics[idx].timeMs + _interludeAfterMs;
    }

    if (idx != _active || interlude != _interlude) {
      setState(() {
        _active = idx;
        _interlude = interlude;
      });
      _follow(instant: !_everFollowed);
    }
  }

  void _follow({bool instant = false}) {
    if (_active < 0 || _active >= _keys.length) return;
    if (!instant && DateTime.now().isBefore(_manualUntil)) return;

    final ctx = _keys[_active].currentContext;
    if (ctx == null) return;
    if (!instant) _everFollowed = true;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.38,
      duration: instant ? Duration.zero : const Duration(milliseconds: 420),
      curve: instant ? Curves.ease : Curves.easeOutCubic,
    );
  }

  // --- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return _center(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(height: 14),
            Text(
              widget.loadingText,
              textAlign: TextAlign.center,
              style: _base(context)
                  .copyWith(color: _inactive(context), fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    final lyrics = widget.lyrics;
    if (lyrics == null) {
      return _center(
        Text(
          widget.notFoundText,
          textAlign: TextAlign.center,
          style: _base(context)
              .copyWith(color: _inactive(context), fontWeight: FontWeight.w500),
        ),
      );
    }

    if (lyrics.instrumental) {
      return _center(_Breath(color: _accent(context), scale: widget.textScale));
    }

    if (lyrics.hasSynced) return _syncedList(context, lyrics.synced!);

    final plain = lyrics.plain;
    if (plain != null && plain.trim().isNotEmpty) {
      return Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Text(
            plain.trim(),
            textAlign: TextAlign.center,
            style: _base(context).copyWith(
              fontSize: 17 * widget.textScale,
              height: 1.7,
              fontWeight: FontWeight.w500,
              color: _activeColor(context),
            ),
          ),
        ),
      );
    }

    return _center(
      Text(
        widget.notFoundText,
        style: _base(context).copyWith(color: _inactive(context)),
      ),
    );
  }

  Widget _syncedList(BuildContext context, List<LyricLine> lines) {
    if (_keys.length != lines.length) {
      _keys = List<GlobalKey>.generate(lines.length, (_) => GlobalKey());
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // User grabbed the scrollbar / drag-scrolled → pause auto-follow 4 s.
        if (n.depth == 0 &&
            n is ScrollStartNotification &&
            n.dragDetails != null) {
          _manualUntil = DateTime.now().add(const Duration(seconds: 4));
        }
        return false;
      },
      child: ListView.builder(
        controller: _scroll,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
          vertical: MediaQuery.of(context).size.height * 0.36,
          horizontal: 28,
        ),
        itemCount: lines.length,
        itemBuilder: (context, i) {
          final isActive = i == _active;
          final isPast = i < _active;
          final line = lines[i];

          final child = line.text.isEmpty
              ? const SizedBox(height: 18)
              : GestureDetector(
            onTap: widget.onSeek == null
                ? null
                : () => widget.onSeek!(
                Duration(milliseconds: lines[i].timeMs)),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              style: _base(context).copyWith(
                fontSize: (isActive ? 25 : 20) * widget.textScale,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                height: 1.35,
                color: isActive
                    ? _accent(context)
                    : _inactive(context)
                    .withOpacity(isPast ? 0.30 : 0.48),
                shadows: isActive
                    ? const <Shadow>[
                  Shadow(blurRadius: 18, color: Color(0x55000000)),
                ]
                    : const <Shadow>[],
              ),
              child: Text(
                line.text,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );

          return Column(
            key: _keys[i],
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                child: child,
              ),
              // Instrumental-break indicator right after the active line.
              if (isActive && _interlude)
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: _Breath(
                      color: _accent(context), scale: widget.textScale),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _center(Widget child) =>
      Center(child: Padding(padding: const EdgeInsets.all(28), child: child));

  TextStyle _base(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge ??
          const TextStyle(fontSize: 16, inherit: false);

  Color _accent(BuildContext context) =>
      widget.accentColor ?? Theme.of(context).colorScheme.primary;

  Color _activeColor(BuildContext context) =>
      widget.accentColor ??
          Theme.of(context).colorScheme.onSurface.withOpacity(0.9);

  Color _inactive(BuildContext context) =>
      widget.inactiveColor ??
          Theme.of(context).colorScheme.onSurface.withOpacity(0.45);
}

/// Pulsing "♪ ♪ ♪" — instrumental break / instrumental-track indicator.
class _Breath extends StatefulWidget {
  const _Breath({required this.color, this.scale = 1.0});

  final Color color;
  final double scale;

  @override
  State<_Breath> createState() => _BreathState();
}

class _BreathState extends State<_Breath> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = 0.5 + 0.5 * _c.value; // 0→1→0 ramp
        return Opacity(
          opacity: 0.30 + 0.55 * t,
          child: Text(
            '♪   ♪   ♪',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22 * widget.scale,
              color: widget.color,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        );
      },
    );
  }
}