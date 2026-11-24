// ZenMusic · vorlon-dev
//
// "Dynamic colors": while the setting is on, the app accent follows the
// artwork of the song that is playing.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:palette_generator/palette_generator.dart';

import 'package:zenmusic/desktop/services/settings_manager.dart';

class DynamicAccent extends ChangeNotifier {
  DynamicAccent._();
  static final DynamicAccent instance = DynamicAccent._();

  ValueListenable<MediaItem?>? _songs;
  String? _lastKey;
  Color? _color;

  /// The colour taken from the current song, or null when the setting is off
  /// or nothing has been extracted yet.
  Color? get color => _color;

  void attach(ValueListenable<MediaItem?> currentSong) {
    _songs?.removeListener(_refresh);
    _songs = currentSong..addListener(_refresh);
    GetIt.I<SettingsManager>()
      ..removeListener(_refresh)
      ..addListener(_refresh);
    _refresh();
  }

  void _refresh() {
    final on = GetIt.I<SettingsManager>().dynamicColors;
    if (!on) {
      _lastKey = null;
      if (_color != null) {
        _color = null;
        notifyListeners();
      }
      return;
    }
    final song = _songs?.value;
    final art = song?.artUri;
    if (song == null || art == null) return;
    final key = '${song.id}|$art';
    if (key == _lastKey) return;
    _lastKey = key;
    unawaited(_extract(art, key));
  }

  Future<void> _extract(Uri art, String key) async {
    try {
      final ImageProvider image = art.scheme == 'file'
          ? FileImage(File.fromUri(art))
          : NetworkImage(art.toString());
      final palette = await PaletteGenerator.fromImageProvider(
        ResizeImage(image, width: 128, height: 128),
        maximumColorCount: 16,
      );
      if (_lastKey != key) return; // song changed while decoding
      final base = palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          palette.dominantColor?.color ??
          palette.mutedColor?.color;
      if (base == null) return;
      // Keep it usable as a primary: lively enough, never near black/white.
      final hsl = HSLColor.fromColor(base);
      final c = hsl
          .withSaturation(hsl.saturation.clamp(0.45, 0.95).toDouble())
          .withLightness(hsl.lightness.clamp(0.42, 0.68).toDouble())
          .toColor();
      if (_color?.toARGB32() == c.toARGB32()) return;
      _color = c;
      notifyListeners();
    } catch (e) {
      debugPrint('[dynamic-accent] $e');
    }
  }
}
