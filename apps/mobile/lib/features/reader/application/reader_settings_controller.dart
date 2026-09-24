import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/preferences_store.dart';
import 'reader_settings.dart';

/// Holds, mutates, and remembers the reader's display settings.
class ReaderSettingsController extends Notifier<ReaderSettings> {
  static const _fontStep = 2.0;
  static const _lineStep = 0.2;

  static const _fontSizeKey = 'reader.font_size';
  static const _lineHeightKey = 'reader.line_height';
  static const _fontKey = 'reader.font';
  static const _sepiaKey = 'reader.sepia';

  PreferencesStore get _store => ref.read(preferencesStoreProvider);

  @override
  ReaderSettings build() {
    const defaults = ReaderSettings();
    final store = _store;
    final fontSize = double.tryParse(store.getString(_fontSizeKey) ?? '');
    final lineHeight = double.tryParse(store.getString(_lineHeightKey) ?? '');
    final font = store.getString(_fontKey);
    return ReaderSettings(
      fontSize: _clampFontSize(fontSize ?? defaults.fontSize),
      lineHeight: _clampLineHeight(lineHeight ?? defaults.lineHeight),
      font: ReaderFont.values.firstWhere(
        (value) => value.name == font,
        orElse: () => defaults.font,
      ),
      sepia: store.getString(_sepiaKey) == 'true',
    );
  }

  void increaseFontSize() => _setFontSize(state.fontSize + _fontStep);

  void decreaseFontSize() => _setFontSize(state.fontSize - _fontStep);

  void increaseLineHeight() => _setLineHeight(state.lineHeight + _lineStep);

  void decreaseLineHeight() => _setLineHeight(state.lineHeight - _lineStep);

  void setFont(ReaderFont font) {
    state = state.copyWith(font: font);
    _save(_fontKey, font.name);
  }

  void setSepia({required bool enabled}) {
    state = state.copyWith(sepia: enabled);
    _save(_sepiaKey, enabled.toString());
  }

  void _setFontSize(double value) {
    state = state.copyWith(fontSize: _clampFontSize(value));
    _save(_fontSizeKey, state.fontSize.toString());
  }

  void _setLineHeight(double value) {
    // Rounded so repeated 0.2 steps don't accumulate floating-point drift.
    final rounded = (value * 10).roundToDouble() / 10;
    state = state.copyWith(lineHeight: _clampLineHeight(rounded));
    _save(_lineHeightKey, state.lineHeight.toString());
  }

  void _save(String key, String value) {
    unawaited(_store.setString(key, value));
  }

  static double _clampFontSize(double value) =>
      value.clamp(ReaderSettings.minFontSize, ReaderSettings.maxFontSize);

  static double _clampLineHeight(double value) =>
      value.clamp(ReaderSettings.minLineHeight, ReaderSettings.maxLineHeight);
}

/// Exposes the reader display settings.
final readerSettingsProvider =
    NotifierProvider<ReaderSettingsController, ReaderSettings>(
      ReaderSettingsController.new,
    );
