// ZenMusic · vorlon-dev
//
// Decode big JSON payloads OFF the UI isolate.
//
// Spotify "pathfinder" and YouTube "browse" responses are hundreds of KB.
// jsonDecode on the UI isolate takes 50–300 ms on a low-end phone and every
// frame drawn in that window is dropped. Small payloads stay inline (spawning
// an isolate costs more than it saves for them).

import 'dart:convert';
import 'dart:isolate';

const int _kBackgroundThreshold = 24 * 1024; // chars

Future<dynamic> decodeJsonBg(String source) {
  if (source.length < _kBackgroundThreshold) {
    return Future<dynamic>.value(jsonDecode(source));
  }
  return Isolate.run<dynamic>(() => jsonDecode(source));
}
