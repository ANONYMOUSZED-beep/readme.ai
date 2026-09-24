import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../explanation/presentation/explanation_sheet.dart';
import '../application/reader_controller.dart';
import '../application/reader_providers.dart';
import '../application/reader_settings_controller.dart';
import '../domain/book_content.dart';
import '../domain/bookmark.dart';
import '../domain/content_format.dart';
import 'widgets/bookmarks_sheet.dart';
import 'widgets/explainable_text.dart';
import 'widgets/reader_settings_sheet.dart';

/// Immersive, API-backed reader with contextual AI assistance.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({required this.bookId, super.key});

  final String bookId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final ScrollController _scrollController = ScrollController();
  final Stopwatch _sessionStopwatch = Stopwatch()..start();

  /// Reading progress as a 0..1 fraction. A notifier (not widget state) so
  /// scrolling repaints only the progress indicators, never the book text.
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  // Captured up front: `ref` must not be used once the widget is disposing,
  // which is exactly when the final position needs saving.
  late final ReaderController _readerController;
  late final AppLogger _logger;

  Timer? _saveDebounce;
  bool _restored = false;

  /// Whether the position changed since it was last saved. Guards against
  /// overwriting a saved position with 0% when the reader is closed before
  /// the saved position has even been restored.
  bool _unsaved = false;
  int _characterCount = 0;

  @override
  void initState() {
    super.initState();
    _readerController = ref.read(readerControllerProvider);
    _logger = ref.read(loggerProvider);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    // The scroll view is already detached here, so the last observed
    // position is saved rather than read from the controller.
    _persistPosition();
    _progress.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  double get _scrollFraction {
    if (!_scrollController.hasClients) return _progress.value;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return 0;
    return (_scrollController.offset / max).clamp(0.0, 1.0);
  }

  int _offsetFromFraction(double fraction) =>
      (fraction * _characterCount).round();

  void _onScroll() {
    _progress.value = _scrollFraction;
    _unsaved = true;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 1200), _persistPosition);
  }

  void _persistPosition() {
    if (!_unsaved || _characterCount == 0) return;
    _unsaved = false;
    final fraction = _progress.value;
    final seconds = _sessionStopwatch.elapsed.inSeconds;
    _sessionStopwatch
      ..reset()
      ..start();
    unawaited(
      _readerController
          .saveProgress(
            widget.bookId,
            currentPosition: _offsetFromFraction(fraction).toString(),
            progressPercentage: fraction * 100,
            readingTimeSeconds: seconds,
          )
          .catchError((Object error) {
            // Best effort: the next save (or next session) catches up.
            _logger.warning('Could not save reading progress: $error');
          }),
    );
  }

  void _restorePosition(double percentage) {
    if (_restored) return;
    _restored = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients || !mounted) return;
      final max = _scrollController.position.maxScrollExtent;
      final target = (percentage / 100).clamp(0.0, 1.0) * max;
      _scrollController.jumpTo(target);
      _progress.value = percentage / 100;
    });
  }

  void _jumpToAnchor(String anchor) {
    final offset = int.tryParse(anchor) ?? 0;
    if (_characterCount == 0 || !_scrollController.hasClients) return;
    final fraction = (offset / _characterCount).clamp(0.0, 1.0);
    _scrollController.animateTo(
      fraction * _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _addBookmark() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final offset = _offsetFromFraction(_scrollFraction);
    await ref
        .read(readerControllerProvider)
        .addBookmark(widget.bookId, anchor: offset.toString());
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.bookmarkAdded),
          action: SnackBarAction(label: 'View', onPressed: _openBookmarks),
        ),
      );
  }

  void _openBookmarks() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => BookmarksSheet(
        bookId: widget.bookId,
        onJump: (Bookmark bookmark) {
          Navigator.of(context).pop();
          _jumpToAnchor(bookmark.anchor);
        },
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const ReaderSettingsSheet(),
    );
  }

  void _explainSelection(String text, int start, int end) {
    final args = (
      bookId: widget.bookId,
      anchor: start.toString(),
      endAnchor: end.toString(),
      selectedText: text,
    );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ExplanationSheet(args: args),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final contentState = ref.watch(bookContentProvider(widget.bookId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        backgroundColor: theme.colorScheme.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              contentState.value?.title ?? l10n.appTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            ValueListenableBuilder<double>(
              valueListenable: _progress,
              builder: (context, progress, _) => Text(
                '${(progress * 100).round()}% complete',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l10n.bookmarkThisPosition,
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: contentState.hasValue ? _addBookmark : null,
          ),
          IconButton(
            tooltip: l10n.bookmarks,
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: _openBookmarks,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: l10n.readerSettings,
              icon: const Icon(Icons.tune_rounded),
              onPressed: _openSettings,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: ValueListenableBuilder<double>(
            valueListenable: _progress,
            builder: (context, progress, _) => TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 180),
              builder: (context, value, _) =>
                  LinearProgressIndicator(minHeight: 3, value: value),
            ),
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: switch (contentState) {
          AsyncData(:final value) => _buildContent(context, value),
          AsyncError() => _ReaderError(
            onRetry: () => ref.invalidate(bookContentProvider(widget.bookId)),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, BookContent content) {
    final l10n = AppLocalizations.of(context);
    if (content.format != ContentFormat.text || content.text == null) {
      return _UnsupportedView(
        key: const ValueKey('unsupported-reader'),
        message: l10n.readerUnsupportedFormat,
        detail: l10n.readerUnsupportedDetail,
      );
    }

    _characterCount = content.characterCount;
    final progressAsync = ref.watch(readingProgressProvider(widget.bookId));
    final resume = progressAsync.value;
    if (resume != null) _restorePosition(resume.progressPercentage);

    final settings = ref.watch(readerSettingsProvider);
    final theme = Theme.of(context);

    return NotificationListener<ScrollUpdateNotification>(
      key: const ValueKey('text-reader'),
      onNotification: (_) {
        _onScroll();
        return false;
      },
      child: Scrollbar(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 80),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _AiReadingHint(),
                  const SizedBox(height: 24),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: MediaQuery.sizeOf(context).width > 620
                          ? 48
                          : 24,
                      vertical: 42,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.ink.withValues(alpha: 0.035),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ExplainableText(
                      text: content.text!,
                      explainLabel: l10n.explain,
                      style:
                          theme.textTheme.bodyLarge?.copyWith(
                            fontSize: settings.fontSize,
                            height: settings.lineHeight,
                            letterSpacing: 0.05,
                          ) ??
                          TextStyle(fontSize: settings.fontSize),
                      onExplain: _explainSelection,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AiReadingHint extends StatelessWidget {
  const _AiReadingHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 17,
              color: theme.colorScheme.onPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Select any word or passage, then tap Explain.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnsupportedView extends StatelessWidget {
  const _UnsupportedView({
    required this.message,
    required this.detail,
    super.key,
  });

  final String message;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(21),
                ),
                child: Icon(
                  Icons.menu_book_outlined,
                  size: 31,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                message,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                detail,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderError extends StatelessWidget {
  const _ReaderError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 52),
          const SizedBox(height: 16),
          Text(l10n.libraryLoadError),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.retry),
          ),
        ],
      ),
    );
  }
}
