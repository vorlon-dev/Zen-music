# zen_ext_rt (optional)

Rust + QuickJS runtime for ZenMusic extensions. With it bundled, Mornye-style
extensions run natively with a real synchronous `fetch` instead of the Dart
replay workaround. Without it the app keeps working (automatic fallback).

## 1. Check the crate first (any machine with Rust)

    cd packages/zen_ext_rt/rust
    cargo test

## 2. Enable it

Add to the app's `pubspec.yaml` dependencies, then `flutter pub get`:

    zen_ext_rt:
      path: packages/zen_ext_rt

Needs the Rust toolchain (rustup) and, for Android, the NDK. Cargokit builds
it for Android, Windows and Linux. iOS keeps using the Dart fallback.

## 3. Remove it

Delete the pubspec line; nothing else changes.
