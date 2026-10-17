// ZenMusic — Seek bar picker page (opened from Settings > Personalization).
//
// * Swipe (or use the arrow keys / chevrons) through all 7 ZenSlider styles
//   in a live, interactive preview that looks like the real player.
// * Drag the bar to try it, toggle play/pause to see animated styles move.
// * "Use this style" writes AppearancePrefs.sliderStyle (the player page reads
//   it live through ZenSliderStyle.fromName(...)).
// * Grid of every style underneath: tap one to jump to it; the style that is
//   currently in use carries a check badge.
//
// Open it with:
//   Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SeekBarPage()));

import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HapticFeedback, LogicalKeyboardKey;

import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/themes/text_styles.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';
import 'package:zenmusic/desktop/utils/zen_slider.dart';

// Icon table: change a name here if your fluentui_system_icons lacks one.
class _I {
  _I._();
  static const previous = FluentIcons.previous_24_filled;
  static const next = FluentIcons.next_24_filled;
  static const play = FluentIcons.play_24_filled;
  static const pause = FluentIcons.pause_24_filled;
  static const check = FluentIcons.checkmark_24_regular;
  static const checkCircle = FluentIcons.checkmark_circle_24_filled;
  static const chevronLeft = FluentIcons.chevron_left_24_regular;
  static const chevronRight = FluentIcons.chevron_right_24_regular;
  static const music = FluentIcons.music_note_2_24_regular;
}

class SeekBarPage extends StatefulWidget {
  const SeekBarPage({super.key});

  @override
  State<SeekBarPage> createState() => _SeekBarPageState();
}

class _SeekBarPageState extends State<SeekBarPage> {
  static const int _songMs = 204000; // fake 3:24 track
  static const int _loopMs = 40000; // preview loops every 40 s

  late final PageController _pages;
  final ValueNotifier<double> _pos = ValueNotifier<double>(0.32);
  Timer? _tick;
  int _page = 0;
  bool _playing = true;
  bool _scrubbing = false;

  @override
  void initState() {
    super.initState();
    final current = ZenSliderStyle.fromName(AppearancePrefs.sliderStyle.value);
    _page = ZenSliderStyle.values.indexOf(current);
    _pages = PageController(initialPage: _page, viewportFraction: 0.92);
    _tick = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_playing || _scrubbing) return;
      var p = _pos.value + 50 / _loopMs;
      if (p >= 1) p = 0;
      _pos.value = p;
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pages.dispose();
    _pos.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------- actions

  ZenSliderStyle get _style => ZenSliderStyle.values[_page];

  void _go(int i) {
    final n = ZenSliderStyle.values.length;
    final target = i.clamp(0, n - 1);
    _pages.animateToPage(target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic);
  }

  /// Writes the preference. If AppearancePrefs exposes a persisting setter
  /// (e.g. setSliderStyle), call it here instead of assigning the notifier.
  void _apply() {
    final s = _style;
    AppearancePrefs.sliderStyle.value = s.name;
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text('Seek bar style set to ${s.label}'),
      ));
  }

  String _fmt(double p) {
    final ms = (p * _songMs).round();
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static String _describe(ZenSliderStyle s) => switch (s) {
    ZenSliderStyle.wavy => 'A gentle animated wave that settles into the thumb.',
    ZenSliderStyle.rgbGlow => 'A flowing RGB trail with a soft Gaussian glow.',
    ZenSliderStyle.classic => 'A clean thin line with a round thumb.',
    ZenSliderStyle.pill => 'A thick rounded bar with a vertical handle.',
    ZenSliderStyle.segments => 'Rounded ticks that swell around the thumb.',
    ZenSliderStyle.equalizer => 'Bouncing bars; the played part lights up.',
    ZenSliderStyle.neon => 'A single-colour glow with a pulsing halo.',
    ZenSliderStyle.orbit => 'A planet thumb with a tilted ring and a tiny moon.',
    ZenSliderStyle.heartbeat => 'A scrolling ECG trace that beats into the thumb.',
    ZenSliderStyle.dna => 'A rotating double helix with rungs.',
    ZenSliderStyle.elastic => 'A string the thumb pulls down and lets wobble.',
    ZenSliderStyle.liquid => 'A glass tube filled with rippling liquid.',
    ZenSliderStyle.constellation => 'Stars light up and connect as you progress.',
    ZenSliderStyle.fireflies => 'Glowing specks drifting above the played line.',
    ZenSliderStyle.ripple => 'Water rings radiating from the thumb.',
    ZenSliderStyle.spring => 'A looping coil that stretches into a straight wire.',
    ZenSliderStyle.dotWave => 'A dot matrix swelling in a travelling wave.',
    ZenSliderStyle.ruler => 'Measuring-tape ticks with a pointer.',
    ZenSliderStyle.comet => 'A glowing tapered tail with sparks.',
    ZenSliderStyle.lightning => 'A crackling electric arc that flickers.',
    ZenSliderStyle.glitch => 'An RGB-split line with digital displacement.',
    ZenSliderStyle.bubbles => 'A glossy line with bubbles rising and popping.',
  };

  // -------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _go(_page - 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _go(_page + 1),
        const SingleActivator(LogicalKeyboardKey.enter): _apply,
        const SingleActivator(LogicalKeyboardKey.space): () =>
            setState(() => _playing = !_playing),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AdaptiveAppBar(
            title: Text('Seek bar', style: appBarTitleStyle()),
          ),
          body: ValueListenableBuilder<String>(
            valueListenable: AppearancePrefs.sliderStyle,
            builder: (context, appliedName, _) {
              final applied = ZenSliderStyle.fromName(appliedName);
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                        child: Text(
                          'Swipe to browse styles. Drag the bar to try it, '
                              'tap play to see it animate.',
                          style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: cs.onSurface.withValues(alpha: 0.65)),
                        ),
                      ),
                      SizedBox(
                        height: 318,
                        child: PageView.builder(
                          controller: _pages,
                          itemCount: ZenSliderStyle.values.length,
                          onPageChanged: (i) => setState(() => _page = i),
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: _PreviewCard(
                              style: ZenSliderStyle.values[i],
                              active: i == _page,
                              playing: _playing,
                              pos: _pos,
                              fmt: _fmt,
                              onScrub: (v) {
                                _scrubbing = true;
                                _pos.value = v;
                              },
                              onScrubEnd: (v) {
                                _scrubbing = false;
                                _pos.value = v;
                              },
                              onTogglePlay: () =>
                                  setState(() => _playing = !_playing),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _Pager(
                        page: _page,
                        count: ZenSliderStyle.values.length,
                        onPrev: _page > 0 ? () => _go(_page - 1) : null,
                        onNext: _page < ZenSliderStyle.values.length - 1
                            ? () => _go(_page + 1)
                            : null,
                      ),
                      const SizedBox(height: 14),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Column(
                          key: ValueKey(_style),
                          children: [
                            Text(_style.label,
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text(_describe(_style),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 14,
                                    color: cs.onSurface
                                        .withValues(alpha: 0.65))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: _style == applied
                            ? OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(_I.check, size: 18),
                          label: const Text('Current style'),
                        )
                            : FilledButton.icon(
                          onPressed: _apply,
                          icon: const Icon(_I.check, size: 18),
                          label: Text('Use ${_style.label}'),
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
                        child: Text('ALL STYLES',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.9)),
                      ),
                      LayoutBuilder(builder: (context, c) {
                        final cols = c.maxWidth >= 700 ? 4 : 2;
                        const gap = 10.0;
                        final w = (c.maxWidth - gap * (cols - 1)) / cols;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (var i = 0;
                            i < ZenSliderStyle.values.length;
                            i++)
                              SizedBox(
                                width: w,
                                child: _StyleTile(
                                  style: ZenSliderStyle.values[i],
                                  selected: i == _page,
                                  inUse: ZenSliderStyle.values[i] == applied,
                                  onTap: () => _go(i),
                                ),
                              ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════

/// Dark "mini player" card with the REAL ZenSlider inside.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.style,
    required this.active,
    required this.playing,
    required this.pos,
    required this.fmt,
    required this.onScrub,
    required this.onScrubEnd,
    required this.onTogglePlay,
  });

  final ZenSliderStyle style;
  final bool active;
  final bool playing;
  final ValueNotifier<double> pos;
  final String Function(double) fmt;
  final ValueChanged<double> onScrub;
  final ValueChanged<double> onScrubEnd;
  final VoidCallback onTogglePlay;

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(color: Colors.white70, fontSize: 12.5);
    return AnimatedScale(
      scale: active ? 1 : 0.94,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF34286B), Color(0xFF15152B)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFF38BDF8)],
                    ),
                  ),
                  child: const Icon(_I.music, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Preview song',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      SizedBox(height: 2),
                      Text('Zen Artist',
                          style:
                          TextStyle(color: Colors.white60, fontSize: 14)),
                    ],
                  ),
                ),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(style.label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const Spacer(),
            ValueListenableBuilder<double>(
              valueListenable: pos,
              builder: (context, p, _) => Column(
                children: [
                  ZenSlider(
                    style: style,
                    value: p,
                    isPlaying: playing && active,
                    height: 48,
                    onChanged: onScrub,
                    onChangeEnd: onScrubEnd,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(fmt(p), style: label),
                        Text(fmt(1), style: label),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(_I.previous, color: Colors.white70, size: 28),
                const SizedBox(width: 22),
                GestureDetector(
                  onTap: onTogglePlay,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        transitionBuilder: (c, a) =>
                            ScaleTransition(scale: a, child: c),
                        child: Icon(playing ? _I.pause : _I.play,
                            key: ValueKey(playing),
                            color: Colors.black,
                            size: 28),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 22),
                const Icon(_I.next, color: Colors.white70, size: 28),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Chevrons + dots (or an "n / total" counter when there are many styles).
class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.count,
    required this.onPrev,
    required this.onNext,
  });

  final int page;
  final int count;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final many = count > 9;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Previous style (←)',
          onPressed: onPrev,
          icon: const Icon(_I.chevronLeft),
        ),
        const SizedBox(width: 6),
        if (many)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '${page + 1} / $count',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          )
        else
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == page ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: i == page
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.22),
              ),
            ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Next style (→)',
          onPressed: onNext,
          icon: const Icon(_I.chevronRight),
        ),
      ],
    );
  }
}

/// Grid tile: static mini preview, selection ring, "in use" badge.
class _StyleTile extends StatefulWidget {
  const _StyleTile({
    required this.style,
    required this.selected,
    required this.inUse,
    required this.onTap,
  });

  final ZenSliderStyle style;
  final bool selected;
  final bool inUse;
  final VoidCallback onTap;

  @override
  State<_StyleTile> createState() => _StyleTileState();
}

class _StyleTileState extends State<_StyleTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1B2E)
                .withValues(alpha: _hover ? 1.0 : 0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.selected
                  ? cs.primary
                  : Colors.white.withValues(alpha: 0.06),
              width: widget.selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 40,
                child: IgnorePointer(
                  child: ZenSlider(
                    style: widget.style,
                    value: 0.45,
                    isPlaying: false,
                    height: 40,
                    onChanged: (_) {},
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(widget.style.label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700)),
                  ),
                  if (widget.inUse)
                    Icon(_I.checkCircle, size: 18, color: cs.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}