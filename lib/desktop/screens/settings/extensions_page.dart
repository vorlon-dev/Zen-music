// ZenMusic · vorlon-dev
//
// Add extension repositories, install lyric-source extensions, set their
// priority. See services/extensions/zen_extensions.dart for the contract.

import 'package:flutter/material.dart';

import 'package:zenmusic/desktop/services/extensions/zen_extensions.dart';

class ExtensionsPage extends StatefulWidget {
  const ExtensionsPage({super.key});

  @override
  State<ExtensionsPage> createState() => _ExtensionsPageState();
}

class _ExtensionsPageState extends State<ExtensionsPage> {
  final TextEditingController _url = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _addRepo() async {
    if (_busy) return;
    setState(() => _busy = true);
    final err = await ZenExtensions.addRepo(_url.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) {
      _url.clear();
    } else {
      _toast(err);
    }
  }

  Future<void> _browse(String registryUrl) async {
    List<RegistryEntry> list;
    try {
      list = await ZenExtensions.fetchRegistry(registryUrl);
    } catch (e) {
      _toast('Could not load repository ($e)');
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        builder: (_, ScrollController sc) => list.isEmpty
            ? const Center(child: Text('No extensions in this repository'))
            : ListView.builder(
                controller: sc,
                itemCount: list.length,
                itemBuilder: (_, int i) {
                  final e = list[i];
                  final have = ZenExtensions.installed().any((x) => x.id == e.id);
                  return ListTile(
                    leading: const Icon(Icons.extension),
                    title: Text('${e.name}  v${e.version}'),
                    subtitle: Text(e.description.isEmpty
                        ? (e.format == 'mornye' ? 'Mornye package' : e.hosts.join(', '))
                        : e.description),
                    trailing: TextButton(
                      onPressed: () async {
                        Navigator.of(c).pop();
                        await _confirmInstall(e);
                      },
                      child: Text(have ? 'Update' : 'Install'),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _confirmInstall(RegistryEntry e) async {
    _toast('Downloading ${e.name}…');
    final (p, err) = await ZenExtensions.prepare(e);
    if (!mounted) return;
    if (p == null) {
      _toast(err ?? 'Install failed');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text('Install ${e.name}?'),
        content: Text(
          'Adds: ${p.kinds.join(' + ')} source'
          '${e.format == 'mornye' ? ' (Mornye package)' : ''}.\n\n'
          'This extension runs code on your device. It can only contact:\n\n'
          '${p.hosts.join('\n')}\n\n'
          '${p.verified ? 'The script checksum was verified.' : 'Warning: the repository gave no checksum, so the script cannot be verified.'}\n\n'
          'It cannot read your files, accounts or library.',
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Install')),
        ],
      ),
    );
    if (ok != true) return;
    final res = await ZenExtensions.commit(p);
    if (mounted) _toast(res ?? '${e.name} installed');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Extensions')),
      body: ValueListenableBuilder<int>(
        valueListenable: ZenExtensions.changes,
        builder: (BuildContext context, int _, Widget? __) {
          final repos = ZenExtensions.repos();
          final installed = ZenExtensions.installed();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      'Extensions add lyric sources and track metadata. Mornye lyrics / '
                      'metadata packages work too. Only install ones from authors you trust.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _url,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'Repository URL',
                            hintText: 'https://github.com/owner/repo',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _addRepo(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _busy ? null : _addRepo,
                        child: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Add'),
                      ),
                    ]),
                  ),
                  if (repos.isNotEmpty)
                    const _Head('Repositories'),
                  for (final r in repos)
                    ListTile(
                      leading: const Icon(Icons.folder_open),
                      title: Text(r.replaceFirst('https://', ''),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _browse(r),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => ZenExtensions.removeRepo(r),
                      ),
                    ),
                  const _Head('Installed (top = highest priority)'),
                  if (installed.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Nothing installed yet. Add a repository, '
                          'tap it, then install.'),
                    )
                  else
                    ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      onReorder: ZenExtensions.reorder,
                      children: <Widget>[
                        for (final e in installed)
                          SwitchListTile(
                            key: ValueKey<String>(e.id),
                            secondary: Icon(e.verified
                                ? Icons.verified_outlined
                                : Icons.warning_amber_outlined),
                            title: Text('${e.name}  v${e.version}'),
                            subtitle: Text('${e.kinds.join(' + ')} · ${e.hosts.join(', ')}'),
                            value: e.enabled,
                            onChanged: (bool on) =>
                                ZenExtensions.setEnabled(e.id, on),
                          ),
                      ],
                    ),
                  for (final e in installed)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => ZenExtensions.uninstall(e.id),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: Text('Remove ${e.name}'),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(t,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
