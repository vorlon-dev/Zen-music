// ZenMusic — ZenDurationAdapter (Hive persistence fix).
//
// Symptom: "HiveError: Cannot write, unknown type: Duration. Did you forget
// to register an adapter?" — thrown right after the Spotify engine resolved
// autoqueue neighbours ("queue: resolved + N neighbours"). The engine path
// stamps a raw Duration into the queue/history map before box.put(...), and
// hive ships NO built-in DurationAdapter (verified against the package API),
// so every frame containing it fails to persist — queue/history silently
// lost on Spotify tracks.
//
// Fix strategy: Option B (global adapter). Payload = single int
// (inMilliseconds) via readInt/writeInt — compact and stable.
//
// REGISTRATION: Hive.registerAdapter(ZenDurationAdapter());
//   Must run BEFORE the first Hive.openBox(...) — put it in main()
//   bootstrap next to your other registerAdapter calls.
//
// TYPEID: 100 chosen as very likely unused (built-ins occupy 0..~16;
// custom adapters normally live far below 100). A collision fails LOUDLY
// at startup ("There is already a TypeAdapter for typeId 100") — if that
// happens, change this to any free 0..223 value. Never reuse/remove a
// typeId that already has data on disk.

import 'package:hive/hive.dart';

class ZenDurationAdapter extends TypeAdapter<Duration> {
  @override
  final int typeId = 100;

  @override
  Duration read(BinaryReader reader) =>
      Duration(milliseconds: reader.readInt());

  @override
  void write(BinaryWriter writer, Duration obj) =>
      writer.writeInt(obj.inMilliseconds);
}