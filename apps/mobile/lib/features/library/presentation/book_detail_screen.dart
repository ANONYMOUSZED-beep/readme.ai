import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/formatters/byte_formatter.dart';
import '../../../shared/widgets/state_message.dart';
import '../../reader/application/reader_providers.dart';
import '../../reader/domain/reading_progress.dart';
import '../application/library_controller.dart';
import '../application/library_providers.dart';
import '../domain/book.dart';
import '../domain/book_status.dart';
import 'widgets/book_card.dart';
import 'widgets/book_cover.dart';

/// Focused overview of a single book before entering the reader.
class BookDetailScreen extends ConsumerWidget {
  const BookDetailScreen({required this.bookId, super.key});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final bookState = ref.watch(bookProvider(bookId));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        actions: [
          if (bookState.hasValue)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: l10n.deleteBook,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(context, ref, bookState.value!),
              ),
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: switch (bookState) {
          AsyncData(:final value) => _BookDetailView(
            key: ValueKey(value.id),
            book: value,
          ),
          AsyncError() => StateMessage(
            icon: Icons.menu_book_outlined,
            title: l10n.libraryLoadError,
            action: OutlinedButton.icon(
              onPressed: () => ref.invalidate(bookProvider(bookId)),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.retry),
            ),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Book book,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: Text(l10n.deleteBook),
        content: Text(l10n.deleteBookConfirmation(book.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
              minimumSize: const Size(48, 44),
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await ref.read(libraryControllerProvider.notifier).deleteBook(book.id);
      router.goNamed(AppRoutes.homeName);
    } on Object {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.deleteFailed)));
    }
  }
}

class _BookDetailView extends ConsumerWidget {
  const _BookDetailView({required this.book, super.key});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = ref.watch(readingProgressProvider(book.id)).value;
    final tint = coverStyleFor(book.title).base;
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        final cover = SizedBox(
          width: wide ? 260 : 176,
          child: AspectRatio(
            aspectRatio: BookCover.aspectRatio,
            child: BookCover(book: book, heroTag: 'book-cover-${book.id}'),
          ),
        );
        final details = _BookDetails(book: book, progress: progress);

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.42],
              colors: [
                Color.lerp(
                  theme.scaffoldBackgroundColor,
                  tint,
                  theme.brightness == Brightness.dark ? 0.22 : 0.16,
                )!,
                theme.scaffoldBackgroundColor,
              ],
            ),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              wide ? 48 : 20,
              topInset + 12,
              wide ? 48 : 20,
              48,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 980 : 560),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          cover,
                          const SizedBox(width: 56),
                          Expanded(child: details),
                        ],
                      )
                    : Column(
                        children: [cover, const SizedBox(height: 28), details],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BookDetails extends StatelessWidget {
  const _BookDetails({required this.book, required this.progress});

  final Book book;
  final ReadingProgress? progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final percent = progress?.progressPercentage ?? 0;
    final started = percent >= 0.5;
    final finished = percent >= 99.5;
    final ctaLabel = finished
        ? 'Read again'
        : started
        ? 'Continue · ${percent.round()}%'
        : l10n.readBook;

    return LayoutBuilder(
      builder: (context, constraints) {
        final centered = constraints.maxWidth < 600;
        final align = centered ? TextAlign.center : TextAlign.left;
        return Column(
          crossAxisAlignment: centered
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            if (book.status != BookStatus.ready) ...[
              _StatusPill(status: book.status),
              const SizedBox(height: 14),
            ],
            Text(
              book.title,
              style: theme.textTheme.headlineLarge,
              textAlign: align,
            ),
            const SizedBox(height: 8),
            Text(
              book.originalFilename,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: align,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.goNamed(
                  AppRoutes.readerName,
                  pathParameters: {'bookId': book.id},
                ),
                icon: Icon(
                  started && !finished
                      ? Icons.play_arrow_rounded
                      : Icons.menu_book_rounded,
                ),
                label: Text(ctaLabel),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _StatsRow(book: book),
            if (progress != null && started) ...[
              const SizedBox(height: 16),
              _ProgressCard(progress: progress!),
            ],
            const SizedBox(height: 36),
            const _SectionTitle('Read with AI'),
            const SizedBox(height: 14),
            const _Tip(
              icon: Icons.touch_app_outlined,
              title: 'Select anything',
              body:
                  'Long-press a word, or drag across a sentence or passage, '
                  'then tap Explain.',
            ),
            const _Tip(
              icon: Icons.auto_awesome_outlined,
              title: 'Understand it in context',
              body:
                  'Explanations use the surrounding text, not a generic '
                  'dictionary.',
            ),
            const _Tip(
              icon: Icons.account_tree_outlined,
              title: 'Fill the gaps',
              body:
                  'When an idea builds on others, ReadMe suggests what to '
                  'learn first.',
            ),
          ],
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final BookStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, foreground, message) = switch (status) {
      BookStatus.failed => (
        theme.colorScheme.errorContainer,
        theme.colorScheme.onErrorContainer,
        "Processing failed — this file can't be read yet",
      ),
      BookStatus.processing || BookStatus.uploading => (
        AppColors.warningSoft,
        AppColors.warning,
        'Preparing this book for reading…',
      ),
      _ => (
        theme.colorScheme.surfaceContainerHigh,
        theme.colorScheme.onSurfaceVariant,
        'Uploaded · waiting to be processed',
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BookStatusDot(status: status),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: theme.textTheme.labelMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final stats = [
      ('Format', fileKindOf(book)),
      (l10n.fieldFileSize, formatBytes(book.fileSize)),
      if (book.totalPages != null) (l10n.fieldPages, '${book.totalPages}'),
      (l10n.fieldUploadedAt, _friendlyDate(book.uploadedAt)),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      stats[i].$2,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(stats[i].$1, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress});

  final ReadingProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = (progress.progressPercentage / 100).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your progress',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
              Text(
                '${_readingTime(progress.totalReadingTimeSeconds)} read',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer.withValues(
                    alpha: 0.75,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              color: theme.colorScheme.tertiary,
              backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
}

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: theme.colorScheme.tertiary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _friendlyDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = date.toLocal();
  final base = '${months[local.month - 1]} ${local.day}';
  return local.year != DateTime.now().year ? '$base, ${local.year}' : base;
}

String _readingTime(int seconds) {
  if (seconds < 60) return '<1 min';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}
