// ZenMusic · vorlon-dev
//
// Discord Rich Presence bridge — DISABLED (no-op stub).
//
// Why: `flutter_discord_rpc` (a cargokit/Rust plugin) broke the Android
// Gradle build with newer toolchains —
//   cargokit/gradle/plugin.gradle line 163: "For input string: 37.0"
//   (A problem occurred configuring project ':flutter_discord_rpc')
// The dependency was therefore removed from pubspec.yaml and this file is
// now a zero-dependency stub with the SAME public API.
//
// MediaPlayer still calls init()/updateTrack()/playing()/paused()/stopped()
// exactly as before, but nothing happens — no Discord status is published
// and, more importantly, playback can never be affected by this.
//
// To restore Rich Presence later: add a Dart-only or FFI-based Discord RPC
// implementation and fill the method bodies below. Do NOT re-add
// flutter_discord_rpc unless cargokit is fixed for your toolchain.

import 'dart:async';

class DiscordPresenceBridge {
  DiscordPresenceBridge._();
  static final DiscordPresenceBridge instance = DiscordPresenceBridge._();

  /// Kept for API compatibility — always false (presence disabled).
  bool get isReady => false;

  /// Call once at startup (idempotent). No-op.
  Future<void> init() async {}

  /// Kept for API compatibility — stores nothing. No-op.
  Future<void> setApplicationId(String id) async {}

  /// Called on every track change. No-op.
  void updateTrack({
    required String title,
    required String artist,
    String? artUrl,
    required String trackKey,
  }) {}

  /// Playback entered the playing state. No-op.
  void playing({Duration position = Duration.zero}) {}

  /// Playback paused. No-op.
  void paused() {}

  /// Nothing loaded anymore — clear presence. No-op.
  void stopped() {}
}
