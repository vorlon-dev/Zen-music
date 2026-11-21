// ZenMusic · vorlon-dev
//
// Network storage: play music from a Subsonic / OpenSubsonic server or a
// WebDAV share. Servers live in Hive SETTINGS ('NET_SERVERS').

import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:zenmusic/desktop/core/utils/bg_json.dart';
import 'package:zenmusic/desktop/core/widgets/section_item.dart' show ListSkeleton;
import 'package:zenmusic/desktop/services/media_player.dart';

enum NetKind { subsonic, webdav }

class NetServer {
  NetServer({
    required this.id,
    required this.kind,
    required this.name,
    required this.url,
    this.user = '',
    this.password = '',
  });
  final String id;
  final NetKind kind;
  final String name;
  final String url; // no trailing slash
  final String user;
  final String password;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'url': url,
        'user': user,
        'password': password,
      };

  static NetServer fromJson(Map m) => NetServer(
        id: m['id'].toString(),
        kind: NetKind.values.firstWhere((k) => k.name == m['kind'],
            orElse: () => NetKind.subsonic),
        name: m['name'].toString(),
        url: m['url'].toString(),
        user: (m['user'] ?? '').toString(),
        password: (m['password'] ?? '').toString(),
      );

  String get basicAuth =>
      'Basic ${base64Encode(utf8.encode('$user:$password'))}';
}

class NetServers {
  static const _key = 'NET_SERVERS';

  static List<NetServer> load() {
    final raw = Hive.box('SETTINGS').get(_key, defaultValue: '[]') as String;
    try {
      return (jsonDecode(raw) as List)
          .map((e) => NetServer.fromJson(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<NetServer> l) => Hive.box('SETTINGS')
      .put(_key, jsonEncode(l.map((e) => e.toJson()).toList()));
}

/// One browsable entry (folder, artist, album or playable track).
class NetEntry {
  NetEntry({
    required this.title,
    required this.id,
    this.subtitle = '',
    this.isDir = true,
    this.song,
  });
  final String title, id, subtitle;
  final bool isDir;
  final Map<String, dynamic>? song;
}

abstract class NetClient {
  Future<void> ping();
  Future<List<NetEntry>> list(String id); // '' = root
  Future<List<NetEntry>> search(String q) async => const [];

  static NetClient of(NetServer s) =>
      s.kind == NetKind.subsonic ? SubsonicClient(s) : WebDavClient(s);
}

String _songId(String serverId, String raw) =>
    'net:${md5.convert(utf8.encode('$serverId|$raw')).toString().substring(0, 16)}';

class SubsonicClient extends NetClient {
  SubsonicClient(this.s);
  final NetServer s;

  Map<String, String> _auth() {
    final rnd = math.Random.secure();
    final salt = List.generate(8, (_) => rnd.nextInt(16).toRadixString(16)).join();
    final token = md5.convert(utf8.encode('${s.password}$salt')).toString();
    return {
      'u': s.user,
      't': token,
      's': salt,
      'v': '1.16.1',
      'c': 'zenmusic',
      'f': 'json',
    };
  }

  Uri _uri(String method, [Map<String, String> extra = const {}]) => Uri.parse(
          '${s.url}/rest/$method.view')
      .replace(queryParameters: {..._auth(), ...extra});

  Future<Map<String, dynamic>> _get(String method,
      [Map<String, String> extra = const {}]) async {
    final r = await http.get(_uri(method, extra)).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final root = (await decodeJsonBg(r.body) as Map)['subsonic-response'] as Map;
    if (root['status'] != 'ok') {
      throw Exception((root['error'] as Map?)?['message'] ?? 'Request failed');
    }
    return Map<String, dynamic>.from(root);
  }

  @override
  Future<void> ping() => _get('ping');

  String _cover(Object? id) => id == null
      ? ''
      : _uri('getCoverArt', {'id': '$id', 'size': '600'}).toString();

  NetEntry _track(Map t) {
    final sid = t['id'].toString();
    final artist = (t['artist'] ?? '').toString();
    return NetEntry(
      title: (t['title'] ?? '').toString(),
      subtitle: artist,
      id: sid,
      isDir: false,
      song: {
        'videoId': _songId(s.id, sid),
        'title': (t['title'] ?? '').toString(),
        'artists': [
          {'name': artist.isEmpty ? 'Unknown artist' : artist}
        ],
        'album': {'name': (t['album'] ?? '').toString()},
        'thumbnails': [
          {'url': _cover(t['coverArt'])}
        ],
        'netUrl': _uri('stream', {'id': sid}).toString(),
        'duration': t['duration'] is num ? _fmt((t['duration'] as num).toInt()) : null,
      },
    );
  }

  static String _fmt(int sec) =>
      '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

  @override
  Future<List<NetEntry>> list(String id) async {
    if (id.isEmpty) {
      final r = await _get('getArtists');
      final out = <NetEntry>[];
      for (final idx in (r['artists']?['index'] as List? ?? const [])) {
        for (final a in (idx['artist'] as List? ?? const [])) {
          out.add(NetEntry(
              title: a['name'].toString(),
              id: 'ar:${a['id']}',
              subtitle: '${a['albumCount'] ?? ''} albums'));
        }
      }
      return out;
    }
    if (id.startsWith('ar:')) {
      final r = await _get('getArtist', {'id': id.substring(3)});
      return [
        for (final a in (r['artist']?['album'] as List? ?? const []))
          NetEntry(
              title: a['name'].toString(),
              id: 'al:${a['id']}',
              subtitle: (a['year'] ?? '').toString())
      ];
    }
    final r = await _get('getAlbum', {'id': id.substring(3)});
    return [
      for (final t in (r['album']?['song'] as List? ?? const [])) _track(t as Map)
    ];
  }

  @override
  Future<List<NetEntry>> search(String q) async {
    final r = await _get('search3', {'query': q, 'songCount': '40', 'albumCount': '10', 'artistCount': '10'});
    final res = r['searchResult3'] as Map? ?? const {};
    return [
      for (final a in (res['album'] as List? ?? const []))
        NetEntry(
            title: a['name'].toString(),
            id: 'al:${a['id']}',
            subtitle: (a['artist'] ?? '').toString()),
      for (final t in (res['song'] as List? ?? const [])) _track(t as Map),
    ];
  }
}

class WebDavClient extends NetClient {
  WebDavClient(this.s);
  final NetServer s;
  static const _audio = {
    'mp3', 'flac', 'm4a', 'aac', 'ogg', 'opus', 'wav', 'wma', 'alac', 'aiff'
  };

  Map<String, String> get _h =>
      s.user.isEmpty ? {} : {'Authorization': s.basicAuth};

  Future<http.Response> _propfind(String url) async {
    final req = http.Request('PROPFIND', Uri.parse(url))
      ..headers.addAll({..._h, 'Depth': '1', 'Content-Type': 'application/xml'})
      ..body = '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop>'
          '<d:resourcetype/><d:displayname/></d:prop></d:propfind>';
    final streamed = await req.send().timeout(const Duration(seconds: 20));
    return http.Response.fromStream(streamed);
  }

  @override
  Future<void> ping() async {
    final r = await _propfind('${s.url}/');
    if (r.statusCode != 207 && r.statusCode != 200) {
      throw Exception('HTTP ${r.statusCode}');
    }
  }

  @override
  Future<List<NetEntry>> list(String id) async {
    final base = Uri.parse(s.url);
    final url = id.isEmpty ? '${s.url}/' : id;
    final r = await _propfind(url);
    if (r.statusCode != 207 && r.statusCode != 200) {
      throw Exception('HTTP ${r.statusCode}');
    }
    final here = Uri.parse(url).path.replaceAll(RegExp(r'/+$'), '');
    final out = <NetEntry>[];
    final responses = RegExp(r'<(?:\w+:)?response[ >].*?</(?:\w+:)?response>',
            dotAll: true)
        .allMatches(r.body);
    for (final m in responses) {
      final block = m.group(0)!;
      final href = RegExp(r'<(?:\w+:)?href>(.*?)</(?:\w+:)?href>', dotAll: true)
          .firstMatch(block)
          ?.group(1)
          ?.trim();
      if (href == null) continue;
      final path = Uri.decodeFull(Uri.parse(href).path);
      final clean = path.replaceAll(RegExp(r'/+$'), '');
      if (Uri.decodeFull(here) == clean) continue; // the folder itself
      final isDir = RegExp(r'<(?:\w+:)?collection\s*/?>').hasMatch(block);
      final name = clean.split('/').last;
      final full = base.replace(path: Uri.encodeFull(path)).toString();
      if (isDir) {
        out.add(NetEntry(title: name, id: full, subtitle: ''));
      } else {
        final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
        if (!_audio.contains(ext)) continue;
        final title = name.substring(0, name.length - ext.length - 1);
        out.add(NetEntry(
          title: title,
          id: full,
          isDir: false,
          song: {
            'videoId': _songId(s.id, full),
            'title': title,
            'artists': [
              {'name': s.name}
            ],
            'album': {'name': Uri.decodeFull(here).split('/').last},
            'thumbnails': [
              {'url': ''}
            ],
            'netUrl': full,
            'netHeaders': _h,
          },
        ));
      }
    }
    out.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return out;
  }
}

// ───────────────────────────── UI ─────────────────────────────

class NetworkStoragePage extends StatefulWidget {
  const NetworkStoragePage({super.key});
  @override
  State<NetworkStoragePage> createState() => _NetworkStoragePageState();
}

class _NetworkStoragePageState extends State<NetworkStoragePage> {
  late List<NetServer> _servers = NetServers.load();

  Future<void> _persist() async {
    await NetServers.save(_servers);
    if (mounted) setState(() {});
  }

  Future<void> _add() async {
    final s = await showDialog<NetServer>(
        context: context, builder: (_) => const _ServerDialog());
    if (s != null) {
      _servers = [..._servers, s];
      await _persist();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Network storage')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add server'),
      ),
      body: _servers.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Add a Subsonic / OpenSubsonic server or a WebDAV share to play your own music over the network.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                for (final s in _servers)
                  Dismissible(
                    key: ValueKey(s.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red.withOpacity(.8),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) {
                      _servers = _servers.where((e) => e.id != s.id).toList();
                      _persist();
                    },
                    child: ListTile(
                      leading: Icon(s.kind == NetKind.subsonic
                          ? Icons.dns_outlined
                          : Icons.folder_shared_outlined),
                      title: Text(s.name),
                      subtitle: Text(s.url),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => NetBrowsePage(server: s))),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ServerDialog extends StatefulWidget {
  const _ServerDialog();
  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  NetKind _kind = NetKind.subsonic;
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _err;

  Future<void> _save() async {
    var url = _url.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isEmpty) return;
    if (!url.startsWith('http')) url = 'https://$url';
    final s = NetServer(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      kind: _kind,
      name: _name.text.trim().isEmpty ? Uri.parse(url).host : _name.text.trim(),
      url: url,
      user: _user.text.trim(),
      password: _pass.text,
    );
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await NetClient.of(s).ping();
      if (mounted) Navigator.pop(context, s);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = 'Could not connect: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add server'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<NetKind>(
            segments: const [
              ButtonSegment(value: NetKind.subsonic, label: Text('Subsonic')),
              ButtonSegment(value: NetKind.webdav, label: Text('WebDAV')),
            ],
            selected: {_kind},
            onSelectionChanged: (v) => setState(() => _kind = v.first),
          ),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name (optional)')),
          TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Server URL')),
          TextField(controller: _user, decoration: const InputDecoration(labelText: 'Username')),
          TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password')),
          if (_err != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Connect')),
      ],
    );
  }
}

class NetBrowsePage extends StatefulWidget {
  const NetBrowsePage(
      {super.key, required this.server, this.folder = '', this.title, this.query});
  final NetServer server;
  final String folder;
  final String? title;
  final String? query;
  @override
  State<NetBrowsePage> createState() => _NetBrowsePageState();
}

class _NetBrowsePageState extends State<NetBrowsePage> {
  late final NetClient _c = NetClient.of(widget.server);
  late Future<List<NetEntry>> _f = _load();

  Future<List<NetEntry>> _load() => widget.query != null
      ? _c.search(widget.query!)
      : _c.list(widget.folder);

  void _open(NetEntry e) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NetBrowsePage(
          server: widget.server, folder: e.id, title: e.title)));

  Future<void> _search() async {
    final ctl = TextEditingController();
    final q = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Search'),
        content: TextField(controller: ctl, autofocus: true, onSubmitted: (v) => Navigator.pop(context, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, ctl.text), child: const Text('Search')),
        ],
      ),
    );
    if (q == null || q.trim().isEmpty || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => NetBrowsePage(
            server: widget.server, title: 'Search: ${q.trim()}', query: q.trim())));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? widget.server.name),
        actions: [
          if (widget.server.kind == NetKind.subsonic && widget.query == null)
            IconButton(icon: const Icon(Icons.search), onPressed: _search),
        ],
      ),
      body: FutureBuilder<List<NetEntry>>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const ListSkeleton();
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${snap.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: () => setState(() => _f = _load()),
                      child: const Text('Retry')),
                ]),
              ),
            );
          }
          final items = snap.data!;
          if (items.isEmpty) return const Center(child: Text('Nothing here'));
          final tracks = items.where((e) => !e.isDir).toList();
          return ListView(
            children: [
              if (tracks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(children: [
                    FilledButton.icon(
                      onPressed: () => GetIt.I<MediaPlayer>().playAll(
                          [for (final t in tracks) t.song!]),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play all'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => GetIt.I<MediaPlayer>().playAll(
                          ([for (final t in tracks) t.song!]..shuffle())),
                      icon: const Icon(Icons.shuffle),
                      label: const Text('Shuffle'),
                    ),
                  ]),
                ),
              for (final e in items)
                ListTile(
                  leading: Icon(e.isDir ? Icons.folder_outlined : Icons.music_note),
                  title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: e.subtitle.isEmpty ? null : Text(e.subtitle, maxLines: 1),
                  onTap: e.isDir
                      ? () => _open(e)
                      : () => GetIt.I<MediaPlayer>().playAll(
                          [for (final t in tracks) t.song!],
                          index: tracks.indexOf(e)),
                ),
            ],
          );
        },
      ),
    );
  }
}
