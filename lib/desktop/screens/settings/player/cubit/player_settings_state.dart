// ZenMusic · vorlon-dev

part of 'player_settings_cubit.dart';

@immutable
sealed class PlayerSettingsState {
  const PlayerSettingsState();
}

class PlayerSettingsLoaded extends PlayerSettingsState {
  final bool skipSilence;

  /// Haptic beats — vibrates on the rhythm of the playing song.
  /// Backed by services/beat_haptics.dart (engine starts at boot).
  final bool beatHaptics;

  /// Vibration tier per beat: 0 = light, 1 = medium, 2 = strong
  /// (BeatStrength in services/beat_haptics.dart).
  final int beatStrength;

  /// Sing mode — vocal removal so you can sing along.
  /// Backed by services/sing_mode.dart (restored at boot).
  final bool singMode;

  /// How much of the singer's voice stays in the mix:
  /// 0.0 = full karaoke, 1.0 = untouched vocals
  /// (voiceLevel in services/sing_mode.dart).
  final double singVoiceLevel;

  /// Spatial audio: 0 = off, 6 = 6D, 16 = 16D (services/spatial_audio.dart).
  final int spatialMode;

  const PlayerSettingsLoaded({
    required this.skipSilence,
    required this.beatHaptics,
    required this.beatStrength,
    required this.singMode,
    required this.singVoiceLevel,
    required this.spatialMode,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerSettingsLoaded &&
          other.skipSilence == skipSilence &&
          other.beatHaptics == beatHaptics &&
          other.beatStrength == beatStrength &&
          other.singMode == singMode &&
          other.singVoiceLevel == singVoiceLevel &&
          other.spatialMode == spatialMode;

  @override
  int get hashCode => Object.hash(
      skipSilence, beatHaptics, beatStrength, singMode, singVoiceLevel, spatialMode);
}
