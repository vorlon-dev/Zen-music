// ZenMusic — brand logos (SP-62). Zero-dependency CustomPainters for the
// Spotify and YouTube Music marks used on the settings Services tiles.
//
// The Spotify mark is the exact simple-icons path (simple-icons 11.14.0,
// CC0-4.0) rendered through a minimal SVG-path parser that supports the
// command subset brand paths actually use (M m L l H h V v C c S s Q q T t
// Z z — no arc commands). First subpath = outer disc (brand green), the
// remaining subpaths = the three wave slivers (white). The YouTube Music
// mark is pure geometry: red disc, white ring, white play triangle.

import 'dart:ui' show Path;

import 'package:flutter/material.dart';

const Color kSpotifyGreen = Color(0xFF1DB954);
const Color kYouTubeRed = Color(0xFFFF0000);

/// Exact simple-icons 11.14.0 "Spotify" path (24x24, CC0-4.0).
const String kSpotifyBrandPath =
    'M12 0C5.4 0 0 5.4 0 12s5.4 12 12 12 12-5.4 12-12S18.66 0 12 0zm'
    '5.521 17.34c-.24.359-.66.48-1.021.24-2.82-1.74-6.36-2.101-10.561'
    '-1.141-.418.122-.779-.179-.899-.539-.12-.421.18-.78.54-.9 4.56'
    '-1.021 8.52-.6 11.64 1.32.42.18.479.659.301 1.02zm1.44-3.3c-.301'
    '.42-.841.6-1.262.3-3.239-1.98-8.159-2.58-11.939-1.38-.479.12-1.02'
    '-.12-1.14-.6-.12-.48.12-1.021.6-1.141C9.6 9.9 15 10.561 18.72 12'
    '.84c.361.181.54.78.241 1.2zm.12-3.36C15.24 8.4 8.82 8.16 5.16 9'
    '.301c-.6.179-1.2-.181-1.38-.721-.18-.601.18-1.2.72-1.381 4.26-1.26 '
    '11.28-1.02 15.721 1.621.539.3.719 1.02.419 1.56-.299.421-1.02.599'
    '-1.559.3z';

/// Minimal SVG path-data parser -> one [Path] per subpath.
/// Bounds-guarded: a malformed tail is dropped instead of crashing.
List<Path> parseSvgSubpaths(String d) {
  final token =
      RegExp(r'[MmLlHhVvCcSsQqTtZz]|[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?');
  final matches = token.allMatches(d).toList();
  var i = 0;

  bool atNumber() {
    if (i >= matches.length) return false;
    final s = matches[i].group(0)!;
    final c = s.codeUnitAt(0);
    return (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x2B || c == 0x2E;
  }

  double num() => double.parse(matches[i++].group(0)!);

  final subpaths = <Path>[];
  Path? cur;
  double cx = 0, cy = 0; // current point
  double sx = 0, sy = 0; // subpath start
  double? lastC2x, lastC2y; // previous cubic control 2 (for S/s)
  double? lastQx, lastQy; // previous quadratic control (for T/t)

  void startNew(double x, double y) {
    cur = Path();
    cur!.moveTo(x, y);
    subpaths.add(cur!);
    sx = x;
    sy = y;
    cx = x;
    cy = y;
  }

  void ensurePath() => cur ??= Path();

  while (i < matches.length) {
    final t = matches[i].group(0)!;
    final c = t.codeUnitAt(0);
    final isCmd = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
    if (!isCmd) {
      i++; // stray number — skip defensively
      continue;
    }
    i++;
    switch (t) {
      case 'M':
      case 'm':
        while (atNumber()) {
          final x = t == 'M' ? num() : cx + num();
          final y = t == 'M' ? num() : cy + num();
          if (cur == null) {
            startNew(x, y);
          } else {
            cur!.moveTo(x, y);
            sx = x;
            sy = y;
            cx = x;
            cy = y;
          }
        }
        break;
      case 'L':
      case 'l':
        ensurePath();
        while (atNumber()) {
          cx = t == 'L' ? num() : cx + num();
          cy = t == 'L' ? num() : cy + num();
          cur!.lineTo(cx, cy);
          lastC2x = lastC2y = lastQx = lastQy = null;
        }
        break;
      case 'H':
      case 'h':
        ensurePath();
        while (atNumber()) {
          cx = t == 'H' ? num() : cx + num();
          cur!.lineTo(cx, cy);
          lastC2x = lastC2y = lastQx = lastQy = null;
        }
        break;
      case 'V':
      case 'v':
        ensurePath();
        while (atNumber()) {
          cy = t == 'V' ? num() : cy + num();
          cur!.lineTo(cx, cy);
          lastC2x = lastC2y = lastQx = lastQy = null;
        }
        break;
      case 'C':
      case 'c':
        while (atNumber()) {
          final x1 = t == 'C' ? num() : cx + num();
          final y1 = t == 'C' ? num() : cy + num();
          final x2 = t == 'C' ? num() : cx + num();
          final y2 = t == 'C' ? num() : cy + num();
          final x = t == 'C' ? num() : cx + num();
          final y = t == 'C' ? num() : cy + num();
          cur?.cubicTo(x1, y1, x2, y2, x, y);
          lastC2x = x2;
          lastC2y = y2;
          lastQx = lastQy = null;
          cx = x;
          cy = y;
        }
        break;
      case 'S':
      case 's':
        while (atNumber()) {
          final x2 = t == 'S' ? num() : cx + num();
          final y2 = t == 'S' ? num() : cy + num();
          final x = t == 'S' ? num() : cx + num();
          final y = t == 'S' ? num() : cy + num();
          final rx = lastC2x ?? cx;
          final ry = lastC2y ?? cy;
          cur?.cubicTo(2 * cx - rx, 2 * cy - ry, x2, y2, x, y);
          lastC2x = x2;
          lastC2y = y2;
          lastQx = lastQy = null;
          cx = x;
          cy = y;
        }
        break;
      case 'Q':
      case 'q':
        while (atNumber()) {
          final qx = t == 'Q' ? num() : cx + num();
          final qy = t == 'Q' ? num() : cy + num();
          final x = t == 'Q' ? num() : cx + num();
          final y = t == 'Q' ? num() : cy + num();
          cur?.quadraticBezierTo(qx, qy, x, y);
          lastQx = qx;
          lastQy = qy;
          lastC2x = lastC2y = null;
          cx = x;
          cy = y;
        }
        break;
      case 'T':
      case 't':
        while (atNumber()) {
          final x = t == 'T' ? num() : cx + num();
          final y = t == 'T' ? num() : cy + num();
          final rx = lastQx ?? cx;
          final ry = lastQy ?? cy;
          cur?.quadraticBezierTo(2 * cx - rx, 2 * cy - ry, x, y);
          lastQx = 2 * cx - rx;
          lastQy = 2 * cy - ry;
          lastC2x = lastC2y = null;
          cx = x;
          cy = y;
        }
        break;
      case 'Z':
      case 'z':
        cur?.close();
        cx = sx;
        cy = sy;
        cur = null; // next coordinate pair starts a fresh subpath
        break;
    }
  }
  return subpaths;
}

class SpotifyLogo extends StatelessWidget {
  const SpotifyLogo({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: const _SpotifyPainter()),
    );
  }
}

class _SpotifyPainter extends CustomPainter {
  const _SpotifyPainter();

  static final List<Path> _subpaths = parseSvgSubpaths(kSpotifyBrandPath);

  @override
  void paint(Canvas canvas, Size size) {
    if (_subpaths.isEmpty) return;
    final scale = size.width / 24;
    canvas.save();
    canvas.scale(scale, scale);
    // Subpath 0 = outer disc; the rest are the three wave slivers.
    for (var i = 0; i < _subpaths.length; i++) {
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = i == 0 ? kSpotifyGreen : const Color(0xFFFFFFFF);
      canvas.drawPath(_subpaths[i], paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SpotifyPainter oldDelegate) => false;
}

class YouTubeMusicLogo extends StatelessWidget {
  const YouTubeMusicLogo({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: const _YouTubeMusicPainter()),
    );
  }
}

class _YouTubeMusicPainter extends CustomPainter {
  const _YouTubeMusicPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Red disc.
    canvas.drawCircle(c, r, Paint()..color = kYouTubeRed);

    // White ring.
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12
        ..color = const Color(0xFFFFFFFF),
    );

    // White play triangle (right-pointing, centered in the ring).
    final tw = r * 0.40;
    final th = r * 0.52;
    final tri = Path()
      ..moveTo(c.dx + tw, c.dy)
      ..lineTo(c.dx - tw * 0.72, c.dy - th)
      ..lineTo(c.dx - tw * 0.72, c.dy + th)
      ..close();
    canvas.drawPath(
      tri,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.fill
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _YouTubeMusicPainter oldDelegate) => false;
}
