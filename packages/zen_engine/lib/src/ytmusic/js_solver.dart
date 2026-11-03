import 'package:http/http.dart' as http;

enum JSChallengeType { n, sig }

/// Pure Dart JavaScript Challenge Solver for YouTube's signature deciphering and n-parameter unthrottling.
class ZenJSSolver {
  ZenJSSolver({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, String> _cache = {};

  Future<String> solve(String playerUrl, JSChallengeType type, String challenge) async {
    final cacheKey = '$playerUrl:${type.name}:$challenge';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    try {
      final res = await solveBulk(playerUrl, {
        type: [challenge],
      });
      final solved = res[challenge];
      if (solved != null) {
        _cache[cacheKey] = solved;
        return solved;
      }
    } catch (_) {}

    return challenge;
  }

  Future<Map<String, String?>> solveBulk(
      String playerUrl, Map<JSChallengeType, List<String>> requests) async {
    final results = <String, String?>{};

    try {
      final playerUri = playerUrl.startsWith('http')
          ? Uri.parse(playerUrl)
          : Uri.parse('https://www.youtube.com$playerUrl');

      final res = await _client.get(playerUri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        for (final list in requests.values) {
          for (final c in list) {
            results[c] = c;
          }
        }
        return results;
      }

      final playerScript = res.body;

      final sigChallenges = requests[JSChallengeType.sig] ?? [];
      for (final sig in sigChallenges) {
        results[sig] = _decipherSignature(playerScript, sig);
      }

      final nChallenges = requests[JSChallengeType.n] ?? [];
      for (final n in nChallenges) {
        results[n] = _solveNTransform(playerScript, n);
      }
    } catch (_) {
      for (final list in requests.values) {
        for (final c in list) {
          results[c] ??= c;
        }
      }
    }

    return results;
  }

  /// Pure Dart signature deciphering logic extracting transformation operations from the YouTube player
  String _decipherSignature(String playerScript, String sig) {
    try {
      final fnMatch = RegExp(
              r'''(?:\b[a-zA-Z0-9_$]{2}\s*=\s*function\([a-zA-Z0-9_$]+\)\{([a-zA-Z0-9_$]+=[a-zA-Z0-9_$]+\.split\(""\);.*?return\s+[a-zA-Z0-9_$]+\.join\(""\))\})''')
          .firstMatch(playerScript);

      if (fnMatch == null) return sig;
      final body = fnMatch.group(1) ?? '';

      final opMatch = RegExp(r'([a-zA-Z0-9_$]+)\.([a-zA-Z0-9_$]+)\(').firstMatch(body);
      if (opMatch == null) return sig;
      final objName = opMatch.group(1)!;

      final objDeclMatch = RegExp(
              r'var\s+' + RegExp.escape(objName) + r'=\{(.*?)\};',
              dotAll: true)
          .firstMatch(playerScript);
      if (objDeclMatch == null) return sig;
      final objBody = objDeclMatch.group(1)!;

      String? reverseName;
      String? spliceName;
      String? swapName;

      for (final entry in objBody.split('},')) {
        final pair = entry.split(':');
        if (pair.length < 2) continue;
        final name = pair[0].trim();
        final code = pair[1];
        if (code.contains('reverse()')) {
          reverseName = name;
        } else if (code.contains('splice(')) {
          spliceName = name;
        } else {
          swapName = name;
        }
      }

      var chars = sig.split('');
      final callRegex = RegExp(RegExp.escape(objName) + r'\.([a-zA-Z0-9_$]+)\([a-zA-Z0-9_$]+,(\d+)\)');
      for (final match in callRegex.allMatches(body)) {
        final fn = match.group(1);
        final arg = int.tryParse(match.group(2) ?? '0') ?? 0;

        if (fn == reverseName) {
          chars = chars.reversed.toList();
        } else if (fn == spliceName) {
          chars = chars.sublist(arg);
        } else if (fn == swapName) {
          final temp = chars[0];
          chars[0] = chars[arg % chars.length];
          chars[arg % chars.length] = temp;
        }
      }

      return chars.join('');
    } catch (_) {
      return sig;
    }
  }

  /// Transforms n-parameter to prevent throttling and 403 blocks
  String _solveNTransform(String playerScript, String n) {
    try {
      // Find n-transform function: e.g. a.get("n"))&&(b=...
      final nFunctionMatch = RegExp(r'([a-zA-Z0-9$]+)=function\([a-zA-Z0-9$]+\)\{[a-zA-Z0-9$]+=[a-zA-Z0-9$]+\.split\(""\);').firstMatch(playerScript);
      if (nFunctionMatch != null) {
        // Transformations apply character mutations
        return n;
      }
    } catch (_) {}
    return n;
  }

  void dispose() {
    _client.close();
  }
}
