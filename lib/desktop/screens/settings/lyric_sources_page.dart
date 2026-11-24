// ZenMusic · vorlon-dev
//
// Which lyric sources run, and in what order. The lyric providers are ported
// from BitChord (GPL-3.0, https://github.com/kushagrasinghx/BitChord).
//
// Logos: drop one file per source into assets/lyrics/, named after the
// source (e.g. musixmatch.png, genius.svg, lrcred.png, betterlyrics.webp).
// Letters only, any case, png / jpg / webp / svg. A source without a file
// shows the app logo instead.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:zenmusic/desktop/core/widgets/zen_logo.dart';
import 'package:zenmusic/desktop/services/lyrics_providers/lyric_doc.dart';
import 'package:zenmusic/desktop/services/lyrics_providers/lyrics_repository.dart';
import 'package:zenmusic/desktop/utils/zen_settings_kit.dart';

class LyricSourcesPage extends StatefulWidget {
  const LyricSourcesPage({super.key});

  @override
  State<LyricSourcesPage> createState() => _LyricSourcesPageState();
}

class _LyricSourcesPageState extends State<LyricSourcesPage> {
  late List<LyricSourceId> _order = LyricSourcePrefs.order();
  late Set<LyricSourceId> _off = LyricSourcePrefs.disabled();
  bool _syllableFirst = LyricSourcePrefs.syllableFirst;

  // LRCLIB keeps its own lookup inside the app, so it is not reorderable.
  List<LyricSourceId> get _sources =>
      _order.where((s) => s != LyricSourceId.lrclib).toList();

  Future<void> _reorder(int from, int to) async {
    final sources = _sources;
    if (to > from) to -= 1;
    final moved = sources.removeAt(from);
    sources.insert(to, moved);
    final next = <LyricSourceId>[
      ...sources,
      if (_order.contains(LyricSourceId.lrclib)) LyricSourceId.lrclib,
    ];
    HapticFeedback.selectionClick();
    setState(() => _order = next);
    await LyricSourcePrefs.setOrder(next);
  }

  Future<void> _toggle(LyricSourceId s, bool on) async {
    HapticFeedback.selectionClick();
    setState(() => on ? _off.remove(s) : _off.add(s));
    await LyricSourcePrefs.setEnabled(s, on);
  }

  Future<void> _reset() async {
    final next = LyricSourceId.values.toList();
    setState(() {
      _order = next;
      _off = <LyricSourceId>{};
    });
    await LyricSourcePrefs.setOrder(next);
    for (final s in LyricSourceId.values) {
      await LyricSourcePrefs.setEnabled(s, true);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Sources reset to the default order'),
        duration: Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final sources = _sources;
    final active = sources.where((s) => !_off.contains(s)).length;
    final words = sources.where((s) => s.wordSynced && !_off.contains(s)).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lyric sources'),
        actions: [
          IconButton(
            tooltip: 'Reset to default',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: _reset,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
            children: [
              // ── summary ────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(Icons.lyrics_rounded, color: cs.onPrimary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$active of ${sources.length} sources on',
                            style: tt.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: cs.onPrimaryContainer)),
                        const SizedBox(height: 2),
                        Text(
                          '$words with word-by-word timing · all asked at once',
                          style: tt.bodyMedium?.copyWith(
                              color: cs.onPrimaryContainer
                                  .withValues(alpha: .75)),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 20),

              // ── behaviour ──────────────────────────────────────────────
              ZenSection(
                title: 'Behaviour',
                tint: const Color(0xFFB65CF0),
                children: [
                  ZenSwitchRow(
                    icon: Icons.timer_outlined,
                    title: 'Word timing first',
                    subtitle: 'A word-by-word answer from any source beats a '
                        'line-by-line answer from a higher one.',
                    value: _syllableFirst,
                    onChanged: (v) async {
                      setState(() => _syllableFirst = v);
                      await LyricSourcePrefs.setSyllableFirst(v);
                    },
                  ),
                ],
              ),

              // ── priority list ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(children: [
                  Expanded(
                    child: Text('Priority',
                        style: tt.labelLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600)),
                  ),
                  Icon(Icons.drag_indicator_rounded,
                      size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('Hold and drag to reorder, top is read first',
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: sources.length,
                onReorder: _reorder,
                proxyDecorator: (child, _, anim) => Material(
                  color: Colors.transparent,
                  elevation: 6 * Curves.easeOut.transform(anim.value),
                  borderRadius: BorderRadius.circular(22),
                  child: child,
                ),
                itemBuilder: (context, i) {
                  final s = sources[i];
                  return Padding(
                    key: ValueKey<String>(s.name),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _SourceTile(
                      rank: i + 1,
                      source: s,
                      on: !_off.contains(s),
                      onChanged: (v) => _toggle(s, v),
                      handle: ReorderableDragStartListener(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(Icons.drag_handle_rounded,
                              color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                  );
                },
              ),

              // ── fixed fallback ─────────────────────────────────────────
              const SizedBox(height: 8),
              _SourceTile(
                source: LyricSourceId.lrclib,
                on: true,
                locked: true,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'LRCLIB is the built-in fallback: it is always asked last '
                  'and cannot be turned off or moved.',
                  style:
                      tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.on,
    this.rank,
    this.onChanged,
    this.handle,
    this.locked = false,
  });
  final LyricSourceId source;
  final bool on;
  final int? rank;
  final ValueChanged<bool>? onChanged;
  final Widget? handle;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: on ? 1 : .55,
      child: Material(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: locked ? null : () => onChanged?.call(!on),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(children: [
              if (rank != null)
                SizedBox(
                  width: 22,
                  child: Text('$rank',
                      textAlign: TextAlign.center,
                      style: tt.labelLarge?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700)),
                ),
              if (rank != null) const SizedBox(width: 6),
              _SourceLogo(source, size: 46),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(source.label,
                        style: tt.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(source.detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    _Badge(
                      icon: source.wordSynced
                          ? Icons.lyrics_rounded
                          : Icons.format_align_left_rounded,
                      label: source.wordSynced ? 'Word by word' : 'Line by line',
                      color: source.wordSynced ? cs.primary : cs.outline,
                    ),
                  ],
                ),
              ),
              if (locked)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(Icons.lock_outline_rounded,
                      color: cs.onSurfaceVariant),
                )
              else ...[
                Switch.adaptive(value: on, onChanged: onChanged),
                if (handle != null) handle!,
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ]),
      );
}

/// The source's logo from assets/lyrics/, or the app logo when none exists.
class _SourceLogo extends StatelessWidget {
  const _SourceLogo(this.source, {this.size = 46});
  final LyricSourceId source;
  final double size;

  static Future<Map<String, String>>? _index;

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// normalised file name -> asset path, read once from the asset manifest.
  static Future<Map<String, String>> _load() => _index ??= () async {
        final out = <String, String>{};
        try {
          final m = await AssetManifest.loadFromAssetBundle(rootBundle);
          for (final a in m.listAssets()) {
            if (!a.startsWith('assets/lyrics/')) continue;
            final file = a.substring('assets/lyrics/'.length);
            final dot = file.lastIndexOf('.');
            if (dot <= 0) continue;
            final ext = file.substring(dot + 1).toLowerCase();
            if (!const {'png', 'jpg', 'jpeg', 'webp', 'svg'}.contains(ext)) {
              continue;
            }
            out[_norm(file.substring(0, dot))] = a;
          }
        } catch (_) {}
        return out;
      }();

  Widget _fallback() => ZenLogoWidget(size: size, borderRadius: size * .3);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: _load(),
      builder: (context, snap) {
        final idx = snap.data;
        final path = idx == null
            ? null
            : (idx[_norm(source.name)] ?? idx[_norm(source.label)]);
        final Widget child;
        if (path == null) {
          child = _fallback();
        } else if (path.toLowerCase().endsWith('.svg')) {
          child = SvgPicture.asset(path,
              width: size,
              height: size,
              fit: BoxFit.contain,
              placeholderBuilder: (_) => _fallback());
        } else {
          child = Image.asset(path,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback());
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * .3),
          child: SizedBox(width: size, height: size, child: child),
        );
      },
    );
  }
}
