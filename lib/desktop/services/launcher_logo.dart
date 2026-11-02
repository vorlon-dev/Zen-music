// ZenMusic · vorlon-dev

import 'dart:io';

import 'package:flutter/services.dart';

class LauncherLogoSlot {
  const LauncherLogoSlot({
    required this.id,
    required this.label,
    required this.bg,
    required this.fg,
    this.preview,
    this.mandala = false,
    this.available = true,
  });

  /// 'default' or the alias suffix ('LogoZen1' … 'LogoMandala').
  final String id;
  final String label;
  final Color bg;
  final Color fg;

  /// In-app preview asset mirroring the shipped launcher PNG (null = the
  /// code-drawn fallback art is used instead).
  final String? preview;
  final bool mandala;

  final bool available;
}

class LauncherLogo {
  LauncherLogo._();

  static const _channel = MethodChannel('zen/launcher_logo');

  /// The 11 slots the Logo page offers, in display order. Colours mirror
  /// the shipped mipmap launcher PNGs so the grid previews exactly what
  /// the launcher will show.
  static const List<LauncherLogoSlot> catalog = [
    LauncherLogoSlot(
        id: 'default',
        label: 'Default',
        bg: Color(0xFF6D28D9),
        fg: Color(0xFFFFFFFF),
        preview: 'assets/icon/logo.png'),
    LauncherLogoSlot(
        id: 'LogoZen1',
        label: 'Zen 1',
        bg: Color(0xFF6D28D9),
        fg: Color(0xFFFFFFFF),
        preview: 'assets/logos/zen_logo_1.png'),
    LauncherLogoSlot(
        id: 'LogoZen2',
        label: 'Zen 2',
        bg: Color(0xFF111111),
        fg: Color(0xFFFFFFFF),
        preview: 'assets/logos/zen_logo_2.png'),
    LauncherLogoSlot(
        id: 'LogoZen3',
        label: 'Zen 3',
        bg: Color(0xFFF5F5F5),
        fg: Color(0xFF111111),
        preview: 'assets/logos/zen_logo_3.png'),
    LauncherLogoSlot(
        id: 'LogoZen4',
        label: 'Zen 4',
        bg: Color(0xFF1D4ED8),
        fg: Color(0xFFFFFFFF),
        preview: 'assets/logos/zen_logo_4.png'),
    LauncherLogoSlot(
        id: 'LogoZen5',
        label: 'Zen 5',
        bg: Color(0xFF15803D),
        fg: Color(0xFFFFFFFF),
        preview: 'assets/logos/zen_logo_5.png'),
    LauncherLogoSlot(
        id: 'LogoZen6',
        label: 'Zen 6',
        bg: Color(0xFFB91C1C),
        fg: Color(0xFFFFFFFF),
        preview: 'assets/logos/zen_logo_6.png'),
    LauncherLogoSlot(
        id: 'LogoZen7',
        label: 'Zen 7',
        bg: Color(0xFFEA580C),
        fg: Color(0xFFFFFFFF),
        preview: 'assets/logos/zen_logo_7.png'),
    LauncherLogoSlot(
        id: 'LogoZen8',
        label: 'Zen 8',
        bg: Color(0xFFBE185D),
        fg: Color(0xFFFFFFFF),
        preview: 'assets/logos/zen_logo_8.png'),
    LauncherLogoSlot(
        id: 'LogoZen9',
        label: 'Zen 9',
        bg: Color(0xFF0F766E),
        fg: Color(0xFFFFFFFF),
        preview: 'assets/logos/zen_logo_9.png'),
    LauncherLogoSlot(
        id: 'LogoMandala',
        label: 'Mandala',
        bg: Color(0xFF3B0764),
        fg: Color(0xFFE9D5FF),
        preview: 'assets/logos/mandala.png',
        mandala: true),
  ];

  /// Android build flag for UI gating (widget layer avoids dart:io).
  static bool get isAndroidPlatform => Platform.isAndroid;

  /// Android with the native channel present. A MissingPluginException
  /// (older builds / non-Android) means the slots cannot be listed.
  static Future<bool> isSupported() async {
    if (!Platform.isAndroid) return false;
    try {
      await _channel.invokeListMethod<String>('listSlots');
      return true;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return true; // channel exists but errored — still Android-capable
    }
  }

  static Future<List<LauncherLogoSlot>> listSlots() async {
    Set<String> aliases = {};
    try {
      final raw = await _channel.invokeListMethod<String>('listSlots');
      aliases = (raw ?? const [])
          .map((a) => a.contains('.') ? a.split('.').last : a)
          .toSet();
    } on MissingPluginException {
      aliases = {};
    } catch (_) {
      aliases = {};
    }
    return [
      for (final s in catalog)
        LauncherLogoSlot(
          id: s.id,
          label: s.label,
          bg: s.bg,
          fg: s.fg,
          preview: s.preview,
          mandala: s.mandala,
          available: s.id == 'default' || aliases.contains(s.id),
        ),
    ];
  }

  /// The currently-enabled alias ('default' when none is).
  static Future<String> currentSlot() async {
    try {
      final raw = await _channel.invokeMethod<String>('getCurrentSlot');
      if (raw == null || raw.isEmpty || raw == 'default') return 'default';
      return raw.contains('.') ? raw.split('.').last : raw;
    } catch (_) {
      return 'default';
    }
  }

  /// Enables the alias for [id] (or restores the default icon). Throws a
  /// StateError with a user-presentable message when the slot is missing
  /// from this install.
  static Future<void> setSlot(String id) async {
    final full = id == 'default' ? 'default' : id;
    try {
      await _channel.invokeMethod('setSlot', {'slot': full});
    } on PlatformException catch (e) {
      if (e.code == 'slot_missing') {
        throw StateError(
            'This logo slot is not available on this install. Rebuild and '
            'reinstall the app once with the new manifest — then every '
            'slot unlocks.');
      }
      rethrow;
    }
  }
}
