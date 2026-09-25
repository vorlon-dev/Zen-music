import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Appearance & player-behavior preferences. Each setting is a
/// ValueNotifier so open screens react immediately; call load() once
/// (settings screen and player screen both do) to hydrate from storage.
class AppearancePrefs {
  static bool _loaded = false;

  // gradient | solid | blur
  static final playerBackground = ValueNotifier<String>('gradient');
  // slim | wavy | bar
  static final sliderStyle = ValueNotifier<String>('slim');
  // surface | blur | gradient
  static final miniPlayerBackground = ValueNotifier<String>('surface');
  // 0..24 dp — player artwork + thumbnails corner radius
  static final thumbRadius = ValueNotifier<double>(14);
  static final hideThumbnail = ValueNotifier<bool>(false);
  static final showQualityBadge = ValueNotifier<bool>(true);
  // left | center | right — current lyric line alignment
  static final lyricsPosition = ValueNotifier<String>('left');
  // 16..36 sp — lyrics text size
  static final lyricsTextSize = ValueNotifier<double>(19.0);
  // 1.0..4.0 — lyrics line spacing multiplier
  static final lyricsLineSpacing = ValueNotifier<double>(1.3);
  static final hideStatusBarOnLyrics = ValueNotifier<bool>(false);
  static final keepScreenOn = ValueNotifier<bool>(false);
  static final haptics = ValueNotifier<bool>(false);
  // 0 home · 1 search · 2 library
  static final defaultTab = ValueNotifier<int>(0);
  // Ambient mode.
  static final ambientArtScale = ValueNotifier<double>(0.85);
  static final ambientShowTitle = ValueNotifier<bool>(false);
  static final ambientShowArtist = ValueNotifier<bool>(false);
  static final ambientShowLyrics = ValueNotifier<bool>(true);

  static Future<void> load() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    playerBackground.value = p.getString('ap_player_bg') ?? 'gradient';
    sliderStyle.value = p.getString('ap_slider') ?? 'slim';
    miniPlayerBackground.value = p.getString('ap_mini_bg') ?? 'surface';
    thumbRadius.value = p.getDouble('ap_thumb_radius') ?? 14;
    hideThumbnail.value = p.getBool('ap_hide_thumb') ?? false;
    showQualityBadge.value = p.getBool('ap_show_badge') ?? true;
    lyricsPosition.value = p.getString('ap_lyrics_pos') ?? 'left';
    lyricsTextSize.value = p.getDouble('ap_lyrics_size') ?? 19;
    lyricsLineSpacing.value = p.getDouble('ap_lyrics_gap') ?? 1.3;
    hideStatusBarOnLyrics.value = p.getBool('ap_hide_status') ?? false;
    keepScreenOn.value = p.getBool('ap_keep_on') ?? false;
    haptics.value = p.getBool('ap_haptics') ?? false;
    defaultTab.value = p.getInt('ap_default_tab') ?? 0;
    ambientArtScale.value = p.getDouble('ap_amb_scale') ?? 0.85;
    ambientShowTitle.value = p.getBool('ap_amb_title') ?? false;
    ambientShowArtist.value = p.getBool('ap_amb_artist') ?? false;
    ambientShowLyrics.value = p.getBool('ap_amb_lyrics') ?? true;
    _loaded = true;
  }

  static Future<void> _write(String key, Object value) async {
    final p = await SharedPreferences.getInstance();
    if (value is bool) {
      await p.setBool(key, value);
    } else if (value is double) {
      await p.setDouble(key, value);
    } else if (value is int) {
      await p.setInt(key, value);
    } else if (value is String) {
      await p.setString(key, value);
    }
  }

  static Future<void> setPlayerBackground(String v) async {
    playerBackground.value = v;
    await _write('ap_player_bg', v);
  }

  static Future<void> setSliderStyle(String v) async {
    sliderStyle.value = v;
    await _write('ap_slider', v);
  }

  static Future<void> setMiniPlayerBackground(String v) async {
    miniPlayerBackground.value = v;
    await _write('ap_mini_bg', v);
  }

  static Future<void> setThumbRadius(double v) async {
    thumbRadius.value = v;
    await _write('ap_thumb_radius', v);
  }

  static Future<void> setHideThumbnail(bool v) async {
    hideThumbnail.value = v;
    await _write('ap_hide_thumb', v);
  }

  static Future<void> setShowQualityBadge(bool v) async {
    showQualityBadge.value = v;
    await _write('ap_show_badge', v);
  }

  static Future<void> setLyricsPosition(String v) async {
    lyricsPosition.value = v;
    await _write('ap_lyrics_pos', v);
  }

  static Future<void> setLyricsTextSize(double v) async {
    lyricsTextSize.value = v;
    await _write('ap_lyrics_size', v);
  }

  static Future<void> setLyricsLineSpacing(double v) async {
    lyricsLineSpacing.value = v;
    await _write('ap_lyrics_gap', v);
  }

  static Future<void> setHideStatusBarOnLyrics(bool v) async {
    hideStatusBarOnLyrics.value = v;
    await _write('ap_hide_status', v);
  }

  static Future<void> setKeepScreenOn(bool v) async {
    keepScreenOn.value = v;
    await _write('ap_keep_on', v);
  }

  static Future<void> setHaptics(bool v) async {
    haptics.value = v;
    await _write('ap_haptics', v);
  }

  static Future<void> setDefaultTab(int v) async {
    defaultTab.value = v;
    await _write('ap_default_tab', v);
  }

  static Future<void> setAmbientArtScale(double v) async {
    ambientArtScale.value = v;
    await _write('ap_amb_scale', v);
  }

  static Future<void> setAmbientShowTitle(bool v) async {
    ambientShowTitle.value = v;
    await _write('ap_amb_title', v);
  }

  static Future<void> setAmbientShowArtist(bool v) async {
    ambientShowArtist.value = v;
    await _write('ap_amb_artist', v);
  }

  static Future<void> setAmbientShowLyrics(bool v) async {
    ambientShowLyrics.value = v;
    await _write('ap_amb_lyrics', v);
  }
}