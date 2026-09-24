import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/files/file_picker_service.dart';
import '../../../core/network/dio_error_mapper.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/application/auth_controller.dart';
import '../../reader/application/reader_providers.dart';
import '../../reader/domain/recent_read.dart';
import '../application/library_controller.dart';
import '../domain/book.dart';
import 'widgets/book_card.dart';
import 'widgets/book_cover_art.dart';

/// The user's responsive, API-backed reading library.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _query = '';

  /// True while a book is uploading (and being prepared server-side), which
  /// can take a while for large books; it drives the button's busy state and
  /// prevents a second, duplicate upload.
  bool _uploading = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final booksState = ref.watch(libraryControllerProvider);
    // The shelf is a nicety: while loading or on error it is simply absent.
    final recent =
        ref.watch(recentReadingProvider).value ?? const <RecentRead>[];

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 20,
        title: const _LibraryBrand(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              tooltip: l10n.signOut,
              icon: const Icon(Icons.logout),
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : () => _handleUpload(context),
        icon: _uploading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              )
            : const Icon(Icons.add_rounded),
        label: Text(_uploading ? l10n.uploadingBook : l10n.uploadBook),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        child: switch (booksState) {
          AsyncData(:final value) => _LibraryBody(
            key: const ValueKey('library-data'),
            books: value,
            recent: recent,
            query: _query,
            onQueryChanged: (value) => setState(() => _query = value),
            onRefresh: () {
              ref.invalidate(recentReadingProvider);
              return ref.read(libraryControllerProvider.notifier).refresh();
            },
            onOpen: (book) => _openBook(context, book),
            onContinue: (book) => context.goNamed(
              AppRoutes.readerName,
              pathParameters: {'bookId': book.id},
            ),
            onUpload: () => _handleUpload(context),
          ),
          AsyncError() => _ErrorView(
            key: const ValueKey('library-error'),
            message: l10n.libraryLoadError,
            onRetry: () =>
                ref.read(libraryControllerProvider.notifier).refresh(),
          ),
          _ => const _LoadingView(key: ValueKey('library-loading')),
        },
      ),
    );
  }

  void _openBook(BuildContext context, Book book) {
    context.goNamed(
      AppRoutes.bookDetailName,
      pathParameters: {'bookId': book.id},
    );
  }

  Future<void> _handleUpload(BuildContext context) async {
    if (_uploading) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final picked = await ref.read(filePickerProvider).pickBook();
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await ref.read(libraryControllerProvider.notifier).uploadBook(picked);
    } on Object catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(describeError(error, fallback: l10n.uploadFailed)),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }
}

class _LibraryBrand extends StatelessWidget {
  const _LibraryBrand();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.auto_stories_rounded,
            size: 21,
            color: theme.colorScheme.onPrimary,
          ),
        ),
        const SizedBox(width: 11),
        Flexible(
          child: Text(
            'ReadMe.ai',
            style: theme.textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _LibraryBody extends StatelessWidget {
  const _LibraryBody({
    required this.books,
    required this.recent,
    required this.query,
    required this.onQueryChanged,
    required this.onRefresh,
    required this.onOpen,
    required this.onContinue,
    required this.onUpload,
    super.key,
  });

  /// How many books the "Continue reading" shelf shows at most.
  static const _shelfSize = 10;

  final List<Book> books;
  final List<RecentRead> recent;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final Future<void> Function() onRefresh;
  final void Function(Book) onOpen;
  final void Function(Book) onContinue;
  final VoidCallback onUpload;

  /// Unfinished books the user has opened, most recently read first.
  List<(Book, RecentRead)> _shelf() {
    final byId = {for (final book in books) book.id: book};
    return [
      for (final read in recent)
        if (!read.isFinished && byId[read.bookId] != null)
          (byId[read.bookId]!, read),
    ].take(_shelfSize).toList();
  }

  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final visibleBooks = normalized.isEmpty
        ? books
        : books
              .where(
                (book) =>
                    book.title.toLowerCase().contains(normalized) ||
                    book.originalFilename.toLowerCase().contains(normalized),
              )
              .toList();
    final shelf = normalized.isEmpty ? _shelf() : const <(Book, RecentRead)>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 720 ? 32.0 : 20.0;
        final contentWidth = (constraints.maxWidth - horizontal * 2).clamp(
          0.0,
          1180.0,
        );
        final columns = contentWidth >= 980
            ? 3
            : contentWidth >= 620
            ? 2
            : 1;
        // Single-column cards get a fixed height: a width-derived ratio made
        // them too short for a two-line title on narrow phones.
        const singleColumnHeight = 190.0;
        const multiColumnRatio = 0.88;

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 0),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: SizedBox(
                      width: 1180,
                      child: _LibraryHeader(
                        bookCount: books.length,
                        onQueryChanged: onQueryChanged,
                      ),
                    ),
                  ),
                ),
              ),
              if (shelf.isNotEmpty)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(horizontal, 26, horizontal, 0),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: SizedBox(
                        width: 1180,
                        child: _ContinueReadingShelf(
                          items: shelf,
                          onOpen: onContinue,
                        ),
                      ),
                    ),
                  ),
                ),
              if (books.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyView(onUpload: onUpload),
                )
              else if (visibleBooks.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _NoResultsView(),
                )
              else ...[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(horizontal, 26, horizontal, 110),
                  sliver: SliverLayoutBuilder(
                    builder: (context, sliverConstraints) {
                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 18,
                          crossAxisSpacing: 18,
                          childAspectRatio: multiColumnRatio,
                          mainAxisExtent: columns == 1
                              ? singleColumnHeight
                              : null,
                        ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final book = visibleBooks[index];
                          return BookCard(
                            book: book,
                            onTap: () => onOpen(book),
                          );
                        }, childCount: visibleBooks.length),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A horizontal shelf of books the user is partway through.
class _ContinueReadingShelf extends StatelessWidget {
  const _ContinueReadingShelf({required this.items, required this.onOpen});

  final List<(Book, RecentRead)> items;
  final void Function(Book) onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.continueReading, style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        SizedBox(
          height: 124,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final (book, read) = items[index];
              return _ContinueReadingCard(
                book: book,
                read: read,
                onTap: () => onOpen(book),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ContinueReadingCard extends StatelessWidget {
  const _ContinueReadingCard({
    required this.book,
    required this.read,
    required this.onTap,
  });

  final Book book;
  final RecentRead read;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final fraction = (read.progressPercentage / 100).clamp(0.0, 1.0);
    return SizedBox(
      width: 272,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 66,
                    height: 100,
                    child: BookCoverArt(
                      book: book,
                      style: CoverStyle.thumbnail,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.percentRead((fraction * 100).round()),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({required this.bookCount, required this.onQueryChanged});

  final int bookCount;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your reading room', style: theme.textTheme.headlineLarge),
            const SizedBox(height: 8),
            Text(
              bookCount == 0
                  ? 'A quiet place for ideas worth keeping.'
                  : '$bookCount ${bookCount == 1 ? 'book' : 'books'} · ready when you are',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
        final search = SizedBox(
          width: wide ? 330 : double.infinity,
          child: TextField(
            onChanged: onQueryChanged,
            decoration: const InputDecoration(
              hintText: 'Search your library',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        );

        return wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: copy),
                  const SizedBox(width: 28),
                  search,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [copy, const SizedBox(height: 22), search],
              );
      },
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onUpload});

  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 36, 28, 110),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 620),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: AppColors.lavender,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.add_to_photos_outlined,
                  size: 34,
                  color: AppColors.cobaltDark,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.libraryEmptyTitle,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Add a PDF, EPUB, or text file and make it easier to understand.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onUpload,
                icon: const Icon(Icons.upload_file_rounded),
                label: Text(l10n.uploadBook),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoResultsView extends StatelessWidget {
  const _NoResultsView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 52,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('No matching books', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Try another title or file name.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 52,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 18),
              Text(
                message,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Check your connection and give it another go.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
