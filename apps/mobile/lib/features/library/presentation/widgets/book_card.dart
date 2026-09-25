import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/formatters/byte_formatter.dart';
import '../../domain/book.dart';
import '../../domain/book_status.dart';
import 'book_cover.dart';

/// A book on the library shelf: its cover, title, and file details.
///
/// Size it with a grid cell whose height is roughly `width * 1.5 + 72`
/// (cover plus two lines of text).
class BookCard extends StatelessWidget {
  const BookCard({required this.book, required this.onTap, super.key});

  final Book book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: BookCover.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BookCover(book: book, heroTag: 'book-cover-${book.id}'),
                  if (book.status.isPreparing) const _PreparingOverlay(),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              book.title,
              style: theme.textTheme.titleSmall?.copyWith(height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                if (book.status != BookStatus.ready) ...[
                  BookStatusDot(status: book.status),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    switch (book.status) {
                      BookStatus.ready =>
                        '${fileKindOf(book)} · ${formatBytes(book.fileSize)}',
                      BookStatus.uploading ||
                      BookStatus.processing => 'Preparing to read…',
                      _ => book.status.label,
                    },
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Veils a cover while the book is prepared for reading.
class _PreparingOverlay extends StatelessWidget {
  const _PreparingOverlay();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Center(
        child: SizedBox.square(
          dimension: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// A small colored dot signalling a book's processing status.
class BookStatusDot extends StatelessWidget {
  const BookStatusDot({required this.status, super.key});

  final BookStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      BookStatus.ready => AppColors.success,
      BookStatus.failed => Theme.of(context).colorScheme.error,
      BookStatus.processing || BookStatus.uploading => AppColors.warning,
      BookStatus.uploaded => Theme.of(context).colorScheme.outline,
    };
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
