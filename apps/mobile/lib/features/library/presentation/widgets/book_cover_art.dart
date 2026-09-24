import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/library_providers.dart';
import '../../domain/book.dart';

/// How much detail the generated cover shows, by the space it occupies.
enum CoverStyle {
  /// Small thumbnails (e.g. the "Continue reading" shelf).
  thumbnail,

  /// Library cards; [compact] cards show only the mark.
  card,
  compact,

  /// The large cover on the book detail screen.
  hero,
}

/// A book's cover: the real picture when the book has one (EPUB covers),
/// otherwise generated art from the title. The generated art is also shown
/// while the picture loads or if it fails, so a cover never appears blank.
class BookCoverArt extends ConsumerWidget {
  const BookCoverArt({required this.book, required this.style, super.key});

  final Book book;
  final CoverStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final generated = _GeneratedCover(book: book, style: style);
    if (!book.hasCover) {
      return generated;
    }
    final picture = ref.watch(bookCoverProvider(book.id)).value;
    if (picture == null) {
      return generated;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        generated,
        Image.memory(
          picture,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          semanticLabel: 'Cover of ${book.title}',
          // A corrupt image falls back to the generated art underneath.
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _GeneratedCover extends StatelessWidget {
  const _GeneratedCover({required this.book, required this.style});

  final Book book;
  final CoverStyle style;

  @override
  Widget build(BuildContext context) {
    final colors = coverColors(book.title);
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: switch (style) {
        CoverStyle.thumbnail => Center(
          child: Text(
            coverInitials(book.title),
            style: textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
        ),
        CoverStyle.compact || CoverStyle.card => _CardArt(
          book: book,
          compact: style == CoverStyle.compact,
        ),
        CoverStyle.hero => _HeroArt(book: book),
      },
    );
  }
}

class _CardArt extends StatelessWidget {
  const _CardArt({required this.book, required this.compact});

  final Book book;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          right: compact ? -34 : -24,
          bottom: compact ? -28 : -34,
          child: Container(
            width: compact ? 96 : 150,
            height: compact ? 96 : 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
        ),
        Positioned(
          left: compact ? 14 : 22,
          top: compact ? 16 : 22,
          right: compact ? 12 : 22,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.auto_stories_rounded,
                color: Colors.white.withValues(alpha: 0.94),
                size: compact ? 24 : 30,
              ),
              if (!compact) ...[
                const SizedBox(height: 30),
                Text(
                  coverInitials(book.title),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontSize: 40,
                  ),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          left: compact ? 14 : 22,
          bottom: compact ? 14 : 20,
          child: Text(
            'README.AI',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
              letterSpacing: 1.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroArt extends StatelessWidget {
  const _HeroArt({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          right: -54,
          bottom: -50,
          child: Container(
            width: 210,
            height: 210,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.auto_stories_rounded,
                size: 34,
                color: Colors.white,
              ),
              const Spacer(),
              Text(
                coverInitials(book.title),
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  color: Colors.white,
                  fontSize: 68,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'README.AI EDITION',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Up to two initials from [title] (``R`` when there are none).
String coverInitials(String title) {
  final words = title
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2);
  final value = words.map((word) => word[0].toUpperCase()).join();
  return value.isEmpty ? 'R' : value;
}

/// A gradient chosen deterministically from [title].
List<Color> coverColors(String title) {
  const palettes = [
    [Color(0xFF4D5FF7), Color(0xFF29369E)],
    [Color(0xFFDF7A45), Color(0xFF8F3D42)],
    [Color(0xFF237A68), Color(0xFF17483F)],
    [Color(0xFF7655C6), Color(0xFF41307D)],
    [Color(0xFF386C9B), Color(0xFF1D3C61)],
  ];
  return palettes[title.hashCode.abs() % palettes.length];
}
