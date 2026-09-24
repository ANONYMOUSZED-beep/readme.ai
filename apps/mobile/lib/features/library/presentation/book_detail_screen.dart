import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/dio_error_mapper.dart';
import '../../../core/router/app_routes.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/formatters/byte_formatter.dart';
import '../application/library_controller.dart';
import '../application/library_providers.dart';
import '../domain/book.dart';
import '../domain/book_status.dart';
import 'widgets/book_cover_art.dart';

/// Focused overview of a single book before entering the reader.
class BookDetailScreen extends ConsumerWidget {
  const BookDetailScreen({required this.bookId, super.key});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final bookState = ref.watch(bookProvider(bookId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.bookDetailTitle),
        actions: [
          if (bookState.hasValue)
            Padding(
              padding: const EdgeInsets.only(right: 12),
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
          AsyncError() => _DetailError(
            onRetry: () => ref.invalidate(bookProvider(bookId)),
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

class _BookDetailView extends StatelessWidget {
  const _BookDetailView({required this.book, super.key});

  final Book book;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(wide ? 40 : 20, 24, wide ? 40 : 20, 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 330,
                          height: 440,
                          child: _DetailCover(book: book),
                        ),
                        const SizedBox(width: 52),
                        Expanded(child: _BookInformation(book: book)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: SizedBox(
                            width: 250,
                            height: 330,
                            child: _DetailCover(book: book),
                          ),
                        ),
                        const SizedBox(height: 34),
                        _BookInformation(book: book),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _DetailCover extends StatelessWidget {
  const _DetailCover({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final shadow = coverColors(book.title).last;
    return Hero(
      tag: 'book-cover-${book.id}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: shadow.withValues(alpha: 0.28),
              blurRadius: 32,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BookCoverArt(book: book, style: CoverStyle.hero),
        ),
      ),
    );
  }
}

class _BookInformation extends StatelessWidget {
  const _BookInformation({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            book.status.label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(book.title, style: theme.textTheme.headlineLarge),
        const SizedBox(height: 12),
        Text(
          'Open the book, select anything confusing, and let AI explain it '
          'inside the context of what you are reading.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
        if (book.status == BookStatus.failed)
          _ProcessingFailedCard(bookId: book.id)
        else
          FilledButton.icon(
            onPressed: () => context.goNamed(
              AppRoutes.readerName,
              pathParameters: {'bookId': book.id},
            ),
            icon: const Icon(Icons.chrome_reader_mode_outlined),
            label: Text(l10n.readBook),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
          ),
        const SizedBox(height: 30),
        Text('About this file', style: theme.textTheme.titleLarge),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              _DetailRow(
                icon: Icons.description_outlined,
                label: l10n.fieldFileName,
                value: book.originalFilename,
              ),
              _DetailRow(
                icon: Icons.data_usage_outlined,
                label: l10n.fieldFileSize,
                value: formatBytes(book.fileSize),
              ),
              if (book.totalPages != null)
                _DetailRow(
                  icon: Icons.layers_outlined,
                  label: l10n.fieldPages,
                  value: '${book.totalPages}',
                ),
              _DetailRow(
                icon: Icons.calendar_today_outlined,
                label: l10n.fieldUploadedAt,
                value: _friendlyDate(book.uploadedAt.toLocal()),
                showDivider: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Explains why a book could not be prepared and lets the reader retry.
class _ProcessingFailedCard extends ConsumerStatefulWidget {
  const _ProcessingFailedCard({required this.bookId});

  final String bookId;

  @override
  ConsumerState<_ProcessingFailedCard> createState() =>
      _ProcessingFailedCardState();
}

class _ProcessingFailedCardState extends ConsumerState<_ProcessingFailedCard> {
  bool _retrying = false;

  Future<void> _retry() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _retrying = true);
    try {
      await ref
          .read(libraryControllerProvider.notifier)
          .reprocessBook(widget.bookId);
    } on Object catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              describeError(error, fallback: l10n.retryProcessingFailed),
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final reason = ref
        .watch(processingReportProvider(widget.bookId))
        .value
        ?.errorMessage;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.processingFailedTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            reason ?? l10n.processingFailedFallback,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _retrying ? null : _retry,
            icon: _retrying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(l10n.retryProcessing),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 62,
            color: theme.colorScheme.outlineVariant,
          ),
      ],
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_outlined, size: 52),
            const SizedBox(height: 16),
            Text(l10n.libraryLoadError),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.retry),
            ),
          ],
        ),
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
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
