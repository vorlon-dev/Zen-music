// SP-76 widget tests — SyncedLyricsView renders resolved lyrics.
//
// Guards the player-page lyric surface end-to-end at the widget level:
// word-timed data must render the karaoke word spans, plain data must
// render its lines, and a miss must show the not-found empty state.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zenmusic/desktop/screens/player/synced_lyrics_view.dart';
import 'package:zenmusic/desktop/services/lyrics_service.dart';

LyricWord _w(int ms, int dur, String text) =>
    LyricWord(timeMs: ms, durationMs: dur, text: text);

LyricsData _wordTimed() => LyricsData(
      trackName: 'T',
      artistName: 'A',
      synced: [
        LyricLine(0, 'Hello world today', durationMs: 4000, words: [
          _w(0, 1000, 'Hello '),
          _w(1000, 1500, 'world '),
          _w(2500, 1500, 'today'),
        ]),
        LyricLine(4000, 'Second line here', durationMs: 4000, words: [
          _w(4000, 2000, 'Second '),
          _w(6000, 2000, 'line here'),
        ]),
      ],
      plain: null,
      instrumental: false,
      wordSync: true,
    );

LyricsData _plainOnly() => LyricsData(
      trackName: 'T',
      artistName: 'A',
      synced: null,
      plain: 'Just some plain lyrics text',
      instrumental: false,
      wordSync: false,
    );

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: Scaffold(body: child),
    );

Future<void> _pump(WidgetTester tester, LyricsData? data,
    {Duration initial = const Duration(seconds: 1),
    Stream<Duration>? stream}) async {
  await tester.pumpWidget(_host(SizedBox(
    width: 500,
    height: 700,
    child: SyncedLyricsView(
      lyrics: data,
      positionStream: stream ?? const Stream<Duration>.empty(),
      initialPosition: initial,
      accentColor: Colors.tealAccent,
    ),
  )));
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pump(const Duration(milliseconds: 120));
}

Iterable<String> _richTexts(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((r) => r.text.toPlainText());

void main() {
  testWidgets('word-timed lyrics render lines AND per-word spans',
      (tester) async {
    // The app drives evaluation through position events — emit one.
    final ctrl = StreamController<Duration>();
    await _pump(tester, _wordTimed(), stream: ctrl.stream);
    ctrl.add(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    unawaited(ctrl.close());
    expect(tester.takeException(), isNull);
    final plain = _richTexts(tester).join('\n');
    expect(plain, contains('Hello world today'),
        reason: 'active line text must render');
    expect(plain, contains('Second line here'),
        reason: 'upcoming line must render');
    // The word wipe builds per-word TextSpans; the plain text of the
    // active line must be assembled from word spans (not one big run).
    // NOTE: Text.rich wraps the given span in an outer TextSpan on this
    // Flutter version, so assert on LEAF spans, not root children.
    final dump = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) {
          final leaves = <String>[];
          void collect(InlineSpan s) {
            if (s is TextSpan) {
              if (s.text != null) leaves.add(s.text!);
              for (final c in s.children ?? const <InlineSpan>[]) {
                collect(c);
              }
            }
          }
          collect(r.text);
          return leaves;
        })
        .toList();
    final active = dump.any((leaves) =>
        leaves.length == 3 &&
        leaves[0] == 'Hello ' &&
        leaves[1] == 'world ' &&
        leaves[2] == 'today');
    expect(active, isTrue,
        reason: 'active line must be built from per-word TextSpans; '
            'leaf structure: $dump');
  });

  testWidgets('plain (untimed) lyrics render their lines', (tester) async {
    await _pump(tester, _plainOnly());
    expect(tester.takeException(), isNull);
    final plain = _richTexts(tester).join('\n');
    expect(plain, contains('Just some plain lyrics text'));
  });

  testWidgets('null lyrics show the not-found empty state', (tester) async {
    await _pump(tester, null);
    expect(tester.takeException(), isNull);
    expect(find.text('No lyrics available for this track'), findsOneWidget);
  });

  testWidgets('position stream updates keep the view stable (wipe timer)',
      (tester) async {
    final ctrl = StreamController<Duration>();
    await tester.pumpWidget(_host(SizedBox(
      width: 500,
      height: 700,
      child: SyncedLyricsView(
        lyrics: _wordTimed(),
        positionStream: ctrl.stream,
        initialPosition: Duration.zero,
        accentColor: Colors.tealAccent,
      ),
    )));
    await tester.pump();
    ctrl.add(const Duration(milliseconds: 500));
    await tester.pump();
    ctrl.add(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    await ctrl.close();
  });
}
