import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/book.dart';

/// A generated, typeset book cover for books without artwork.
///
/// The palette and motif are derived deterministically from the title, so a
/// book keeps the same cover everywhere it appears. Sizes itself from its
/// width; give it a 2:3 box (see [BookCover.aspectRatio]). The cover is
/// decorative and hidden from screen readers, so always show the title
/// alongside it.
class BookCover extends StatelessWidget {
  const BookCover({
    required this.book,
    this.heroTag,
    this.elevated = true,
    super.key,
  });

  /// Width-to-height ratio of a paperback.
  static const double aspectRatio = 2 / 3;

  final Book book;

  /// When set, wraps the cover in a [Hero] with this tag.
  final Object? heroTag;

  /// Whether to draw the soft drop shadow beneath the cover.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final cover = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final style = coverStyleFor(book.title);
        final radius = (width * 0.045).clamp(3.0, 9.0);
        final borderRadius = BorderRadius.only(
          topLeft: Radius.circular(radius * 0.5),
          bottomLeft: Radius.circular(radius * 0.5),
          topRight: Radius.circular(radius),
          bottomRight: Radius.circular(radius),
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            boxShadow: elevated
                ? [
                    BoxShadow(
                      color: style.shade.withValues(alpha: 0.28),
                      blurRadius: width * 0.14,
                      offset: Offset(0, width * 0.06),
                    ),
                    BoxShadow(
                      color: AppColors.ink.withValues(alpha: 0.12),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: ExcludeSemantics(
              child: _CoverArt(book: book, style: style, width: width),
            ),
          ),
        );
      },
    );
    final tag = heroTag;
    return tag == null ? cover : Hero(tag: tag, child: cover);
  }
}

class _CoverArt extends StatelessWidget {
  const _CoverArt({
    required this.book,
    required this.style,
    required this.width,
  });

  final Book book;
  final CoverStyle style;
  final double width;

  @override
  Widget build(BuildContext context) {
    final pad = width * 0.11;
    final compact = width < 72;
    // Shrink the title until its longest word fits on one line; Literata
    // semibold averages under 0.62em per character.
    final longestWord = book.title
        .split(RegExp(r'\s+'))
        .fold(0, (longest, word) => math.max(longest, word.characters.length));
    final fitSize = longestWord == 0
        ? double.infinity
        : (width - pad * 2.15) / (longestWord * 0.62);
    final titleSize = math.min((width * 0.118).clamp(9.0, 34.0), fitSize);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [style.base, style.shade],
            ),
          ),
        ),
        CustomPaint(
          painter: _MotifPainter(
            motif: style.motif,
            color: style.ink.withValues(alpha: 0.13),
          ),
        ),
        // Spine: a darker binding edge with a thin highlight.
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: math.max(4, width * 0.07),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0x38000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
        Positioned(
          left: math.max(4, width * 0.07),
          top: 0,
          bottom: 0,
          width: 1,
          child: ColoredBox(color: Colors.white.withValues(alpha: 0.14)),
        ),
        if (compact)
          Center(
            child: Text(
              _initial(book.title),
              style: TextStyle(
                fontFamily: AppFonts.serif,
                fontWeight: FontWeight.w600,
                fontSize: width * 0.44,
                color: style.ink,
                height: 1,
              ),
            ),
          )
        else
          Padding(
            padding: EdgeInsets.fromLTRB(pad * 1.15, pad, pad, pad * 0.9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.serif,
                    fontWeight: FontWeight.w600,
                    fontSize: titleSize,
                    height: 1.12,
                    letterSpacing: -0.2,
                    color: style.ink,
                  ),
                ),
                const Spacer(),
                Container(
                  width: width * 0.16,
                  height: math.max(1, width * 0.008),
                  color: style.ink.withValues(alpha: 0.55),
                ),
                SizedBox(height: width * 0.04),
                Text(
                  fileKindOf(book),
                  style: TextStyle(
                    fontSize: (width * 0.056).clamp(6.0, 12.0),
                    fontWeight: FontWeight.w700,
                    letterSpacing: width * 0.012,
                    color: style.ink.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Visual recipe for a generated cover.
@immutable
class CoverStyle {
  const CoverStyle(this.base, this.shade, this.ink, this.motif);

  final Color base;
  final Color shade;
  final Color ink;
  final int motif;
}

const _palettes = [
  (Color(0xFF2F5E4E), Color(0xFF1E4035), Color(0xFFF3EAD8)), // forest
  (Color(0xFFC0643F), Color(0xFF93452B), Color(0xFFFFF1E4)), // terracotta
  (Color(0xFF2F3F73), Color(0xFF1F2A52), Color(0xFFEEF0FF)), // ink blue
  (Color(0xFF6E3B5E), Color(0xFF4E2942), Color(0xFFFBE9F3)), // plum
  (Color(0xFFD9A441), Color(0xFFB9852A), Color(0xFF2A1E0A)), // ochre
  (Color(0xFF4D5FF7), Color(0xFF3342C9), Color(0xFFF1F2FF)), // cobalt
  (Color(0xFFE7B7A6), Color(0xFFD29C8A), Color(0xFF3B1F18)), // blush
  (Color(0xFF48525F), Color(0xFF30373F), Color(0xFFF0F2F4)), // slate
];

/// Deterministic cover style for [title] (stable across runs and platforms).
CoverStyle coverStyleFor(String title) {
  var hash = 7;
  for (final unit in title.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  final (base, shade, ink) = _palettes[hash % _palettes.length];
  return CoverStyle(base, shade, ink, (hash ~/ _palettes.length) % 3);
}

/// Upper-case file extension (e.g. `PDF`), or `DOCUMENT` when absent.
String fileKindOf(Book book) {
  final dot = book.originalFilename.lastIndexOf('.');
  if (dot == -1 || dot == book.originalFilename.length - 1) return 'DOCUMENT';
  return book.originalFilename.substring(dot + 1).toUpperCase();
}

String _initial(String title) {
  final trimmed = title.trim();
  return trimmed.isEmpty ? 'R' : trimmed.characters.first.toUpperCase();
}

class _MotifPainter extends CustomPainter {
  const _MotifPainter({required this.motif, required this.color});

  final int motif;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final w = size.width;
    final h = size.height;
    switch (motif) {
      case 0:
        // A large sun rising from the lower edge.
        canvas.drawCircle(Offset(w * 0.78, h * 1.02), w * 0.62, paint);
      case 1:
        // Concentric rings.
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, w * 0.018);
        for (var i = 1; i <= 4; i++) {
          canvas.drawCircle(Offset(w * 0.92, h * 0.74), w * 0.16 * i, paint);
        }
      default:
        // Horizontal bands across the lower third.
        for (var i = 0; i < 3; i++) {
          final top = h * (0.62 + i * 0.1);
          canvas.drawRect(Rect.fromLTWH(0, top, w, h * 0.045), paint);
        }
    }
  }

  @override
  bool shouldRepaint(_MotifPainter oldDelegate) =>
      oldDelegate.motif != motif || oldDelegate.color != color;
}
