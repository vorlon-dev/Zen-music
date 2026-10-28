// ZenMusic Desktop — ported from Echo Music (GPL-3.0). ZenMusic remains GPL-3.0.

part of 'appearance_cubit.dart';

@immutable
sealed class AppearanceState {
  const AppearanceState();
}

class AppearanceLoaded extends AppearanceState {
  final ThemeMode themeMode;
  final Color? accentColor;
  final bool amoledBlack;
  final bool dynamicColors;
  final bool liquidGlass; // SP-54: Liquid Glass whole-app theme
  final String uiTheme; // SP-58: 'classic' | 'liquid' | 'm3'

  const AppearanceLoaded({
    required this.themeMode,
    required this.accentColor,
    required this.amoledBlack,
    required this.dynamicColors,
    required this.liquidGlass, // SP-54
    required this.uiTheme, // SP-58
  });
}
