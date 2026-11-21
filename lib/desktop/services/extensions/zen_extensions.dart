// ZenMusic · vorlon-dev
//
// Community extensions: small JavaScript plugins that add lyric sources and
// track metadata. Repositories follow Mornye's model (GPL-3.0,
// https://github.com/mornyeapp/Mornye): anyone hosts a `registry.json` on
// GitHub, the user adds the repo URL, then installs what they want.
//
// Two kinds of package are understood, both written from scratch here:
//
//  1. ZenMusic extensions (`format: zen`): a single script, async API.
//       async function getLyrics(track)   -> { wordLrc?, lrc?, plain? } | null
//       async function getMetadata(track) -> { isrc?, album? } | null
//       track = { title, artist, album, durationMs, isrc, videoId }
//       zen.fetch(url, {method, headers, body}) -> { status, ok, text(), json() }
//
//  2. Mornye packages (`.mornye-ext` / `.sflx` zip with manifest.json and
//     index.js). Only `lyrics_provider` and `metadata_provider` ones run;
//     download providers are refused. They call a SYNCHRONOUS host API
//     (fetch, http.*, storage, utils.md5 ...) which cannot be served from
//     async Dart, so each run is replayed: when the script reaches a host
//     call the run stops, Dart performs the call, and the script is run again
//     with the recorded answers until it finishes. Scripts must therefore be
//     deterministic and must not swallow exceptions around host calls.
//
// Safety model: bare QuickJS (no DOM, timers, files); the only way out is the
// network, https only, restricted to the hosts the extension declared and the
// user approved, never private/loopback addresses, no redirects, capped
// response size / request count / time. A registry sha256 must match.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../lyrics_providers/lyric_doc.dart';

final RegExp _idRe = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');

String _str(Map m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return '';
}

/// One entry of a repository's registry.json (ZenMusic or Mornye layout).
class RegistryEntry {
  RegistryEntry({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.url,
    required this.hosts,
    required this.kinds,
    required this.format,
    this.sha256,
    required this.repo,
  });

  final String id;
  final String name;
  final String version;
  final String description;
  final Uri url;

  /// Declared hosts (ZenMusic format). Mornye packages declare them inside
  /// the zip, so this is empty until the package has been opened.
  final List<String> hosts;
  final List<String> kinds; // 'lyrics', 'metadata' (empty = find out later)
  final String format; // 'zen' | 'mornye'
  final String? sha256;
  final String repo;

  static RegistryEntry? parse(Map m, Uri registryUri, String repo) {
    final id = _str(m, ['id', 'name']).toLowerCase();
    if (!_idRe.hasMatch(id)) return null;
    final raw = _str(m, ['download_url', 'downloadUrl', 'url']);
    if (raw.isEmpty) return null;
    final url = registryUri.resolve(raw);
    if (url.scheme != 'https') return null;
    final path = url.path.toLowerCase();
    final mornye = path.endsWith('.mornye-ext') ||
        path.endsWith('.sflx') ||
        path.endsWith('.spotiflac-ext') ||
        path.endsWith('.zip') ||
        m['runtime'] != null;
    final kinds = <String>[];
    final t = m['type'];
    for (final x in (t is List ? t : [if (t != null) t])) {
      final k = '$x'.toLowerCase().replaceAll('_provider', '');
      if ((k == 'lyrics' || k == 'metadata') && !kinds.contains(k)) kinds.add(k);
    }
    if (!mornye && kinds.isEmpty) kinds.add('lyrics');
    final sha = _str(m, ['sha256', 'checksum_sha256', 'checksumSha256'])
        .toLowerCase()
        .replaceFirst('sha256:', '');
    return RegistryEntry(
      id: id,
      name: _str(m, ['display_name', 'displayName', 'name']).isEmpty
          ? id
          : _str(m, ['display_name', 'displayName', 'name']),
      version: _str(m, ['version']).isEmpty ? '0' : _str(m, ['version']),
      description: _str(m, ['description']),
      url: url,
      hosts: normalizeHosts(m['hosts']),
      kinds: kinds,
      format: mornye ? 'mornye' : 'zen',
      sha256: RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ? sha : null,
      repo: repo,
    );
  }
}

/// Lower-cased hosts; a leading `*.` is dropped (subdomains always match).
List<String> normalizeHosts(Object? raw) {
  final out = <String>[];
  if (raw is List) {
    for (final h in raw) {
      var s = '$h'.trim().toLowerCase();
      if (s.startsWith('*.')) s = s.substring(2);
      if (s.isEmpty || s.contains('*') || s.contains('/') || s.contains(':')) {
        continue;
      }
      if (!out.contains(s)) out.add(s);
    }
  }
  return out;
}

/// A downloaded, verified package waiting for the user's approval.
class PreparedInstall {
  PreparedInstall({
    required this.entry,
    required this.source,
    required this.hosts,
    required this.kinds,
    required this.verified,
  });
  final RegistryEntry entry;
  final String source; // the script text (index.js for Mornye packages)
  final List<String> hosts;
  final List<String> kinds;
  final bool verified;
}

/// An installed extension (script on disk, metadata in Hive 'SETTINGS').
class InstalledExtension {
  InstalledExtension({
    required this.id,
    required this.name,
    required this.version,
    required this.hosts,
    required this.kinds,
    required this.format,
    required this.repo,
    required this.verified,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String version;
  final List<String> hosts;
  final List<String> kinds;
  final String format;
  final String repo;
  final bool verified;
  bool enabled;

  bool get isMornye => format == 'mornye';

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'version': version,
        'hosts': hosts,
        'kinds': kinds,
        'format': format,
        'repo': repo,
        'verified': verified,
        'enabled': enabled,
      };

  static InstalledExtension? fromMap(Object? o) {
    if (o is! Map) return null;
    final id = '${o['id'] ?? ''}';
    if (!_idRe.hasMatch(id)) return null;
    final kinds = [for (final k in (o['kinds'] as List? ?? const [])) '$k'];
    return InstalledExtension(
      id: id,
      name: '${o['name'] ?? id}',
      version: '${o['version'] ?? '0'}',
      hosts: [for (final h in (o['hosts'] as List? ?? const [])) '$h'],
      kinds: kinds.isEmpty ? ['lyrics'] : kinds,
      format: '${o['format'] ?? 'zen'}',
      repo: '${o['repo'] ?? ''}',
      verified: o['verified'] == true,
      enabled: o['enabled'] != false,
    );
  }
}

class ZenExtensions {
  ZenExtensions._();

  static const String _reposKey = 'ZEN_EXT_REPOS';
  static const String _installedKey = 'ZEN_EXT_INSTALLED';
  static const int _maxScriptBytes = 512 * 1024;
  static const int _maxPackageBytes = 8 * 1024 * 1024;
  static const int _maxResponseBytes = 2 * 1024 * 1024;
  static const int _maxFetchesPerCall = 8;
  static const Duration _callTimeout = Duration(seconds: 20);

  /// Bumped whenever repos or installed extensions change.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static Box? get _box {
    try {
      return Hive.isBoxOpen('SETTINGS') ? Hive.box('SETTINGS') : null;
    } catch (_) {
      return null;
    }
  }

  // ───────────────────────── repositories ─────────────────────────

  static List<String> repos() {
    final v = _box?.get(_reposKey);
    return v is List ? [for (final e in v) '$e'] : <String>[];
  }

  /// A GitHub repo URL becomes its raw registry.json; any other https URL
  /// is taken as the registry file itself.
  static Uri? registryUriFor(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'https://$s';
    final u = Uri.tryParse(s);
    if (u == null || u.scheme != 'https' || u.host.isEmpty) return null;
    if (u.host == 'github.com') {
      final seg = u.pathSegments.where((e) => e.isNotEmpty).toList();
      if (seg.length < 2) return null;
      final repo = seg[1].replaceAll(RegExp(r'\.git$'), '');
      return Uri.https(
          'raw.githubusercontent.com', '/${seg[0]}/$repo/HEAD/registry.json');
    }
    return u;
  }

  static Future<String?> addRepo(String input) async {
    final uri = registryUriFor(input);
    if (uri == null) return 'Enter a GitHub repository URL';
    try {
      await fetchRegistry(uri.toString());
    } catch (e) {
      return 'Could not read registry.json ($e)';
    }
    final list = repos();
    if (!list.contains(uri.toString())) list.add(uri.toString());
    await _box?.put(_reposKey, list);
    changes.value++;
    return null;
  }

  static Future<void> removeRepo(String registryUrl) async {
    await _box?.put(_reposKey, repos()..remove(registryUrl));
    changes.value++;
  }

  static Future<List<RegistryEntry>> fetchRegistry(String registryUrl) async {
    final uri = Uri.parse(registryUrl);
    final r = await http.get(uri).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
    if (r.bodyBytes.length > 1024 * 1024) throw 'registry too large';
    final root = jsonDecode(utf8.decode(r.bodyBytes));
    final list = root is Map ? root['extensions'] : root;
    if (list is! List) throw 'no "extensions" list';
    return [
      for (final e in list)
        if (e is Map)
          if (RegistryEntry.parse(e, uri, registryUrl) case final x?) x,
    ];
  }

  // ───────────────────────── installed ─────────────────────────

  static List<InstalledExtension> installed() {
    final v = _box?.get(_installedKey);
    if (v is! List) return <InstalledExtension>[];
    return [
      for (final e in v)
        if (InstalledExtension.fromMap(e) case final x?) x,
    ];
  }

  static Future<void> _saveInstalled(List<InstalledExtension> l) async {
    await _box?.put(_installedKey, [for (final e in l) e.toMap()]);
    changes.value++;
  }

  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/extensions');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<File> _file(String id) async =>
      File('${(await _dir()).path}/$id.js');

  /// Step 1 of an install: download and verify. Returns the package to show
  /// the user, or an error message. Nothing is stored yet.
  static Future<(PreparedInstall?, String?)> prepare(RegistryEntry e) async {
    try {
      final r = await http.get(e.url).timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) return (null, 'Download failed (HTTP ${r.statusCode})');
      final bytes = r.bodyBytes;
      if (bytes.length > (e.format == 'mornye' ? _maxPackageBytes : _maxScriptBytes)) {
        return (null, 'Package too large');
      }
      if (e.sha256 != null && sha256.convert(bytes).toString() != e.sha256) {
        return (null, 'Checksum mismatch, install blocked');
      }
      if (e.format == 'zen') {
        if (e.hosts.isEmpty) return (null, 'Extension declares no network hosts');
        return (
          PreparedInstall(
            entry: e,
            source: utf8.decode(bytes, allowMalformed: true),
            hosts: e.hosts,
            kinds: e.kinds,
            verified: e.sha256 != null,
          ),
          null
        );
      }
      return _openMornye(e, bytes);
    } catch (err) {
      return (null, 'Install failed ($err)');
    }
  }

  static (PreparedInstall?, String?) _openMornye(RegistryEntry e, List<int> bytes) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return (null, 'Not a valid extension package');
    }
    String? manifestText, script;
    for (final f in zip.files) {
      if (!f.isFile) continue;
      final n = f.name.replaceAll('\\', '/');
      if (n == 'manifest.json' || n == 'index.js') {
        final raw = f.content as List<int>;
        if (raw.length > _maxScriptBytes) return (null, 'Script too large');
        final txt = utf8.decode(raw, allowMalformed: true);
        n == 'index.js' ? script = txt : manifestText = txt;
      }
    }
    if (manifestText == null) return (null, 'Package has no manifest.json');
    if (script == null) return (null, 'Package has no index.js');
    final Object? mf;
    try {
      mf = jsonDecode(manifestText);
    } catch (_) {
      return (null, 'manifest.json is not valid JSON');
    }
    if (mf is! Map) return (null, 'manifest.json is not an object');
    final types = [for (final t in (mf['type'] as List? ?? const [])) '$t'];
    final kinds = <String>[
      if (types.contains('lyrics_provider')) 'lyrics',
      if (types.contains('metadata_provider')) 'metadata',
    ];
    if (kinds.isEmpty) {
      return (
        null,
        types.contains('download_provider')
            ? 'Download extensions are not supported in ZenMusic'
            : 'Unsupported extension type'
      );
    }
    final perm = mf['permissions'];
    final hosts = normalizeHosts(perm is Map ? perm['network'] : null);
    if (hosts.isEmpty) return (null, 'Extension declares no network hosts');
    return (
      PreparedInstall(
        entry: e,
        source: script,
        hosts: hosts,
        kinds: kinds,
        verified: e.sha256 != null,
      ),
      null
    );
  }

  /// Step 2: the user approved [p]'s hosts. Stores script and metadata.
  static Future<String?> commit(PreparedInstall p) async {
    try {
      await (await _file(p.entry.id)).writeAsString(p.source, flush: true);
      final list = installed()..removeWhere((x) => x.id == p.entry.id);
      list.add(InstalledExtension(
        id: p.entry.id,
        name: p.entry.name,
        version: p.entry.version,
        hosts: p.hosts,
        kinds: p.kinds,
        format: p.entry.format,
        repo: p.entry.repo,
        verified: p.verified,
      ));
      await _saveInstalled(list);
      return null;
    } catch (err) {
      return 'Install failed ($err)';
    }
  }

  static Future<void> uninstall(String id) async {
    try {
      final f = await _file(id);
      if (await f.exists()) await f.delete();
      await _box?.delete('ZEN_EXT_STORE_$id');
    } catch (_) {}
    await _saveInstalled(installed()..removeWhere((x) => x.id == id));
  }

  static Future<void> setEnabled(String id, bool on) async {
    final l = installed();
    for (final e in l) {
      if (e.id == id) e.enabled = on;
    }
    await _saveInstalled(l);
  }

  /// Installed order is the priority order.
  static Future<void> reorder(int from, int to) async {
    final l = installed();
    if (to > from) to -= 1;
    l.insert(to, l.removeAt(from));
    await _saveInstalled(l);
  }

  // ───────────────────────── lyrics bridge ─────────────────────────

  /// One future per enabled lyrics extension, in priority order, for
  /// `LyricsRepository` to read alongside the built-in sources.
  static List<(String, Future<LyricDoc?>)> lyricFutures(LyricQuery q) => [
        for (final e in installed())
          if (e.enabled && e.kinds.contains('lyrics')) (e.name, _lyrics(e, q)),
      ];

  static Map<String, dynamic> _track(LyricQuery q) => {
        'title': q.title,
        'artist': q.artist,
        'album': q.album,
        'durationMs': q.durationMs,
        'isrc': q.isrc,
        'videoId': q.videoId,
      };

  static Future<LyricDoc?> _lyrics(InstalledExtension e, LyricQuery q) async {
    try {
      final f = await _file(e.id);
      if (!await f.exists()) return null;
      final src = await f.readAsString();
      if (e.isMornye) {
        final out = await _runMornye(e, src, 'fetchLyrics',
            [q.title, q.artist, q.album ?? '', q.durationSec ?? 0]);
        return _mornyeLyrics(out);
      }
      final out = await _runZen(e, src, 'getLyrics', _track(q));
      if (out is! Map) return null;
      String s(String k) => '${out[k] ?? ''}';
      if (s('wordLrc').trim().isNotEmpty) {
        return LyricDoc(payload: s('wordLrc'), wordSynced: true);
      }
      if (s('lrc').trim().isNotEmpty) {
        return LyricDoc(payload: s('lrc'), wordSynced: false, lineSynced: true);
      }
      if (s('plain').trim().isNotEmpty) {
        return LyricDoc(payload: s('plain'), wordSynced: false, isPlain: true);
      }
      return null;
    } catch (err) {
      debugPrint('[ext:${e.id}] lyrics failed: $err');
      return null;
    }
  }

  /// Mornye lyrics: { syncType, lines:[{startTimeMs, words}], plainLyrics }.
  static LyricDoc? _mornyeLyrics(dynamic out) {
    if (out is! Map || out['instrumental'] == true) return null;
    final lines = out['lines'];
    if (lines is List && lines.isNotEmpty && '${out['syncType']}' != 'UNSYNCED') {
      final b = StringBuffer();
      for (final l in lines) {
        if (l is! Map) continue;
        final ms = (l['startTimeMs'] is num)
            ? (l['startTimeMs'] as num).toInt()
            : int.tryParse('${l['startTimeMs']}') ?? 0;
        final mm = (ms ~/ 60000).toString().padLeft(2, '0');
        final ss = ((ms % 60000) / 1000).toStringAsFixed(2).padLeft(5, '0');
        b.writeln('[$mm:$ss]${l['words'] ?? ''}');
      }
      final t = b.toString();
      if (t.trim().isNotEmpty) {
        return LyricDoc(payload: t, wordSynced: false, lineSynced: true);
      }
    }
    final plain = '${out['plainLyrics'] ?? ''}'.trim();
    return plain.isEmpty
        ? null
        : LyricDoc(payload: plain, wordSynced: false, isPlain: true);
  }

  // ───────────────────────── metadata bridge ─────────────────────────

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Fills a missing ISRC / album from enabled metadata extensions so the
  /// lyric sources that match by recording get a better query. Never throws
  /// and never takes longer than a few seconds.
  static Future<LyricQuery> enrichQuery(LyricQuery q) async {
    if (q.isrc != null && q.album != null) return q;
    final exts = [
      for (final e in installed())
        if (e.enabled && e.kinds.contains('metadata')) e,
    ];
    if (exts.isEmpty) return q;
    String? isrc = q.isrc, album = q.album;
    try {
      await Future.any<void>([
        () async {
          for (final e in exts) {
            if (isrc != null && album != null) break;
            final f = await _file(e.id);
            if (!await f.exists()) continue;
            final src = await f.readAsString();
            Map? hit;
            if (e.isMornye) {
              final out = await _runMornye(
                  e, src, 'searchTracks', ['${q.title} ${q.artist}', 5]);
              final list = out is Map ? out['tracks'] : out;
              if (list is List) {
                for (final t in list) {
                  if (t is! Map) continue;
                  if (_norm('${t['name'] ?? ''}') != _norm(q.title)) continue;
                  final d = t['duration_ms'];
                  if (d is num && q.durationMs != null &&
                      (d.toInt() - q.durationMs!).abs() > 6000) {
                    continue;
                  }
                  hit = {'isrc': t['isrc'], 'album': t['album_name']};
                  break;
                }
              }
            } else {
              final out = await _runZen(e, src, 'getMetadata', _track(q));
              if (out is Map) hit = out;
            }
            if (hit == null) continue;
            final i = '${hit['isrc'] ?? ''}'.trim();
            final a = '${hit['album'] ?? ''}'.trim();
            if (isrc == null && i.isNotEmpty) isrc = i;
            if (album == null && a.isNotEmpty) album = a;
          }
        }(),
        Future<void>.delayed(const Duration(seconds: 8)),
      ]);
    } catch (err) {
      debugPrint('[ext] metadata failed: $err');
    }
    return LyricQuery(
      title: q.title,
      artist: q.artist,
      album: album,
      durationMs: q.durationMs,
      videoId: q.videoId,
      isrc: isrc,
    );
  }

  // ───────────────────────── ZenMusic runtime (async) ─────────────────────────

  static const String _zenPrelude = r'''
globalThis.__zen = { n: 0, p: {}, done: false, out: null, err: null };
globalThis.zen = {
  fetch: function (url, opts) {
    return new Promise(function (res, rej) {
      var id = ++__zen.n;
      __zen.p[id] = { res: res, rej: rej };
      sendMessage('zen.fetch', JSON.stringify({ id: id, url: String(url), opts: opts || {} }));
    }).then(function (r) {
      return {
        status: r.status,
        ok: r.status >= 200 && r.status < 300,
        text: function () { return Promise.resolve(r.body); },
        json: function () { return Promise.resolve(JSON.parse(r.body)); }
      };
    });
  },
  log: function () {
    sendMessage('zen.log', JSON.stringify(Array.prototype.map.call(arguments, String)));
  }
};
globalThis.console = { log: zen.log, warn: zen.log, error: zen.log };
globalThis.__zenSettle = function (id, ok, v) {
  var p = __zen.p[id]; delete __zen.p[id];
  if (!p) return;
  if (ok) p.res(v); else p.rej(new Error(String(v)));
};
''';

  static Future<dynamic> _runZen(InstalledExtension ext, String source,
      String fn, Map<String, dynamic> track) async {
    final rt = getJavascriptRuntime(xhr: false);
    var fetches = 0;
    var disposed = false;
    final client = http.Client();

    void settle(int id, bool ok, Object v) {
      if (disposed) return;
      rt.evaluate('__zenSettle($id,$ok,${jsonEncode(v)})');
      rt.executePendingJob();
    }

    Map<String, dynamic> decode(dynamic a) =>
        Map<String, dynamic>.from(a is String ? jsonDecode(a) as Map : a as Map);

    rt.onMessage('zen.log', (dynamic a) {
      debugPrint('[ext:${ext.id}] ${a is String ? a : jsonEncode(a)}');
    });
    rt.onMessage('zen.fetch', (dynamic a) async {
      final m = decode(a);
      final id = m['id'] as int;
      try {
        if (++fetches > _maxFetchesPerCall) throw 'too many requests';
        final opts = Map<String, dynamic>.from((m['opts'] as Map?) ?? {});
        final headers = <String, String>{};
        final h = opts['headers'];
        if (h is Map) h.forEach((k, v) => headers['$k'] = '$v');
        final res = await _httpCall(
          ext,
          client,
          '${m['url']}',
          '${opts['method'] ?? 'GET'}'.toUpperCase(),
          headers,
          opts['body'] == null ? '' : '${opts['body']}',
        );
        settle(id, true, {'status': res['status'], 'body': res['body']});
      } catch (err) {
        settle(id, false, '$err');
      }
    });

    try {
      final pre = rt.evaluate(_zenPrelude);
      if (pre.isError) throw 'prelude: ${pre.stringResult}';
      final load = rt.evaluate(source);
      if (load.isError) throw 'load: ${load.stringResult}';
      final start = rt.evaluate('''
(async function () {
  try {
    if (typeof $fn !== 'function') throw new Error('$fn() missing');
    var r = await $fn(${jsonEncode(track)});
    __zen.out = JSON.stringify(r == null ? null : r);
  } catch (e) { __zen.err = String(e && e.message || e); }
  __zen.done = true;
})();
''');
      if (start.isError) throw 'start: ${start.stringResult}';

      final deadline = DateTime.now().add(_callTimeout);
      while (DateTime.now().isBefore(deadline)) {
        rt.executePendingJob();
        if (rt.evaluate('__zen.done ? "1" : "0"').stringResult == '1') break;
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      if (rt.evaluate('__zen.done ? "1" : "0"').stringResult != '1') {
        throw 'timed out';
      }
      final err = rt.evaluate('__zen.err === null ? "" : __zen.err').stringResult;
      if (err.isNotEmpty) throw err;
      final out = rt.evaluate('__zen.out === null ? "null" : __zen.out').stringResult;
      return jsonDecode(out);
    } finally {
      disposed = true;
      client.close();
      try {
        rt.dispose();
      } catch (_) {}
    }
  }

  // ───────────────────────── Mornye runtime (replayed) ─────────────────────────

  static const String _mornyePrelude = r'''
globalThis.__m = { cache: __CACHE__, i: 0, pending: null, store: __STORE__, done: false, res: null };
(function () {
  function call(req) {
    var i = __m.i++;
    if (i < __m.cache.length) return __m.cache[i];
    __m.pending = req;
    throw { __zenNeed: req };
  }
  function hdrs(h) {
    var o = {};
    if (h && typeof h === 'object') for (var k in h) o[k] = String(h[k]);
    return o;
  }
  function bodyOf(b) {
    if (b === undefined || b === null) return '';
    if (typeof b === 'string') return b;
    try { return JSON.stringify(b); } catch (_) { return String(b); }
  }
  function wrap(r, isFetch) {
    if (r.error !== undefined) {
      return isFetch
        ? { ok: false, status: 0, statusText: 'Network Error', error: r.error,
            text: function () { return ''; }, json: function () { return undefined; } }
        : { error: r.error };
    }
    return {
      ok: r.status >= 200 && r.status < 300, status: r.status, statusText: '',
      body: r.body, headers: r.headers || {},
      text: function () { return r.body; },
      json: function () { try { return JSON.parse(r.body); } catch (_) { return undefined; } }
    };
  }
  function net(method, url, headers, body, isFetch) {
    return wrap(call({ k: 'net', url: String(url), method: method, headers: hdrs(headers), body: bodyOf(body) }), isFetch);
  }
  globalThis.fetch = function (url, o) {
    o = o || {};
    return net(String(o.method || 'GET').toUpperCase(), url, o.headers, o.body, true);
  };
  globalThis.http = {
    get: function (u, h) { return net('GET', u, h, '', false); },
    delete: function (u, h) { return net('DELETE', u, h, '', false); },
    post: function (u, b, h) { return net('POST', u, h, b, false); },
    put: function (u, b, h) { return net('PUT', u, h, b, false); },
    patch: function (u, b, h) { return net('PATCH', u, h, b, false); },
    request: function (u, o) { o = o || {}; return net(String(o.method || 'GET').toUpperCase(), u, o.headers, o.body, false); },
    clearCookies: function () {}
  };
  function store(prefix) {
    return {
      get: function (k, fb) { var v = __m.store[prefix + String(k)]; return v === undefined ? fb : JSON.parse(v); },
      set: function (k, v) { __m.store[prefix + String(k)] = JSON.stringify(v); return true; },
      store: function (k, v) { __m.store[prefix + String(k)] = JSON.stringify(v); return { success: true }; },
      remove: function (k) { delete __m.store[prefix + String(k)]; return true; }
    };
  }
  var st = store('s:'), cr = store('c:');
  globalThis.storage = { get: st.get, set: st.set, remove: st.remove };
  globalThis.credentials = { get: cr.get, store: cr.store, remove: cr.remove };
  var nop = function () {};
  globalThis.log = { debug: nop, info: nop, warn: nop, error: nop };
  globalThis.console = { log: nop, info: nop, warn: nop, error: nop, debug: nop };
  var B = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  globalThis.btoa = function (s) {
    s = String(s); var o = '';
    for (var i = 0; i < s.length; i += 3) {
      var a = s.charCodeAt(i), b = s.charCodeAt(i + 1), c = s.charCodeAt(i + 2);
      o += B[a >> 2] + B[((a & 3) << 4) | ((b || 0) >> 4)] +
        (i + 1 < s.length ? B[((b & 15) << 2) | ((c || 0) >> 6)] : '=') +
        (i + 2 < s.length ? B[c & 63] : '=');
    }
    return o;
  };
  globalThis.atob = function (s) {
    s = String(s).replace(/=+$/, ''); var o = '', bits = 0, n = 0;
    for (var i = 0; i < s.length; i++) {
      var v = B.indexOf(s[i]); if (v < 0) continue;
      bits = (bits << 6) | v; n += 6;
      if (n >= 8) { n -= 8; o += String.fromCharCode((bits >> n) & 255); }
    }
    return o;
  };
  function utf8(s) { return unescape(encodeURIComponent(String(s))); }
  function calc(fn) {
    return function () { return call({ k: 'calc', fn: fn, a: Array.prototype.map.call(arguments, String) }).v; };
  }
  globalThis.utils = {
    isDownloadCancelled: function () { return false; },
    isRequestCancelled: function () { return false; },
    randomUserAgent: function () { return 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36'; },
    appVersion: function () { return '1.0'; },
    appUserAgent: function () { return 'ZenMusic/1.0'; },
    getResolutionRemainingMs: function () { return 20000; },
    base64Encode: function (v) { return btoa(utf8(v)); },
    base64Decode: function (v) { try { return decodeURIComponent(escape(atob(v))); } catch (_) { return atob(v); } },
    md5: calc('md5'), sha256: calc('sha256'),
    hmacSHA256: calc('hmacSHA256'), hmacSHA256Base64: calc('hmacSHA256Base64'),
    parseJSON: function (v) { try { return JSON.parse(String(v)); } catch (_) { return undefined; } },
    stringifyJSON: function (v) { try { return JSON.stringify(v); } catch (_) { return ''; } },
    sleep: function () { return true; }
  };
  globalThis.URLSearchParams = function (init) {
    var list = [], self = this;
    if (typeof init === 'string') {
      init.replace(/^\?/, '').split('&').forEach(function (p) {
        if (!p) return; var kv = p.split('=');
        list.push([decodeURIComponent(kv[0].replace(/\+/g, ' ')), decodeURIComponent((kv[1] || '').replace(/\+/g, ' '))]);
      });
    } else if (init && typeof init === 'object') {
      for (var k in init) list.push([k, String(init[k])]);
    }
    self.append = function (k, v) { list.push([String(k), String(v)]); };
    self.set = function (k, v) { self['delete'](k); self.append(k, v); };
    self['delete'] = function (k) { list = list.filter(function (e) { return e[0] !== String(k); }); };
    self.get = function (k) { for (var i = 0; i < list.length; i++) if (list[i][0] === String(k)) return list[i][1]; return null; };
    self.has = function (k) { return self.get(k) !== null; };
    self.toString = function () {
      return list.map(function (e) { return encodeURIComponent(e[0]) + '=' + encodeURIComponent(e[1]); }).join('&');
    };
  };
  globalThis.registerExtension = function (v) { if (arguments.length) globalThis.extension = v; };
})();
''';

  static Future<dynamic> _runMornye(InstalledExtension ext, String source,
      String method, List<dynamic> args) async {
    final initial = _loadStore(ext.id);
    final cache = <Map<String, dynamic>>[];
    final client = http.Client();
    var nets = 0;
    try {
      for (var round = 0; round < _maxFetchesPerCall + 24; round++) {
        final r = await _mornynePass(source, method, args, cache, initial);
        final need = r['need'];
        if (need is! Map) {
          if (r['err'] != null) throw '${r['err']}';
          final st = r['store'];
          if (st is Map) await _saveStore(ext.id, st);
          return r['ok'];
        }
        final req = Map<String, dynamic>.from(need);
        if (req['k'] == 'net' && ++nets > _maxFetchesPerCall) {
          throw 'too many requests';
        }
        cache.add(await _perform(ext, client, req));
      }
      throw 'too many host calls';
    } finally {
      client.close();
    }
  }

  static Map<String, String> _loadStore(String id) {
    final v = _box?.get('ZEN_EXT_STORE_$id');
    return v is Map
        ? {for (final e in v.entries) '${e.key}': '${e.value}'}
        : <String, String>{};
  }

  static Future<void> _saveStore(String id, Map st) async {
    // Cap what an extension may keep on the device.
    var size = 0;
    final out = <String, String>{};
    st.forEach((k, v) {
      size += '$k'.length + '$v'.length;
      if (size <= 256 * 1024) out['$k'] = '$v';
    });
    await _box?.put('ZEN_EXT_STORE_$id', out);
  }

  /// One run of the script against the recorded host answers in [cache].
  static Future<Map<String, dynamic>> _mornynePass(
      String source,
      String method,
      List<dynamic> args,
      List<Map<String, dynamic>> cache,
      Map<String, String> store) async {
    final rt = getJavascriptRuntime(xhr: false);
    try {
      final pre = rt.evaluate(_mornynePrelude
          // STORE first: its placeholder comes after CACHE's, so text inside
          // either payload can never be mistaken for the other placeholder.
          .replaceFirst('__STORE__', jsonEncode(store))
          .replaceFirst('__CACHE__', jsonEncode(cache)));
      if (pre.isError) throw 'prelude: ${pre.stringResult}';
      final load = rt.evaluate(source);
      if (load.isError) throw 'load: ${load.stringResult}';
      final m = jsonEncode(method);
      final start = rt.evaluate('''
(function () {
  function fin(res) {
    if (__m.pending) res = { need: __m.pending };
    res.store = __m.store;
    __m.res = JSON.stringify(res);
    __m.done = true;
  }
  Promise.resolve().then(function () {
    var ex = globalThis.extension;
    if (!ex) throw new Error('registerExtension() was not called');
    if (typeof ex.initialize === 'function') ex.initialize({});
    if (typeof ex[$m] !== 'function') throw new Error($m + ' is not implemented');
    return ex[$m].apply(ex, ${jsonEncode(args)});
  }).then(
    function (v) { fin({ ok: v === undefined ? null : v }); },
    function (e) { fin(e && e.__zenNeed ? { need: e.__zenNeed } : { err: String(e && e.message || e) }); }
  );
})();
''');
      if (start.isError) throw 'start: ${start.stringResult}';
      for (var i = 0; i < 400; i++) {
        rt.executePendingJob();
        if (rt.evaluate('__m.done ? "1" : "0"').stringResult == '1') break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      if (rt.evaluate('__m.done ? "1" : "0"').stringResult != '1') {
        throw 'timed out';
      }
      return Map<String, dynamic>.from(
          jsonDecode(rt.evaluate('__m.res').stringResult) as Map);
    } finally {
      try {
        rt.dispose();
      } catch (_) {}
    }
  }

  /// Answers one recorded host call. Errors become `{error}` answers, as in
  /// Mornye, so the script decides what to do.
  static Future<Map<String, dynamic>> _perform(
      InstalledExtension ext, http.Client client, Map<String, dynamic> req) async {
    try {
      if (req['k'] == 'calc') {
        final a = [for (final x in (req['a'] as List? ?? const [])) '$x'];
        switch ('${req['fn']}') {
          case 'md5':
            return {'v': md5.convert(utf8.encode(a.isEmpty ? '' : a[0])).toString()};
          case 'sha256':
            return {'v': sha256.convert(utf8.encode(a.isEmpty ? '' : a[0])).toString()};
          case 'hmacSHA256':
            return {
              'v': Hmac(sha256, utf8.encode(a.length > 1 ? a[1] : ''))
                  .convert(utf8.encode(a.isEmpty ? '' : a[0]))
                  .toString()
            };
          case 'hmacSHA256Base64':
            return {
              'v': base64Encode(Hmac(sha256, utf8.encode(a.length > 1 ? a[1] : ''))
                  .convert(utf8.encode(a.isEmpty ? '' : a[0]))
                  .bytes)
            };
        }
        return {'v': ''};
      }
      final headers = <String, String>{};
      final h = req['headers'];
      if (h is Map) h.forEach((k, v) => headers['$k'] = '$v');
      final method = '${req['method']}';
      return await _httpCall(ext, client, '${req['url']}', method, headers,
          '${req['body'] ?? ''}');
    } catch (err) {
      return {'error': '$err'};
    }
  }

  // ───────────────────────── shared network policy ─────────────────────────

  static Future<Map<String, dynamic>> _httpCall(
    InstalledExtension ext,
    http.Client client,
    String url,
    String method,
    Map<String, String> headers,
    String body,
  ) async {
    final uri = _checkUrl(ext, url);
    if (!const {'GET', 'POST', 'PUT', 'DELETE', 'PATCH'}.contains(method)) {
      throw 'method not allowed';
    }
    final req = http.Request(method, uri);
    // No automatic redirects: a 30x could leave the approved hosts.
    req.followRedirects = false;
    headers.forEach((k, v) {
      final key = k.toLowerCase();
      // The host stays in charge of identity and credentials.
      if (key == 'cookie' || key == 'host') return;
      req.headers[k] = v;
    });
    if (body.isNotEmpty && method != 'GET' && method != 'DELETE') req.body = body;
    final resp = await client.send(req).timeout(const Duration(seconds: 12));
    final bytes = <int>[];
    await for (final c in resp.stream) {
      bytes.addAll(c);
      if (bytes.length > _maxResponseBytes) throw 'response too large';
    }
    return {
      'status': resp.statusCode,
      'body': utf8.decode(bytes, allowMalformed: true),
      'headers': resp.headers,
    };
  }

  /// https only, declared hosts only, never a private or loopback address.
  static Uri _checkUrl(InstalledExtension ext, String raw) {
    final u = Uri.tryParse(raw);
    if (u == null || u.scheme != 'https' || u.host.isEmpty) {
      throw 'only https URLs are allowed';
    }
    final host = u.host.toLowerCase();
    if (_isPrivateHost(host)) throw 'private addresses are blocked';
    final ok = ext.hosts.any((h) => host == h || host.endsWith('.$h'));
    if (!ok) throw 'host $host not declared by extension';
    return u;
  }

  static bool _isPrivateHost(String h) {
    if (h == 'localhost' || h.endsWith('.localhost') || h.endsWith('.local')) {
      return true;
    }
    final ip = InternetAddress.tryParse(h);
    if (ip == null) return false;
    if (ip.isLoopback || ip.isLinkLocal || ip.isMulticast) return true;
    if (ip.type == InternetAddressType.IPv4) {
      final b = ip.rawAddress;
      return b[0] == 10 ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168) ||
          b[0] == 0;
    }
    return (ip.rawAddress[0] & 0xfe) == 0xfc; // fc00::/7
  }
}
