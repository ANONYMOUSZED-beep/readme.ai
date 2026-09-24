import 'package:freezed_annotation/freezed_annotation.dart';

part 'reader_settings.freezed.dart';

/// Typeface used for book text.
enum ReaderFont {
  /// Lora, a bundled serif designed for long-form reading.
  serif,

  /// The platform's interface font.
  sans,
}

/// Colour of the page. [dark] follows the app-wide dark theme.
enum ReaderPageTone { light, sepia, dark }

/// Display preferences for the reader, remembered across launches.
@freezed
abstract class ReaderSettings with _$ReaderSettings {
  const factory ReaderSettings({
    @Default(18.0) double fontSize,
    @Default(1.6) double lineHeight,
    @Default(ReaderFont.serif) ReaderFont font,

    /// Warm, low-contrast paper instead of white (light theme only).
    @Default(false) bool sepia,
  }) = _ReaderSettings;

  const ReaderSettings._();

  /// Bounds keep typography legible.
  static const double minFontSize = 12.0;
  static const double maxFontSize = 32.0;
  static const double minLineHeight = 1.2;
  static const double maxLineHeight = 2.4;

  /// Font family for [TextStyle.fontFamily] (`null`: the theme's default).
  String? get fontFamily => switch (font) {
    ReaderFont.serif => 'Lora',
    ReaderFont.sans => null,
  };
}
