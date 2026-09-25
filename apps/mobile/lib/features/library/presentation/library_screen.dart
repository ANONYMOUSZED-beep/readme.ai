import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/files/file_picker_service.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/state_message.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/auth_user.dart';
import '../../reader/application/last_opened_book_controller.dart';
import '../../reader/application/reader_providers.dart';
import '../application/library_controller.dart';
import '../domain/book.dart';
import 'widgets/book_card.dart';
import 'widgets/book_cover.dart';

/// The user's responsive, API-backed reading library.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _uploadingName;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final booksState = ref.watch(libraryControllerProvider);
    final user = ref.watch(authStateChangesProvider).value;
    final hasBooks = booksState.value?.isNotEmpty ?? false;

    return Scaffold(
      // The empty state carries its own upload call to action.
      floatingActionButton: hasBooks
          ? FloatingActionButton.extended(
              onPressed: () => _handleUpload(context),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.uploadBook),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final gutter = constraints.maxWidth >= 720 ? 32.0 : 20.0;
            final contentWidth = math.min(
              constraints.maxWidth - gutter * 2,
              1120.0,
            );
            final side = (constraints.maxWidth - contentWidth) / 2;

            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(libraryControllerProvider.notifier).refresh(),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(side, 16, side, 0),
                    sliver: SliverToBoxAdapter(
                      child: _LibraryHeader(
                        user: user,
                        onAccount: () => _openAccount(context),
                      ),
                    ),
                  ),
                  ...switch (booksState) {
                    AsyncData(:final value) => _contentSlivers(
                      context,
                      books: value,
                      side: side,
                      contentWidth: contentWidth,
                    ),
                    AsyncError() => [
                      _CenteredRemaining(
                        child: StateMessage(
                          key: const ValueKey('library-error'),
                          icon: Icons.cloud_off_rounded,
                          title: l10n.libraryLoadError,
                          message:
                              'Check your connection and give it another go.',
                          action: OutlinedButton.icon(
                            onPressed: () => ref
                                .read(libraryControllerProvider.notifier)
                                .refresh(),
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(l10n.retry),
                          ),
                        ),
                      ),
                    ],
                    _ => [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(side, 20, side, 0),
                        sliver: SliverToBoxAdapter(
                          child: _LibrarySkeleton(
                            key: const ValueKey('library-loading'),
                            width: contentWidth,
                          ),
                        ),
                      ),
                    ],
                  },
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _contentSlivers(
    BuildContext context, {
    required List<Book> books,
    required double side,
    required double contentWidth,
  }) {
    final uploading = _uploadingName;
    final banner = uploading == null
        ? null
        : SliverPadding(
            padding: EdgeInsets.fromLTRB(side, 20, side, 0),
            sliver: SliverToBoxAdapter(child: _UploadingBanner(uploading)),
          );

    if (books.isEmpty) {
      return [
        ?banner,
        _CenteredRemaining(
          child: _EmptyLibrary(
            onUpload: uploading == null ? () => _handleUpload(context) : null,
          ),
        ),
      ];
    }

    final normalized = _query.trim().toLowerCase();
    final visible = normalized.isEmpty
        ? books
        : books
              .where(
                (book) =>
                    book.title.toLowerCase().contains(normalized) ||
                    book.originalFilename.toLowerCase().contains(normalized),
              )
              .toList();
    final lastOpenedId = ref.watch(lastOpenedBookProvider);
    final continueBook = normalized.isEmpty
        ? books.where((book) => book.id == lastOpenedId).firstOrNull
        : null;

    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(side, 20, side, 0),
        sliver: SliverToBoxAdapter(
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search your library',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.cancel_rounded, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
        ),
      ),
      ?banner,
      if (continueBook != null)
        SliverPadding(
          padding: EdgeInsets.fromLTRB(side, 24, side, 0),
          sliver: SliverToBoxAdapter(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: _ContinueReadingCard(
                  book: continueBook,
                  onContinue: () => context.goNamed(
                    AppRoutes.readerName,
                    pathParameters: {'bookId': continueBook.id},
                  ),
                ),
              ),
            ),
          ),
        ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(side, 30, side, 16),
        sliver: SliverToBoxAdapter(
          child: _SectionHeader(
            title: normalized.isEmpty ? 'All books' : 'Results',
            count: visible.length,
          ),
        ),
      ),
      if (visible.isEmpty)
        const SliverToBoxAdapter(
          child: StateMessage(
            icon: Icons.search_off_rounded,
            title: 'No matching books',
            message: 'Try another title or file name.',
          ),
        )
      else
        SliverPadding(
          padding: EdgeInsets.fromLTRB(side, 0, side, 120),
          sliver: _BookGrid(
            books: visible,
            width: contentWidth,
            onOpen: (book) => context.goNamed(
              AppRoutes.bookDetailName,
              pathParameters: {'bookId': book.id},
            ),
          ),
        ),
    ];
  }

  void _openAccount(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const _AccountSheet(),
    );
  }

  Future<void> _handleUpload(BuildContext context) async {
    if (_uploadingName != null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final picked = await ref.read(filePickerProvider).pickBook();
    if (picked == null || !mounted) return;
    setState(() => _uploadingName = picked.filename);
    try {
      await ref.read(libraryControllerProvider.notifier).uploadBook(picked);
    } on Object {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.uploadFailed)));
    } finally {
      if (mounted) setState(() => _uploadingName = null);
    }
  }
}

/// Centers [child] in the viewport space left below the preceding slivers.
///
/// Unlike `SliverFillRemaining`, it grows (and scrolls) rather than
/// overflowing when the content is taller than the space available.
class _CenteredRemaining extends StatelessWidget {
  const _CenteredRemaining({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) => SliverToBoxAdapter(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(
              0,
              constraints.viewportMainAxisExtent -
                  constraints.precedingScrollExtent,
            ),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({required this.user, required this.onAccount});

  final AuthUser? user;
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(user, DateTime.now()),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(l10n.libraryTitle, style: theme.textTheme.displaySmall),
            ],
          ),
        ),
        _Avatar(user: user, size: 40, onTap: onAccount),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, required this.size, this.onTap});

  final AuthUser? user;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        shape: BoxShape.circle,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        _initialOf(user),
        style: TextStyle(
          fontFamily: AppFonts.serif,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.42,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
    if (onTap == null) return avatar;
    return IconButton(
      tooltip: 'Account',
      onPressed: onTap,
      padding: EdgeInsets.zero,
      icon: avatar,
    );
  }
}

class _AccountSheet extends ConsumerWidget {
  const _AccountSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final user = ref.watch(authStateChangesProvider).value;
    final mode = ref.watch(themeModeProvider);
    final name = user?.displayName;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Avatar(user: user, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name == null || name.isEmpty ? 'Reader' : name,
                        style: theme.textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (user != null)
                        Text(
                          user.email,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              'Appearance',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_outlined),
                    label: Text('System'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('Dark'),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (selection) => ref
                    .read(themeModeProvider.notifier)
                    .setMode(selection.first),
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.logout, color: theme.colorScheme.error),
              title: Text(
                l10n.signOut,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              onTap: () {
                final auth = ref.read(authControllerProvider.notifier);
                Navigator.of(context).pop();
                auth.signOut();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueReadingCard extends ConsumerWidget {
  const _ContinueReadingCard({required this.book, required this.onContinue});

  final Book book;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = ref.watch(readingProgressProvider(book.id)).value;
    final fraction = ((progress?.progressPercentage ?? 0) / 100).clamp(
      0.0,
      1.0,
    );

    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onContinue,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(
                width: 62,
                child: AspectRatio(
                  aspectRatio: BookCover.aspectRatio,
                  child: BookCover(book: book),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CONTINUE READING',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.tertiary,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.title,
                      style: theme.textTheme.titleLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: fraction,
                              minHeight: 4,
                              color: theme.colorScheme.tertiary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${(fraction * 100).round()}%',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadingBanner extends StatelessWidget {
  const _UploadingBanner(this.filename);

  final String filename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: theme.colorScheme.tertiary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Uploading $filename',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Preparing it for reading…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer.withValues(
                      alpha: 0.75,
                    ),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(width: 8),
        Text(
          '$count',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Column count and tile geometry for a shelf of the given [width].
({int columns, double tileWidth, double extent}) _gridGeometry(
  BuildContext context,
  double width,
) {
  final columns = width < 520
      ? 2
      : width < 760
      ? 3
      : width < 1000
      ? 4
      : 5;
  final tileWidth = (width - _gridCrossSpacing * (columns - 1)) / columns;
  final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
  final extent = tileWidth / BookCover.aspectRatio + 72 * textScale;
  return (columns: columns, tileWidth: tileWidth, extent: extent);
}

const double _gridCrossSpacing = 18;
const double _gridMainSpacing = 18;

class _BookGrid extends StatelessWidget {
  const _BookGrid({
    required this.books,
    required this.width,
    required this.onOpen,
  });

  final List<Book> books;
  final double width;
  final void Function(Book) onOpen;

  @override
  Widget build(BuildContext context) {
    final geometry = _gridGeometry(context, width);
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: geometry.columns,
        crossAxisSpacing: _gridCrossSpacing,
        mainAxisSpacing: _gridMainSpacing,
        mainAxisExtent: geometry.extent,
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        final book = books[index];
        return _FadeSlideIn(
          index: index,
          child: BookCard(book: book, onTap: () => onOpen(book)),
        );
      }, childCount: books.length),
    );
  }
}

/// Staggered entrance for shelf tiles.
class _FadeSlideIn extends StatelessWidget {
  const _FadeSlideIn({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final step = math.min(index, 8);
    final total = 360 + step * 45;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(step * 45 / total, 1, curve: Curves.easeOutCubic),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _LibrarySkeleton extends StatelessWidget {
  const _LibrarySkeleton({required this.width, super.key});

  final double width;

  @override
  Widget build(BuildContext context) {
    final geometry = _gridGeometry(context, width);
    return SkeletonPulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(height: 48, radius: 16),
          const SizedBox(height: 34),
          const SkeletonBox(width: 120, height: 20),
          const SizedBox(height: 20),
          Wrap(
            spacing: _gridCrossSpacing,
            runSpacing: _gridMainSpacing,
            children: [
              for (var i = 0; i < geometry.columns * 2; i++)
                SizedBox(
                  width: geometry.tileWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AspectRatio(
                        aspectRatio: BookCover.aspectRatio,
                        child: SkeletonBox(radius: 6),
                      ),
                      const SizedBox(height: 12),
                      SkeletonBox(width: geometry.tileWidth * 0.85),
                      const SizedBox(height: 8),
                      SkeletonBox(width: geometry.tileWidth * 0.5, height: 10),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onUpload});

  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 96),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _BookStackIllustration(),
              const SizedBox(height: 32),
              Text(
                l10n.libraryEmptyTitle,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Add a book or document, then select anything that puzzles '
                'you — ReadMe explains it in context.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: onUpload,
                icon: const Icon(Icons.upload_rounded),
                label: Text(l10n.uploadBook),
              ),
              const SizedBox(height: 14),
              Text('PDF, EPUB and TXT files', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three fanned-out books with an AI sparkle, drawn with plain widgets.
class _BookStackIllustration extends StatelessWidget {
  const _BookStackIllustration();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget book(Color color, double angle, Offset offset) =>
        Transform.translate(
          offset: offset,
          child: Transform.rotate(
            angle: angle,
            child: Container(
              width: 74,
              height: 108,
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(3),
                  bottomLeft: Radius.circular(3),
                  topRight: Radius.circular(7),
                  bottomRight: Radius.circular(7),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final w in const [40.0, 30.0])
                    Container(
                      width: w,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );

    return SizedBox(
      width: 200,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          book(const Color(0xFF2F5E4E), -0.2, const Offset(-50, 8)),
          book(const Color(0xFFC0643F), 0.18, const Offset(50, 8)),
          book(const Color(0xFF2F3F73), 0, Offset.zero),
          Positioned(
            right: 34,
            top: 0,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 20,
                color: theme.colorScheme.tertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _greeting(AuthUser? user, DateTime now) {
  final hour = now.hour;
  final salutation = hour < 12
      ? 'Good morning'
      : hour < 17
      ? 'Good afternoon'
      : 'Good evening';
  final name = user?.displayName?.trim();
  if (name == null || name.isEmpty) return salutation;
  return '$salutation, ${name.split(RegExp(r'\s+')).first}';
}

String _initialOf(AuthUser? user) {
  final source = (user?.displayName?.trim().isNotEmpty ?? false)
      ? user!.displayName!.trim()
      : user?.email.trim() ?? '';
  return source.isEmpty ? 'R' : source.characters.first.toUpperCase();
}
