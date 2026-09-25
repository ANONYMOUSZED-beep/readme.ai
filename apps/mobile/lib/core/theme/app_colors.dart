import 'package:flutter/material.dart';

/// ReadMe.ai's warm editorial color system.
///
/// Ink on paper carries the interface; [insight] is reserved for AI moments
/// (explanations, sparkles, reading progress) so they stand out on the page.
abstract final class AppColors {
  // Brand accent — used sparingly for AI and progress.
  static const Color insight = Color(0xFF4D5FF7);
  static const Color insightSoft = Color(0xFFE6E8FF);
  static const Color insightDark = Color(0xFF9DA6FF);
  static const Color insightSoftDark = Color(0xFF2B305E);

  // Light surfaces.
  static const Color ink = Color(0xFF1D1B17);
  static const Color inkSoft = Color(0xFF6B665C);
  static const Color paper = Color(0xFFF6F2EA);
  static const Color paperRaised = Color(0xFFFFFDF8);
  static const Color paperSunken = Color(0xFFEEE9DE);
  static const Color hairline = Color(0xFFE4DDD0);

  // Dark surfaces.
  static const Color night = Color(0xFF121110);
  static const Color nightRaised = Color(0xFF1C1B19);
  static const Color nightSunken = Color(0xFF282623);
  static const Color nightInk = Color(0xFFEFEBE3);
  static const Color nightInkSoft = Color(0xFFA9A398);
  static const Color nightHairline = Color(0xFF302E2A);

  // Semantic accents.
  static const Color clay = Color(0xFFB0562E);
  static const Color highlight = Color(0xFFF4D784);
  static const Color success = Color(0xFF2F7D5B);
  static const Color successSoft = Color(0xFFDDEFE5);
  static const Color warning = Color(0xFF94600A);
  static const Color warningSoft = Color(0xFFF8E6C4);
}

/// Font families bundled with the app.
abstract final class AppFonts {
  /// Reading-optimised serif used for headings and book text.
  static const String serif = 'Literata';
}
