// ZenMusic — launcher icon switcher (SP-77).
//
// "Change the logo OUTSIDE the app": the picked logo becomes the app's
// launcher icon (the icon the user sees on their home screen), not an
// in-app brand swap. Android implements this with activity-aliases —
// each logo slot is an alias in AndroidManifest.xml with its own mipmap
// icon; switching enables one alias and disables the rest through
// PackageManager (no app restart, no new permission).
//
// Slots (must match ZenLauncherIcon.kt + the manifest aliases):
//   default, zen_logo_1 .. zen_logo_9
// Preview images live in assets/logos/<slot>.png (declared in pubspec).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

class LauncherIcon {
  LauncherIcon._();

  static const _channel = MethodChannel('zen/launcher_icon');

  /// All switchable slots, in picker order. 'default' is the stock icon.
  static const List<String> slots = [
    'default',
    'zen_logo_1',
    'zen_logo_2',
    'zen_logo_3',
    'zen_logo_4',
    'zen_logo_5',
    'zen_logo_6',
    'zen_logo_7',
    'zen_logo_8',
    'zen_logo_9',
  ];

  static const _prefKey = 'LAUNCHER_LOGO';

  /// The last slot this device reported (null until first read).
  static String? _current;

  static String? get current => _current;

  /// Human name for the picker subtitle.
  static String slotLabel(String slot) => switch (slot) {
        'default' => 'Default',
        _ => 'Zen ${slot.replaceFirst('zen_logo_', '')}',
      };

  static Future<String> loadCurrent() async {
    final saved = Hive.box('SETTINGS').get(_prefKey) as String?;
    _current = saved ?? 'default';
    if (!Platform.isAndroid) return _current!;
    try {
      final live = await _channel.invokeMethod('current') as String?;
      if (live != null && live.isNotEmpty) {
        _current = live;
        await Hive.box('SETTINGS').put(_prefKey, live);
      }
    } on MissingPluginException {
      // older native side — the saved pref is the best we know
    } catch (_) {}
    return _current!;
  }

  /// Applies [slot] as the launcher icon. Returns false when the platform
  /// cannot switch (non-Android, or the alias set is missing on this
  /// install — e.g. the app was updated without the new manifest).
  static Future<bool> apply(String slot) async {
    if (!slots.contains(slot)) return false;
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod('set', {'slot': slot}) as bool?;
      if (ok == true) {
        _current = slot;
        await Hive.box('SETTINGS').put(_prefKey, slot);
      } else {
        // SP-82: say WHY on the console so a failed switch is diagnosable
        // from `flutter run` — almost always the installed APK was built
        // from an android/ project without the activity-alias set.
        print('[launcher-icon] set("$slot") returned false — the installed '
            'APK does not declare the launcher alias for this slot. '
            'Rebuild + reinstall from the project that ships the SP-80 '
            'AndroidManifest (activity-alias entries + mipmap icons).');
      }
      return ok == true;
    } on MissingPluginException {
      print('[launcher-icon] no zen/launcher_icon channel on this install '
            '(native side predates SP-80) — rebuild + reinstall the app.');
      return false;
    } catch (e) {
      print('[launcher-icon] set("$slot") error: $e');
      return false;
    }
  }
}
