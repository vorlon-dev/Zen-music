// ZenMusic · vorlon-dev

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/services/settings_manager.dart';
import 'package:zenmusic/desktop/services/sing_mode.dart';
import 'package:zenmusic/desktop/services/spatial_audio.dart';
import 'package:zenmusic/desktop/services/audio_vibe.dart';

part 'player_settings_state.dart';

class PlayerSettingsCubit extends Cubit<PlayerSettingsState> {
  final SettingsManager _settings = GetIt.I<SettingsManager>();
  final MediaPlayer _player = GetIt.I<MediaPlayer>();

  late final VoidCallback _listener;

  PlayerSettingsCubit()
      : super(
    PlayerSettingsLoaded(
      skipSilence: GetIt.I<SettingsManager>().skipSilence,
      beatHaptics: AppearancePrefs.beatHaptics.value,
      beatStrength: AppearancePrefs.beatStrength.value,
      singMode: SingMode.instance.enabled.value,
      singVoiceLevel: SingMode.instance.voiceLevel.value,
      spatialMode: SpatialAudio.instance.mode.value,
      vibe: AudioVibe.instance.preset.value,
      vibeSpeed: AudioVibe.instance.speed.value,
    ),
  ) {
    _listener = () {
      if (!isClosed) {
        _emitState();
      }
    };

    _settings.addListener(_listener);
    AppearancePrefs.beatHaptics.addListener(_listener);
    AppearancePrefs.beatStrength.addListener(_listener);
    SingMode.instance.enabled.addListener(_listener);
    SingMode.instance.voiceLevel.addListener(_listener);
    SpatialAudio.instance.mode.addListener(_listener);
    AudioVibe.instance.preset.addListener(_listener);
    AudioVibe.instance.speed.addListener(_listener);
  }

  void _emitState() {
    if (isClosed) return;

    final next = PlayerSettingsLoaded(
      skipSilence: _settings.skipSilence,
      beatHaptics: AppearancePrefs.beatHaptics.value,
      beatStrength: AppearancePrefs.beatStrength.value,
      singMode: SingMode.instance.enabled.value,
      singVoiceLevel: SingMode.instance.voiceLevel.value,
      spatialMode: SpatialAudio.instance.mode.value,
      vibe: AudioVibe.instance.preset.value,
      vibeSpeed: AudioVibe.instance.speed.value,
    );

    // Identical-state emits are skipped so a notifier storm never causes
    // redundant BlocBuilder rebuilds.
    if (next == state) return;

    emit(next);
  }

  Future<void> setSkipSilence(bool value) async {
    await _player.skipSilence(value);
    _settings.skipSilence = value;
    // listener will re-emit
  }

  /// Haptic beats (services/beat_haptics.dart): the engine listens on
  /// [AppearancePrefs.beatHaptics] itself, so writing the pref re-arms
  /// it for the current song — including a first-ever enable mid-song.
  Future<void> setBeatHaptics(bool value) async {
    await AppearancePrefs.setBeatHaptics(value);
    // listener will re-emit
  }

  /// 0 = light, 1 = medium, 2 = strong (BeatStrength tiers). The engine
  /// reads the tier at every fire, so changes apply from the next beat.
  Future<void> setBeatStrength(int value) async {
    await AppearancePrefs.setBeatStrength(value);
  }

  /// Sing mode (services/sing_mode.dart): persists to the SETTINGS box
  /// and applies the vocal-removal amount through the Android lossless
  /// bridge immediately.
  Future<void> setSingMode(bool value) async {
    await SingMode.instance.setEnabled(value);
    // listener will re-emit
  }

  /// 0.0 = no vocals (full karaoke), 1.0 = untouched mix. Applied live
  /// while Sing mode is on.
  Future<void> setSingVoiceLevel(double value) async {
    await SingMode.instance.setVoiceLevel(value);
  }

  /// Spatial audio (services/spatial_audio.dart): 0 = off, 6 = 6D, 16 = 16D.
  Future<void> setSpatialMode(int value) async {
    await SpatialAudio.instance.setMode(value);
  }

  /// Sound vibes (services/audio_vibe.dart): 0 off, 1 Slowed + Reverb, 2 Nightcore.
  Future<void> setVibe(int value) => AudioVibe.instance.setPreset(value);
  Future<void> setVibeSpeed(double value) => AudioVibe.instance.setSpeed(value);

  @override
  Future<void> close() {
    _settings.removeListener(_listener);
    AppearancePrefs.beatHaptics.removeListener(_listener);
    AppearancePrefs.beatStrength.removeListener(_listener);
    SingMode.instance.enabled.removeListener(_listener);
    SingMode.instance.voiceLevel.removeListener(_listener);
    SpatialAudio.instance.mode.removeListener(_listener);
    AudioVibe.instance.preset.removeListener(_listener);
    AudioVibe.instance.speed.removeListener(_listener);
    return super.close();
  }
}
