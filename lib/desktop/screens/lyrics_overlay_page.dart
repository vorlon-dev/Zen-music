// ZenMusic · vorlon-dev

import 'package:flutter/material.dart';

import 'package:zenmusic/desktop/services/lyrics_overlay_bridge.dart';
import 'package:zenmusic/desktop/services/lyrics_translator.dart';

const Color _kBg = Color(0xFF121216);
const Color _kSurface = Color(0xFF1B1B21);

/// Fixed row height for the synced list — makes scroll math exact.
const double _kLineExtent = 44.0;

/// Taller rows while a translation is shown under each line.
const double _kLineExtentTr = 64.0;

const Map<String, String> _kTrLangs = <String, String>{
  'en': 'English', 'hi': 'Hindi', 'es': 'Spanish', 'fr': 'French',
  'de': 'German', 'pt': 'Portuguese', 'ru': 'Russian', 'ja': 'Japanese',
  'ko': 'Korean', 'ar': 'Arabic', 'id': 'Indonesian', 'tr': 'Turkish',
};

class LyricsOverlayApp extends StatelessWidget {
  const LyricsOverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ZenMusic Lyrics',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _kBg,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          surface: _kSurface,
        ),
        useMaterial3: true,
      ),
      home: const LyricsOverlayPage(),
    );
  }
}

class LyricsOverlayPage extends StatefulWidget {
  const LyricsOverlayPage({super.key});

  @override
  State<LyricsOverlayPage> createState() => _LyricsOverlayPageState();
}

class _LyricsOverlayPageState extends State<LyricsOverlayPage> {
  final LyricsOverlayBridge _bridge = LyricsOverlayBridge.instance;
  final ScrollController _scroll = ScrollController();

  int _activeIndex = -2; // -2 = nothing computed yet
  String? _trackKey; // resets follow state when the track changes

  // ---- translation ----
  bool _showTr = false;
  bool _trLoading = false;
  List<String>? _tr;
  String _trLang = LyricsTranslator.targetLang;
  int _trToken = 0; // drops results from stale requests

  double get _extent => (_showTr && _tr != null) ? _kLineExtentTr : _kLineExtent;

  Future<void> _loadTr(List<OverlayLyricLine> lines, String key) async {
    final int token = ++_trToken;
    final List<String>? res = await LyricsTranslator.translate(
      lines.map((OverlayLyricLine l) => l.text).toList(),
      cacheKey: key,
      lang: _trLang,
    );
    if (!mounted || token != _trToken) return;
    setState(() {
      _tr = res;
      _trLoading = false;
      if (res == null) {
        _showTr = false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Translation failed. Check your connection.')),
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  int _activeLineFor(int positionMs, List<OverlayLyricLine> lines) {
    int active = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].timeMs <= positionMs) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }

  void _follow(int active) {
    if (active == _activeIndex) return;
    _activeIndex = active;
    if (!_scroll.hasClients) return;
    // Keep the active line roughly 40% from the top, clamped to the list.
    final double target = ((active - 3) * _extent)
        .clamp(0.0, _scroll.position.maxScrollExtent)
        .toDouble();
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          _bridge.overlayTrack,
          _bridge.overlayStatus,
          _bridge.overlayLines,
          _bridge.overlayPlain,
          _bridge.overlayPosition,
          _bridge.overlayPinned,
        ]),
        builder: (BuildContext context, _) {
          final OverlayTrack? track = _bridge.overlayTrack.value;
          if (track == null) {
            return const Center(
              child: Text(
                'Nothing playing',
                style: TextStyle(color: Colors.white38, fontSize: 15),
              ),
            );
          }

          // New track → restart the follow state from the top.
          final String key =
              '${track.title}|${track.artist}';
          if (key != _trackKey) {
            _trackKey = key;
            _activeIndex = -2;
            _tr = null;
            _trLoading = false;
            _trToken++;
            if (_scroll.hasClients && _scroll.position.hasContentDimensions) {
              _scroll.jumpTo(0);
            }
          }

          final String status = _bridge.overlayStatus.value;
          final List<OverlayLyricLine>? lines = _bridge.overlayLines.value;

          // Follow the position while synced lyrics are shown.
          if (status == 'synced' && lines != null && lines.isNotEmpty) {
            final int active = _activeLineFor(
                _bridge.overlayPosition.value.inMilliseconds, lines);
            if (active >= 0) _follow(active);
          }

          // Kick off translation once synced lines are available.
          if (_showTr && _tr == null && !_trLoading &&
              status == 'synced' && lines != null && lines.isNotEmpty) {
            _trLoading = true;
            final List<OverlayLyricLine> ls = lines;
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _loadTr(ls, key));
          }

          return Column(
            children: <Widget>[
              _header(track),
              const Divider(height: 1, color: Colors.white10),
              Expanded(child: _body(status, lines)),
            ],
          );
        },
      ),
    );
  }

  Widget _header(OverlayTrack track) {
    return Container(
      color: _kSurface,
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Translation language',
            color: _kSurface,
            icon: const Icon(Icons.language, size: 18, color: Colors.white38),
            onSelected: (String c) {
              LyricsTranslator.setTargetLang(c);
              setState(() {
                _trLang = c;
                _tr = null;
                _trLoading = false;
                _trToken++;
                _showTr = true;
              });
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              for (final MapEntry<String, String> e in _kTrLangs.entries)
                PopupMenuItem<String>(
                  value: e.key,
                  child: Text(e.value,
                      style: TextStyle(
                        color: e.key == _trLang ? Colors.white : Colors.white60,
                        fontWeight: e.key == _trLang ? FontWeight.w700 : FontWeight.w400,
                      )),
                ),
            ],
          ),
          IconButton(
            tooltip: _showTr ? 'Hide translation' : 'Translate lyrics',
            icon: _trLoading
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.translate,
                    size: 18, color: _showTr ? Colors.white70 : Colors.white24),
            onPressed: () => setState(() {
              _showTr = !_showTr;
              if (!_showTr) {
                _trToken++;
                _trLoading = false;
              }
            }),
          ),
          ListenableBuilder(
            listenable: _bridge.overlayPinned,
            builder: (BuildContext context, _) {
              final bool pinned = _bridge.overlayPinned.value;
              return IconButton(
                tooltip: pinned ? 'Unpin from top' : 'Pin on top',
                icon: Icon(
                  pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 18,
                  color: pinned ? Colors.white70 : Colors.white24,
                ),
                onPressed: () {
                  // Optimistic flip; the main window pushes the
                  // authoritative state right back.
                  _bridge.overlayPinned.value = !pinned;
                  LyricsOverlayBridge.sendCommand('pin', pinned: !pinned);
                },
              );
            },
          ),
          IconButton(
            tooltip: 'Close overlay',
            icon: const Icon(Icons.close, size: 18, color: Colors.white38),
            onPressed: () => LyricsOverlayBridge.sendCommand('close'),
          ),
        ],
      ),
    );
  }

  Widget _body(String status, List<OverlayLyricLine>? lines) {
    switch (status) {
      case 'synced':
        final List<OverlayLyricLine> list =
            lines ?? const <OverlayLyricLine>[];
        if (list.isEmpty) return _centered('No lyrics found for this track');
        return ListView.builder(
          controller: _scroll,
          itemExtent: _extent,
          padding: EdgeInsets.symmetric(
            vertical: MediaQuery.of(context).size.height * 0.28,
            horizontal: 24,
          ),
          itemCount: list.length,
          itemBuilder: (BuildContext context, int i) {
            final bool active = i == _activeIndex;
            final Color color = active
                ? Colors.white
                : (i < _activeIndex ? Colors.white24 : Colors.white38);
            final String? tr = (_showTr && _tr != null && i < _tr!.length)
                ? _tr![i].trim()
                : null;
            final Text main = Text(
              list[i].text.isEmpty ? '♪' : list[i].text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: active ? 19 : 15,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            );
            if (tr == null) {
              return Align(alignment: Alignment.centerLeft, child: main);
            }
            return Align(
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  main,
                  if (tr.isNotEmpty && tr != list[i].text.trim())
                    Text(
                      tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? Colors.white70 : Colors.white24,
                        fontSize: active ? 14 : 12,
                      ),
                    ),
                ],
              ),
            );
          },
        );
      case 'plain':
        final String? plain = _bridge.overlayPlain.value;
        if (plain == null || plain.trim().isEmpty) {
          return _centered('No lyrics found for this track');
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Text(
            plain.trim(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              height: 1.6,
            ),
          ),
        );
      case 'instrumental':
        return _centered('♪  Instrumental  ♪');
      case 'loading':
        return const Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        );
      case 'none':
      default:
        return _centered('No lyrics found for this track');
    }
  }

  Widget _centered(String text) => Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white38, fontSize: 14),
        ),
      );
}
