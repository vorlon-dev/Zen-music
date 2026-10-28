// ZenMusic Desktop — ported from Echo Music (GPL-3.0). ZenMusic remains GPL-3.0.

import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:zenmusic/desktop/services/settings_manager.dart';

part 'appearance_state.dart';

class AppearanceCubit extends Cubit<AppearanceState> {
  final SettingsManager _settings = GetIt.I<SettingsManager>();

  late final VoidCallback _listener;

  AppearanceCubit()
      : super(
          AppearanceLoaded(
            themeMode: GetIt.I<SettingsManager>().themeMode,
            accentColor: GetIt.I<SettingsManager>().accentColor,
            amoledBlack: GetIt.I<SettingsManager>().amoledBlack,
            dynamicColors: GetIt.I<SettingsManager>().dynamicColors,
            liquidGlass: GetIt.I<SettingsManager>().liquidGlass, // SP-54
            uiTheme: GetIt.I<SettingsManager>().uiTheme, // SP-58
          ),
        ) {
    _listener = () {
      if (!isClosed) {
        _emitState();
      }
    };

    _settings.addListener(_listener);
  }

  void _emitState() {
    if (isClosed) return;

    emit(
      AppearanceLoaded(
        themeMode: _settings.themeMode,
        accentColor: _settings.accentColor,
        amoledBlack: _settings.amoledBlack,
        dynamicColors: _settings.dynamicColors,
        liquidGlass: _settings.liquidGlass, // SP-54
        uiTheme: _settings.uiTheme, // SP-58
      ),
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _settings.setThemeMode(mode);
  }

  void setAmoledBlack(bool value) {
    _settings.amoledBlack = value;
  }

  void setDynamicColors(bool value) {
    _settings.dynamicColors = value;
  }

  // SP-54: Liquid Glass — whole-app glass theme switch.
  void setLiquidGlass(bool value) {
    _settings.liquidGlass = value;
  }

  // SP-58: Material 3 / Classic / Liquid Glass tri-state switch.
  void setUiTheme(String value) {
    _settings.setUiTheme(value);
  }

  @override
  Future<void> close() {
    _settings.removeListener(_listener);
    return super.close();
  }
}
