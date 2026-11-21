// ZenMusic · vorlon-dev
//
// Community extensions: small JavaScript plugins that add lyric sources.
// The idea follows Mornye's extension repositories (GPL-3.0,
// https://github.com/mornyeapp/Mornye): anyone hosts a `registry.json` on
// GitHub, the user adds the repo URL, then installs what they want. The
// runtime here is written from scratch and is NOT API-compatible with Mornye.
//
// Safety model
//  * Scripts run in a bare QuickJS context: no DOM, no timers, no file or
//    storage access. The only door out is `zen.fetch`.
//  * `zen.fetch` is https-only, limited to the hosts the extension declared
//    (and the user approved at install time), refuses private/loopback
//    addresses, caps response size, request count and time.
//  * A registry entry may carry a sha256; the download must match it.
//
// Extension contract (plain script, no modules):
//   async function getLyrics(track) -> { wordLrc?, lrc?, plain? } | null
//   track = { title, artist, album, durationMs, isrc, videoId }
//   Use `zen.fetch(url, {method, headers, body})` -> { status, ok, text(), json() }
//   and `zen.log(...)`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../lyrics_providers/lyric_doc.dart';

/// One entry of a repository's registry.json.
class RegistryEntry {
  RegistryEntry({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.url,
    required this.hosts,
    this.sha256,
    required this.repo,
  });

  final String id;
  final String name;
  final String version;
  final String description;
  final Uri url;
  final List<String> hosts;
  final String? sha256;
  final String repo;

  static final RegExp _idRe = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');

  /// Null when the entry is unusable (bad id, non-https script, no hosts…).
  static RegistryEntry? parse(Map m, Uri registryUri, String repo) {
    final id = '${m['id'] ?? ''}'.toLowerCase();
    if (!_idRe.hasMatch(id)) return null;
    if ('${m['type'] ?? 'lyrics'}' != 'lyrics') return null;
    final raw = '${m['url'] ?? ''}';
    if (raw.isEmpty) return null;
    final url = registryUri.resolve(raw);
    if (url.scheme != 'https') return null;
    final hosts = <String>[
      for (final h in (m['hosts'] as List? ?? const []))
        if ('$h'.trim().isNotEmpty) '$h'.trim().toLowerCase(),
    ];
    final sha = '${m['sha256'] ?? ''}'.toLowerCase();
    return RegistryEntry(
      id: id,
      name: '${m['name'] ?? id}',
      version: '${m['version'] ?? '0'}',
      description: '${m['description'] ?? ''}',
      url: url,
      hosts: hosts,
      sha256: RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ? sha : null,
      repo: repo,
    );
  }
}

/// An installed extension (stored in Hive 'SETTINGS', script on disk).
class InstalledExtension {
  InstalledExtension({
    required this.id,
    required this.name,
    required this.version,
    required this.hosts,
    required this.repo,
    required this.verified,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String version;
  final List<String> hosts;
  final String repo;
  final bool verified;
  bool enabled;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'version': version,
        'hosts': hosts,
        'repo': repo,
        'verified': verified,
        'enabled': enabled,
      };

  static InstalledExtension? fromMap(Object? o) {
    if (o is! Map) return null;
    final id = '${o['id'] ?? ''}';
    if (!RegistryEntry._idRe.hasMatch(id)) return null;
    return InstalledExtension(
      id: id,
      name: '${o['name'] ?? id}',
      version: '${o['version'] ?? '0'}',
      hosts: [for (final h in (o['hosts'] as List? ?? const [])) '$h'],
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

  /// Downloads, verifies and stores [e]. Returns an error message or null.
  /// The caller must already have shown the user [RegistryEntry.hosts].
  static Future<String?> install(RegistryEntry e) async {
    if (e.hosts.isEmpty) return 'Extension declares no network hosts';
    try {
      final r = await http.get(e.url).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return 'Download failed (HTTP ${r.statusCode})';
      if (r.bodyBytes.length > _maxScriptBytes) return 'Script too large';
      if (e.sha256 != null && sha256.convert(r.bodyBytes).toString() != e.sha256) {
        return 'Checksum mismatch, install blocked';
      }
      await (await _file(e.id)).writeAsBytes(r.bodyBytes, flush: true);
      final list = installed()..removeWhere((x) => x.id == e.id);
      list.add(InstalledExtension(
        id: e.id,
        name: e.name,
        version: e.version,
        hosts: e.hosts,
        repo: e.repo,
        verified: e.sha256 != null,
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

  /// One future per enabled extension, in priority order, for
  /// `LyricsRepository` to read alongside the built-in sources.
  static List<(String, Future<LyricDoc?>)> lyricFutures(LyricQuery q) => [
        for (final e in installed())
          if (e.enabled) (e.name, _lyrics(e, q)),
      ];

  static Future<LyricDoc?> _lyrics(InstalledExtension e, LyricQuery q) async {
    try {
      final f = await _file(e.id);
      if (!await f.exists()) return null;
      final out = await _run(e, await f.readAsString(), {
        'title': q.title,
        'artist': q.artist,
        'album': q.album,
        'durationMs': q.durationMs,
        'isrc': q.isrc,
        'videoId': q.videoId,
      });
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
      debugPrint('[ext:${e.id}] failed: $err');
      return null;
    }
  }

  static const String _prelude = r'''
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

  static Future<dynamic> _run(
      InstalledExtension ext, String source, Map<String, dynamic> track) async {
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
        final uri = _checkUrl(ext, '${m['url']}');
        final method = '${opts['method'] ?? 'GET'}'.toUpperCase();
        if (method != 'GET' && method != 'POST') throw 'method not allowed';
        final req = http.Request(method, uri);
        // No automatic redirects: a 30x could leave the approved hosts.
        req.followRedirects = false;
        final h = opts['headers'];
        if (h is Map) {
          h.forEach((k, v) {
            final key = '$k'.toLowerCase();
            // The host stays in charge of identity and credentials.
            if (key == 'cookie' || key == 'host') {
              return;
            }
            req.headers['$k'] = '$v';
          });
        }
        if (opts['body'] != null && method == 'POST') {
          req.body = '${opts['body']}';
        }
        final resp = await client.send(req).timeout(const Duration(seconds: 12));
        final bytes = <int>[];
        await for (final c in resp.stream) {
          bytes.addAll(c);
          if (bytes.length > _maxResponseBytes) throw 'response too large';
        }
        settle(id, true, {
          'status': resp.statusCode,
          'body': utf8.decode(bytes, allowMalformed: true),
        });
      } catch (err) {
        settle(id, false, '$err');
      }
    });

    try {
      final pre = rt.evaluate(_prelude);
      if (pre.isError) throw 'prelude: ${pre.stringResult}';
      final load = rt.evaluate(source);
      if (load.isError) throw 'load: ${load.stringResult}';
      final start = rt.evaluate('''
(async function () {
  try {
    if (typeof getLyrics !== 'function') throw new Error('getLyrics() missing');
    var r = await getLyrics(${jsonEncode(track)});
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
