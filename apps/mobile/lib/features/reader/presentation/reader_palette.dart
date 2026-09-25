import 'package:flutter/material.dart';

import '../application/reader_settings.dart';

/// Colors for the reading page, resolved from the page tone and brightness.
///
/// In dark mode the page is always "night"; the tone applies to light mode.
@immutable
class ReaderPalette {
  const ReaderPalette({
    required this.page,
    required this.ink,
    required this.muted,
    required this.hairline,
  });

  factory ReaderPalette.resolve(ReaderPageTone tone, Brightness brightness) {
    if (brightness == Brightness.dark) return night;
    return switch (tone) {
      ReaderPageTone.paper => paper,
      ReaderPageTone.sepia => sepia,
      ReaderPageTone.white => white,
    };
  }

  static const paper = ReaderPalette(
    page: Color(0xFFFAF6EE),
    ink: Color(0xFF2B2722),
    muted: Color(0xFF857E71),
    hairline: Color(0xFFE6DFD2),
  );

  static const sepia = ReaderPalette(
    page: Color(0xFFF1E4CC),
    ink: Color(0xFF3F3122),
    muted: Color(0xFF86705A),
    hairline: Color(0xFFDFCDAF),
  );

  static const white = ReaderPalette(
    page: Color(0xFFFFFFFF),
    ink: Color(0xFF1C1C1E),
    muted: Color(0xFF8A8A8E),
    hairline: Color(0xFFE8E8EA),
  );

  static const night = ReaderPalette(
    page: Color(0xFF141311),
    ink: Color(0xFFD8D2C6),
    muted: Color(0xFF8C867B),
    hairline: Color(0xFF2A2825),
  );

  /// Background of the page.
  final Color page;

  /// Body text color.
  final Color ink;

  /// Secondary text (metadata, captions).
  final Color muted;

  /// Rules and borders.
  final Color hairline;
}
