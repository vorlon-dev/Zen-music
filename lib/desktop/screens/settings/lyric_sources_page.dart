// ZenMusic · vorlon-dev
//
// Which lyric sources run, and in what order. The lyric providers are ported
// from BitChord (GPL-3.0, https://github.com/kushagrasinghx/BitChord).

import 'package:flutter/material.dart';

import 'package:zenmusic/desktop/services/lyrics_providers/lyric_doc.dart';
import 'package:zenmusic/desktop/services/lyrics_providers/lyrics_repository.dart';

class LyricSourcesPage extends StatefulWidget {
  const LyricSourcesPage({super.key});

  @override
  State<LyricSourcesPage> createState() => _LyricSourcesPageState();
}

class _LyricSourcesPageState extends State<LyricSourcesPage> {
  late List<LyricSourceId> _order = LyricSourcePrefs.order();
  late Set<LyricSourceId> _off = LyricSourcePrefs.disabled();
  bool _syllableFirst = LyricSourcePrefs.syllableFirst;

  @override
  Widget build(BuildContext context) {
    // LRCLIB keeps its own lookup inside the app, so it is not reorderable.
    final sources = _order.where((s) => s != LyricSourceId.lrclib).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Lyric sources')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: <Widget>[
              SwitchListTile(
                title: const Text('Word timing first'),
                subtitle: const Text(
                    'A word-by-word answer from any source beats a '
                    'line-by-line answer from a higher one.'),
                value: _syllableFirst,
                onChanged: (bool v) async {
                  setState(() => _syllableFirst = v);
                  await LyricSourcePrefs.setSyllableFirst(v);
                },
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Every enabled source is asked at once and read in this '
                  'order, top first. Drag to reorder.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: true,
                  itemCount: sources.length,
                  onReorder: (int from, int to) async {
                    if (to > from) to -= 1;
                    final moved = sources.removeAt(from);
                    sources.insert(to, moved);
                    final next = <LyricSourceId>[
                      ...sources,
                      if (_order.contains(LyricSourceId.lrclib))
                        LyricSourceId.lrclib,
                    ];
                    setState(() => _order = next);
                    await LyricSourcePrefs.setOrder(next);
                  },
                  itemBuilder: (BuildContext context, int i) {
                    final s = sources[i];
                    return SwitchListTile(
                      key: ValueKey<String>(s.name),
                      title: Text(s.label),
                      subtitle: Text(
                          s.detail),
                      secondary: Icon(s.wordSynced
                          ? Icons.lyrics
                          : Icons.format_align_left),
                      value: !_off.contains(s),
                      onChanged: (bool on) async {
                        setState(() => on ? _off.remove(s) : _off.add(s));
                        await LyricSourcePrefs.setEnabled(s, on);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
