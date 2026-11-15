// ZenMusic · vorlon-dev
//
// Cross-verification of the self-contained Blowfish against vectors
// generated with pycryptodome (CBC, key '58ahf>to4|)ehoec', IV 0001020304
// 050607) plus the published ECB vectors.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zenmusic/desktop/lossless/blowfish.dart';

Uint8List _hexBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void main() {
  test('published ECB vectors', () {
    final vectors = <List<String>>[
      ['FEDCBA9876543210', '0123456789ABCDEF', '0ACEAB0FC6A0A28D'],
      ['0000000000000000', '0000000000000000', '4EF997456198DD78'],
      ['FFFFFFFFFFFFFFFF', 'FFFFFFFFFFFFFFFF', '51866FD5B85ECB8A'],
    ];
    for (final v in vectors) {
      final enc = _hexBytes(v[2]);
      final dec = BlowfishCbcDecryptor(_hexBytes(v[0]), Uint8List(8));
      final pt = dec.decryptBlock(enc);
      final hex = pt
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join();
      expect(hex, v[1], reason: 'key ${v[0]}');
    }
  });

  test('CBC full-stream decrypt matches pycryptodome', () {
    // Vectors injected by scripts/run_bf_test.sh (dart-define) — generated
    // with pycryptodome; the plaintext SHA-256 is what the Dart decryptor
    // must reproduce.
    const encHex = String.fromEnvironment('BF_ENC');
    const plainSha = String.fromEnvironment('BF_SHA');
    const keyHex = String.fromEnvironment('BF_KEY');
    const ivHex = String.fromEnvironment('BF_IV');
    expect(encHex, isNot(''));

    final dec = BlowfishCbcDecryptor(_hexBytes(keyHex), _hexBytes(ivHex));
    final enc = _hexBytes(encHex);
    final out = BytesBuilder();
    for (var off = 0; off + 8 <= enc.length; off += 8) {
      out.add(dec.decryptBlock(Uint8List.sublistView(enc, off)));
    }
    expect(sha256.convert(out.toBytes()).toString(), plainSha);
  });
}
