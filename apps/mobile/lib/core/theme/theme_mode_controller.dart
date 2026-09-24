import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/preferences_store.dart';

/// Holds the user's selected [ThemeMode] (light, dark, or system).
///
/// Defaults to [ThemeMode.system] and remembers the choice across launches.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _storageKey = 'theme_mode';

  PreferencesStore get _store => ref.read(preferencesStoreProvider);

  @override
  ThemeMode build() {
    final stored = _store.getString(_storageKey);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => ThemeMode.system,
    );
  }

  /// Replace the current theme mode.
  void setMode(ThemeMode mode) {
    state = mode;
    unawaited(_store.setString(_storageKey, mode.name));
  }

  /// Toggle between light and dark, treating `system` as a starting point.
  void toggle() {
    setMode(switch (state) {
      ThemeMode.dark => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.system => ThemeMode.dark,
    });
  }
}

/// Exposes the [ThemeModeController] and its current [ThemeMode] value.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
