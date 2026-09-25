import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'reader_settings.dart';

/// Holds and mutates the reader's display settings (font size, line spacing,
/// typeface, and page tone).
class ReaderSettingsController extends Notifier<ReaderSettings> {
  static const _fontStep = 2.0;
  static const _lineStep = 0.2;

  @override
  ReaderSettings build() => const ReaderSettings();

  void increaseFontSize() => _setFontSize(state.fontSize + _fontStep);

  void decreaseFontSize() => _setFontSize(state.fontSize - _fontStep);

  void increaseLineHeight() => _setLineHeight(state.lineHeight + _lineStep);

  void decreaseLineHeight() => _setLineHeight(state.lineHeight - _lineStep);

  void setTypeface(ReaderTypeface typeface) =>
      state = state.copyWith(typeface: typeface);

  void setPageTone(ReaderPageTone tone) =>
      state = state.copyWith(pageTone: tone);

  void _setFontSize(double value) {
    state = state.copyWith(
      fontSize: value.clamp(
        ReaderSettings.minFontSize,
        ReaderSettings.maxFontSize,
      ),
    );
  }

  void _setLineHeight(double value) {
    state = state.copyWith(
      lineHeight: value.clamp(
        ReaderSettings.minLineHeight,
        ReaderSettings.maxLineHeight,
      ),
    );
  }
}

/// Exposes the reader display settings.
final readerSettingsProvider =
    NotifierProvider<ReaderSettingsController, ReaderSettings>(
      ReaderSettingsController.new,
    );
