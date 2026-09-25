import 'package:freezed_annotation/freezed_annotation.dart';

part 'reader_settings.freezed.dart';

/// Typeface used for book text.
enum ReaderTypeface {
  /// Literata, a serif designed for long-form reading.
  serif,

  /// The platform sans-serif.
  sans,
}

/// Page color used by the reader in light mode (dark mode always uses night).
enum ReaderPageTone { paper, sepia, white }

/// Display preferences for the reader, remembered across launches.
@freezed
abstract class ReaderSettings with _$ReaderSettings {
  const factory ReaderSettings({
    @Default(18.0) double fontSize,
    @Default(1.6) double lineHeight,
    @Default(ReaderTypeface.serif) ReaderTypeface typeface,
    @Default(ReaderPageTone.paper) ReaderPageTone pageTone,
  }) = _ReaderSettings;

  const ReaderSettings._();

  /// Bounds keep typography legible.
  static const double minFontSize = 12.0;
  static const double maxFontSize = 32.0;
  static const double minLineHeight = 1.2;
  static const double maxLineHeight = 2.4;

  /// Font family for [TextStyle.fontFamily] (`null`: the theme's default).
  String? get fontFamily => switch (typeface) {
    ReaderTypeface.serif => 'Literata',
    ReaderTypeface.sans => null,
  };
}
