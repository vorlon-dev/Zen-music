// ZenMusic · vorlon-dev

import 'package:zenmusic/desktop/services/l10n.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/services/launcher_logo.dart';

class LogoPage extends StatefulWidget {
  const LogoPage({super.key});

  @override
  State<LogoPage> createState() => _LogoPageState();
}

class _LogoPageState extends State<LogoPage> {
  List<LauncherLogoSlot>? _slots;
  String _current = 'default';
  String? _applying;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final supported = await LauncherLogo.isSupported();
    if (!supported) {
      if (!mounted) return;
      setState(() {
        _slots = LauncherLogo.catalog
            .map((s) => LauncherLogoSlot(
                  id: s.id,
                  label: s.label,
                  bg: s.bg,
                  fg: s.fg,
                  mandala: s.mandala,
                  available: s.id == 'default',
                ))
            .toList();
        _error = !LauncherLogo.isAndroidPlatform
            ? 'Launcher logo switching works on Android.'
            : 'Launcher slots could not be read on this install.';
      });
      return;
    }
    final slots = await LauncherLogo.listSlots();
    final current = await LauncherLogo.currentSlot();
    if (!mounted) return;
    setState(() {
      _slots = slots;
      _current = current;
    });
  }

  Future<void> _apply(LauncherLogoSlot slot) async {
    if (_applying != null || slot.id == _current) return;
    setState(() {
      _applying = slot.id;
      _error = null;
    });
    try {
      await LauncherLogo.setSlot(slot.id);
      // Mirror the pick onto the in-app brand mark (about page, headers)
      // so the whole app follows the launcher icon.
      await AppearancePrefs.setCustomLogo(switch (slot.preview) {
        null => '',
        'assets/icon/logo.png' => '',
        final p => p,
      });
      if (!mounted) return;
      setState(() {
        _current = slot.id;
        _applying = null;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(
              'Launcher logo set to ${slot.label} — the icon refreshes in a '
              'few seconds'),
        ));
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() {
        _applying = null;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applying = null;
        _error = 'Could not apply this logo: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = _slots;
    return Scaffold(
      appBar: AppBar(
        title: Text('Logo'.tr),
        centerTitle: true,
      ),
      body: slots == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                const Text(
                  'Changes the app icon on your home screen and refreshes '
                  'the logo shown inside the app.',
                  style: TextStyle(fontSize: 13.5),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.86,
                  children: [
                    for (final slot in slots)
                      _SlotTile(
                        slot: slot,
                        current: _current == slot.id,
                        applying: _applying == slot.id,
                        onTap: () => _apply(slot),
                      ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  _Notice(text: _error!),
                ],
                const SizedBox(height: 18),
                Text(
                  'Tip: some launchers cache icons — if the new logo does '
                  'not appear right away, give it a few seconds or restart '
                  'the launcher.',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6)),
                ),
              ],
            ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.slot,
    required this.current,
    required this.applying,
    required this.onTap,
  });

  final LauncherLogoSlot slot;
  final bool current;
  final bool applying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: slot.available ? onTap : null,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: Opacity(
                    opacity: slot.available ? 1.0 : 0.35,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: current
                            ? Border.all(color: cs.primary, width: 2.5)
                            : null,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: slot.preview != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.asset(
                                  slot.preview!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => _LogoArt(
                                    bg: slot.bg,
                                    fg: slot.fg,
                                    mandala: slot.mandala,
                                  ),
                                ),
                              )
                            : _LogoArt(
                                bg: slot.bg,
                                fg: slot.fg,
                                mandala: slot.mandala,
                              ),
                      ),
                    ),
                  ),
                ),
                if (applying)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black38,
                      child: Center(
                          child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4))),
                    ),
                  ),
                if (current)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                          color: cs.primary, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded,
                          size: 13, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            slot.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight:
                  current ? FontWeight.w700 : FontWeight.w500,
              color: slot.available
                  ? null
                  : Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// Code-drawn preview mirroring the shipped launcher PNG for this slot.
class _LogoArt extends StatelessWidget {
  const _LogoArt({
    required this.bg,
    required this.fg,
    required this.mandala,
  });

  final Color bg;
  final Color fg;
  final bool mandala;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LogoArtPainter(bg: bg, fg: fg, mandala: mandala),
      child: const SizedBox.expand(),
    );
  }
}

class _LogoArtPainter extends CustomPainter {
  _LogoArtPainter({
    required this.bg,
    required this.fg,
    required this.mandala,
  });

  final Color bg;
  final Color fg;
  final bool mandala;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.shortestSide;
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(w * 0.20));
    final bgPaint = Paint()..color = bg;
    canvas.drawRRect(rrect, bgPaint);

    if (!mandala) {
      final tp = TextPainter(
        text: TextSpan(
            text: 'Z',
            style: TextStyle(
              color: fg,
              fontSize: w * 0.56,
              fontWeight: FontWeight.w800,
              height: 1.0,
            )),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
      );
      return;
    }

    // Mandala: concentric petal rings, same geometry as the PNG.
    final c = Offset(size.width / 2, size.height / 2);
    final p = Paint()..color = fg;
    final rings = [(0.42, 10, 0.030), (0.30, 8, 0.028), (0.19, 6, 0.026)];
    for (final (rf, petals, pw) in rings) {
      final r = w * rf;
      for (var i = 0; i < petals; i++) {
        final a = 2 * math.pi * i / petals;
        final px = c.dx + r * 0.55 * math.cos(a);
        final py = c.dy + r * 0.55 * math.sin(a);
        canvas.drawCircle(Offset(px, py), w * pw * 1.6, p);
      }
      canvas.drawCircle(c, r * 0.85, Paint()
        ..color = fg
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.012);
    }
    canvas.drawCircle(c, w * 0.09, p);
  }

  @override
  bool shouldRepaint(_LogoArtPainter old) =>
      old.bg != bg || old.fg != fg || old.mandala != mandala;
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 18, color: cs.onSurface.withValues(alpha: 0.8)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13, height: 1.35)),
          ),
        ],
      ),
    );
  }
}
