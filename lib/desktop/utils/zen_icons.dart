// ZenMusic — platform icon table.
// One name per concept, resolved to the icon family that belongs to the
// platform: Cupertino on iOS/macOS, Fluent on Windows, Material elsewhere.
// Icons are always drawn in a single neutral colour by the callers; nothing
// here carries colour.
//
// Needs `cupertino_icons` and `fluentui_system_icons` in pubspec.yaml
// (both were already used by the old settings page, except cupertino_icons
// which ships with every Flutter template).

import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter/material.dart' show Icons;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

class ZenIcons {
  ZenIcons._();

  static final bool _apple = Platform.isIOS || Platform.isMacOS;
  static final bool _win = Platform.isWindows;

  static IconData _pick(IconData apple, IconData material, [IconData? fluent]) {
    if (_apple) return apple;
    if (_win && fluent != null) return fluent;
    return material;
  }

  static IconData get appearance => _pick(CupertinoIcons.paintbrush,
      Icons.palette_outlined, FluentIcons.paint_brush_24_regular);
  static IconData get player => _pick(CupertinoIcons.play_circle,
      Icons.play_circle_outline, FluentIcons.play_circle_24_regular);
  static IconData get seekBar => _pick(CupertinoIcons.slider_horizontal_3,
      Icons.tune, FluentIcons.options_24_regular);
  static IconData get playerScreen => _pick(CupertinoIcons.rectangle_on_rectangle,
      Icons.view_carousel_outlined);
  static IconData get youtube => _pick(
      CupertinoIcons.play_rectangle,
      Icons.smart_display_outlined,
      FluentIcons.video_24_regular);
  static IconData get backup => _pick(CupertinoIcons.cloud_upload,
      Icons.cloud_upload_outlined, FluentIcons.cloud_arrow_up_24_regular);
  static IconData get privacy => _pick(CupertinoIcons.shield,
      Icons.shield_outlined, FluentIcons.shield_24_regular);
  static IconData get about => _pick(CupertinoIcons.info, Icons.info_outline,
      FluentIcons.info_24_regular);
  static IconData get update => _pick(CupertinoIcons.arrow_down_circle,
      Icons.download_outlined, FluentIcons.arrow_download_24_regular);
  static IconData get openExternal => _pick(CupertinoIcons.arrow_up_right_square,
      Icons.open_in_new, FluentIcons.open_24_regular);
  static IconData get battery => _pick(CupertinoIcons.battery_25,
      Icons.battery_alert_outlined, FluentIcons.battery_warning_24_regular);
  static IconData get chevron => _pick(CupertinoIcons.chevron_forward,
      Icons.chevron_right, FluentIcons.chevron_right_24_regular);
  static IconData get search => _pick(CupertinoIcons.search, Icons.search,
      FluentIcons.search_24_regular);
  static IconData get clear => _pick(CupertinoIcons.xmark_circle_fill,
      Icons.close, FluentIcons.dismiss_24_regular);
  static IconData get connected => _pick(CupertinoIcons.link, Icons.link,
      FluentIcons.plug_connected_24_regular);
  static IconData get disconnected => _pick(CupertinoIcons.link, Icons.link_off,
      FluentIcons.plug_disconnected_24_regular);
  static IconData get person => _pick(CupertinoIcons.person,
      Icons.person_outline, FluentIcons.person_24_regular);
  static IconData get key => _pick(CupertinoIcons.lock, Icons.key_outlined,
      FluentIcons.key_24_regular);
  static IconData get eye => _pick(CupertinoIcons.eye,
      Icons.visibility_outlined, FluentIcons.eye_24_regular);
  static IconData get eyeOff => _pick(CupertinoIcons.eye_slash,
      Icons.visibility_off_outlined, FluentIcons.eye_off_24_regular);
  static IconData get paste => _pick(CupertinoIcons.doc_on_clipboard,
      Icons.content_paste, FluentIcons.clipboard_paste_24_regular);
  static IconData get error => _pick(CupertinoIcons.exclamationmark_circle,
      Icons.error_outline, FluentIcons.error_circle_24_regular);
  static IconData get check => _pick(CupertinoIcons.checkmark_circle,
      Icons.check_circle_outline);

  // Appearance
  static IconData get themeMode => _pick(CupertinoIcons.moon,
      Icons.dark_mode_outlined, FluentIcons.weather_moon_24_regular);
  static IconData get accent => _pick(CupertinoIcons.circle_lefthalf_fill,
      Icons.colorize_outlined);
  static IconData get amoled => _pick(CupertinoIcons.circle_fill,
      Icons.brightness_1_outlined);
  static IconData get dynamicColor => _pick(CupertinoIcons.sparkles,
      Icons.auto_awesome_outlined);
  static IconData get animatedBg => _pick(CupertinoIcons.waveform,
      Icons.gradient_outlined);
  static IconData get screenOn => _pick(CupertinoIcons.device_phone_portrait,
      Icons.screen_lock_portrait_outlined);
  static IconData get textSize => _pick(CupertinoIcons.textformat_size,
      Icons.format_size, FluentIcons.text_font_size_24_regular);
  static IconData get lineSpacing => _pick(CupertinoIcons.text_justify,
      Icons.format_line_spacing);
  static IconData get alignment => _pick(CupertinoIcons.text_alignleft,
      Icons.format_align_left, FluentIcons.text_align_left_24_regular);
  static IconData get haptics => _pick(CupertinoIcons.dot_radiowaves_left_right,
      Icons.vibration);
}