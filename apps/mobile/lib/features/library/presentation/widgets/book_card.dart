import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/formatters/byte_formatter.dart';
import '../../domain/book.dart';
import '../../domain/book_status.dart';
import 'book_cover_art.dart';

/// Responsive editorial card for a book in the user's library.
class BookCard extends StatelessWidget {
  const BookCard({required this.book, required this.onTap, super.key});

  final Book book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxHeight < 250;
            return horizontal
                ? _HorizontalBook(book: book)
                : _VerticalBook(book: book);
          },
        ),
      ),
    );
  }
}

class _VerticalBook extends StatelessWidget {
  const _VerticalBook({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: SizedBox(
            width: double.infinity,
            child: _BookCover(book: book),
          ),
        ),
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _StatusBadge(status: book.status)),
                    Icon(
                      Icons.arrow_outward_rounded,
                      size: 19,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  book.title,
                  style: theme.textTheme.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  '${_fileKind(book)}  ·  ${formatBytes(book.fileSize)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HorizontalBook extends StatelessWidget {
  const _HorizontalBook({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(width: 124, child: _BookCover(book: book, compact: true)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StatusBadge(status: book.status),
                const SizedBox(height: 14),
                // Flexible: with large system text the title gives way
                // (ellipsis) instead of overflowing the card.
                Flexible(
                  child: Text(
                    book.title,
                    style: theme.textTheme.titleLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_fileKind(book)}  ·  ${formatBytes(book.fileSize)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Icon(
            Icons.arrow_forward_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.book, this.compact = false});

  final Book book;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'book-cover-${book.id}',
      child: BookCoverArt(
        book: book,
        style: compact ? CoverStyle.compact : CoverStyle.card,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final BookStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (
      Color background,
      Color foreground,
      IconData icon,
    ) = switch (status) {
      BookStatus.ready => (
        AppColors.mint.withValues(alpha: 0.55),
        const Color(0xFF246145),
        Icons.check_circle_outline_rounded,
      ),
      BookStatus.failed => (
        theme.colorScheme.errorContainer,
        theme.colorScheme.onErrorContainer,
        Icons.error_outline_rounded,
      ),
      BookStatus.processing || BookStatus.uploading => (
        AppColors.apricot.withValues(alpha: 0.48),
        const Color(0xFF78440A),
        Icons.autorenew_rounded,
      ),
      BookStatus.uploaded => (
        theme.colorScheme.primaryContainer,
        theme.colorScheme.onPrimaryContainer,
        Icons.cloud_done_outlined,
      ),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                status.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fileKind(Book book) {
  final dot = book.originalFilename.lastIndexOf('.');
  if (dot == -1) return 'DOCUMENT';
  return book.originalFilename.substring(dot + 1).toUpperCase();
}
