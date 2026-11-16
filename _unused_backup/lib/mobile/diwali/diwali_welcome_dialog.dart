import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const _repoUrl = 'https://github.com/vorlon-dev/Zen-music';
const _prefKey = 'diwali_2026_welcome_shown'; // change the year next Diwali to show it again

// Only show around Diwali 2026 (8 Nov). Set _useDateWindow = false to show on first launch whenever.
const _useDateWindow = true;
final _windowStart = DateTime(2026, 11, 5);
final _windowEnd = DateTime(2026, 11, 17);

/// Called once from ZenMobileShell.initState (Android/iOS home).
Future<void> showDiwaliWelcomeIfFirstTime(BuildContext context) async {
  if (_useDateWindow) {
    final now = DateTime.now();
    if (now.isBefore(_windowStart) || now.isAfter(_windowEnd)) return;
  }
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_prefKey) ?? false) return;
  await prefs.setBool(_prefKey, true);
  if (!context.mounted) return;

  // Pre-load the big images so the dialog animates smoothly.
  await Future.wait([
    precacheImage(const AssetImage('assets/diwali/toran.png'), context),
    precacheImage(const AssetImage('assets/diwali/diya.png'), context),
    precacheImage(const AssetImage('assets/diwali/support_qr.png'), context),
  ]);
  if (!context.mounted) return;

  await showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Diwali',
    barrierColor: Colors.black.withValues(alpha: 0.82),
    transitionDuration: const Duration(milliseconds: 600),
    pageBuilder: (_, __, ___) => const DiwaliWelcomeDialog(),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

class DiwaliWelcomeDialog extends StatefulWidget {
  const DiwaliWelcomeDialog({super.key});
  @override
  State<DiwaliWelcomeDialog> createState() => _DiwaliWelcomeDialogState();
}

class _DiwaliWelcomeDialogState extends State<DiwaliWelcomeDialog> with TickerProviderStateMixin {
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
  late final AnimationController _flame =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..forward();
  bool _showQr = false;

  static const _gold = Color(0xFFFFC857);
  static const _orange = Color(0xFFFF8F00);

  @override
  void dispose() {
    _loop.dispose();
    _flame.dispose();
    _enter.dispose();
    super.dispose();
  }

  Widget _stagger(double start, Widget child) {
    final a = CurvedAnimation(
        parent: _enter, curve: Interval(start, math.min(start + 0.35, 1.0), curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(a),
        child: child,
      ),
    );
  }

  Widget _point(String emoji, String title, String body) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _gold.withValues(alpha: 0.25)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: _gold, fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 3),
                Text(body, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13.5, height: 1.4)),
              ]),
            ),
          ]),
        ),
      );

  ButtonStyle get _outlineStyle => OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
            constraints: const BoxConstraints(maxWidth: 440),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2A0F3D), Color(0xFF3D1405), Color(0xFF14070A)],
              ),
              border: Border.all(color: _orange.withValues(alpha: 0.7), width: 1.4),
              boxShadow: [BoxShadow(color: _orange.withValues(alpha: 0.35), blurRadius: 40, spreadRadius: 2)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Stack(children: [
                // floating golden sparks
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _loop,
                      builder: (_, __) => CustomPaint(painter: _SparkPainter(_loop.value)),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    // Marigold toran: drops in from the top, then sways gently
                    AnimatedBuilder(
                      animation: Listenable.merge([_enter, _flame]),
                      builder: (_, child) {
                        final drop = Curves.bounceOut.transform(math.min(_enter.value / 0.45, 1.0));
                        return Transform.translate(
                          offset: Offset(0, -60 * (1 - drop)),
                          child: Transform.rotate(
                            angle: (_flame.value - 0.5) * 0.008,
                            alignment: Alignment.topCenter,
                            child: Opacity(opacity: drop, child: child),
                          ),
                        );
                      },
                      child: Image.asset('assets/diwali/toran.png', width: double.infinity, fit: BoxFit.fitWidth),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        // diya + rotating gold mandala + flame glow
                        SizedBox(
                          height: 170,
                          child: Stack(alignment: Alignment.center, children: [
                            RotationTransition(
                              turns: _loop,
                              child: Opacity(
                                opacity: 0.22,
                                child: SvgPicture.asset('assets/diwali/mandala.svg', height: 170),
                              ),
                            ),
                            // glow behind the flame
                            AnimatedBuilder(
                              animation: _flame,
                              builder: (_, __) => Transform.translate(
                                offset: const Offset(0, -22),
                                child: Container(
                                  width: 70,
                                  height: 90,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(60),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _orange.withValues(alpha: 0.35 + 0.30 * _flame.value),
                                        blurRadius: 45 + 25 * _flame.value,
                                        spreadRadius: 4 + 8 * _flame.value,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // diya with a tiny flicker, anchored at the base
                            AnimatedBuilder(
                              animation: _flame,
                              builder: (_, child) => Transform.scale(
                                scale: 1 + 0.025 * _flame.value,
                                alignment: Alignment.bottomCenter,
                                child: child,
                              ),
                              child: Image.asset('assets/diwali/diya.png', height: 150),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 8),
                        _stagger(
                          0.12,
                          ShaderMask(
                            shaderCallback: (r) => const LinearGradient(
                                colors: [Color(0xFFFFE08A), Color(0xFFFF8F00)]).createShader(r),
                            child: const Text('Happy Diwali! 🪔',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _stagger(
                          0.20,
                          Text(
                            'Welcome to ZenMusic. May your life be as bright as a diya and every day sound as beautiful as your favourite song.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 14.5, height: 1.45),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _stagger(0.30, _point('🎶', 'Enjoy the app', 'Put on your favourite songs, light a diya, and let the festival mood flow.')),
                        _stagger(0.40, _point('👨‍👩‍👧‍👦', 'Share with family & friends', 'If ZenMusic makes you smile, send it to your loved ones this Diwali.')),
                        _stagger(0.50, _point('🪔', 'Light a diya for someone', 'Buy a diya from a small street seller, so their home can glow this Diwali too. Shy to post about it on social media or can\'t buy one? That\'s okay, a kind thought is enough.')),
                        const SizedBox(height: 10),
                        _stagger(
                          0.60,
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: LinearGradient(colors: [_orange.withValues(alpha: 0.18), Colors.pink.withValues(alpha: 0.10)]),
                              border: Border.all(color: _gold.withValues(alpha: 0.35)),
                            ),
                            child: Column(children: [
                              const Text('💛 Support us', style: TextStyle(color: _gold, fontWeight: FontWeight.w800, fontSize: 16)),
                              const SizedBox(height: 6),
                              Text(
                                'If you wish, you can send any amount to the QR below. I will not keep this money. '
                                'I will donate it, so it reaches people who need a little light this Diwali. '
                                'Even a small amount, or just sharing the app, means a lot.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.86), fontSize: 13.5, height: 1.45),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _gold,
                                  side: const BorderSide(color: _gold),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                onPressed: () => setState(() => _showQr = !_showQr),
                                icon: Icon(_showQr ? Icons.keyboard_arrow_up : Icons.qr_code_2_rounded),
                                label: Text(_showQr ? 'Hide QR' : 'Show QR'),
                              ),
                              // Your QR design, shown whole and uncropped
                              AnimatedSize(
                                duration: const Duration(milliseconds: 450),
                                curve: Curves.easeOutCubic,
                                child: _showQr
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(18),
                                          child: Container(
                                            color: Colors.black,
                                            child: Image.asset(
                                              'assets/diwali/support_qr.png',
                                              width: double.infinity,
                                              fit: BoxFit.fitWidth,
                                            ),
                                          ),
                                        ),
                                      )
                                    : const SizedBox(width: double.infinity),
                              ),
                              if (_showQr)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text('Screenshot this and scan it from your UPI app',
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11.5)),
                                ),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _stagger(
                          0.70,
                          Text(
                            'About me: I\'m Pratam, an indie developer from Goa, building ZenMusic on my own. '
                            'The app is still under development, so thank you for your patience, feedback and love. 🙏',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12.5, height: 1.45),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _stagger(
                          0.78,
                          Row(children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: _outlineStyle,
                                onPressed: () => SharePlus.instance.share(ShareParams(
                                    text:
                                        'Happy Diwali! 🪔 Try ZenMusic, a music player made by an indie dev from Goa.\n$_repoUrl')),
                                icon: const Icon(Icons.share_rounded, size: 18),
                                label: const Text('Share'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: _outlineStyle,
                                onPressed: () =>
                                    launchUrl(Uri.parse(_repoUrl), mode: LaunchMode.externalApplication),
                                icon: const Icon(Icons.star_rounded, size: 18),
                                label: const Text('GitHub'),
                              ),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 10),
                        _stagger(
                          0.86,
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _orange,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                elevation: 8,
                                shadowColor: _orange,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Start listening ✨',
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Golden sparks drifting upward like embers from a diya.
class _SparkPainter extends CustomPainter {
  _SparkPainter(this.t);
  final double t;
  static final _rnd = math.Random(7);
  static final _seeds =
      List.generate(34, (_) => [_rnd.nextDouble(), _rnd.nextDouble(), _rnd.nextDouble(), _rnd.nextDouble()]);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in _seeds) {
      final p = (t + s[1]) % 1.0;
      final x = s[0] * size.width + math.sin((p + s[2]) * math.pi * 2) * 12;
      final y = size.height * (1 - p);
      final fade = math.sin(p * math.pi);
      final r = 1.2 + s[3] * 2.6;
      final paint = Paint()
        ..color = Color.lerp(const Color(0xFFFFE08A), const Color(0xFFFF6A00), s[3])!.withValues(alpha: 0.75 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.t != t;
}
