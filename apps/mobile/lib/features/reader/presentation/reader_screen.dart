import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../activity/application/activity_providers.dart';
import '../../activity/domain/activity_summary.dart';
import '../../explanation/presentation/explanation_sheet.dart';
import '../application/last_opened_book_controller.dart';
import '../application/reader_controller.dart';
import '../application/reader_providers.dart';
import '../application/reader_settings_controller.dart';
import '../domain/book_content.dart';
import '../domain/bookmark.dart';
import '../domain/chapter_mark.dart';
import '../domain/character_anchor.dart';
import '../domain/content_format.dart';
import '../domain/document_outline.dart';
import '../domain/document_pagination_source.dart';
import '../domain/pagination_source.dart';
import '../domain/reader_element.dart';
import 'pagination/document_page.dart';
import 'pagination/reading_paginator.dart';
import 'reader_palette.dart';
import 'rendering/element_renderer.dart';
import 'rendering/element_renderer_registry.dart';
import 'rendering/page_body.dart';
import 'rendering/page_composer.dart';
import 'rendering/render_block.dart';
import 'rendering/selection_resolver.dart';
import 'widgets/bookmarks_sheet.dart';
import 'widgets/contents_sheet.dart';
import 'widgets/page_turn_view.dart';
import 'widgets/reader_settings_sheet.dart';

/// Reading time credited per save is capped (the server does the same), so an
/// idle open reader can't carry today's goal over the line on its own.
const int _maxSecondsPerSave = 15 * 60;

/// Immersive, API-backed reader with contextual AI assistance.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({required this.bookId, super.key});

  final String bookId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  /// How many pages ahead of the current one to prepare, so the reader can turn
  /// forward without waiting for measurement.
  static const int _lookahead = 2;

  late final Stopwatch _sessionStopwatch;
  late final ReaderController _readerController;
  late final AppLogger _logger;
  bool _restored = false;

  /// Whether the saved position has loaded (whether or not there was one).
  bool _progressLoaded = false;

  /// Whether the position moved since the last save.
  bool _moved = false;

  // Today's goal: the summary when the book opened, and the time read since.
  ActivitySummary? _activityAtOpen;
  int _secondsReadThisSession = 0;
  bool _celebrated = false;
  double _progress = 0;
  int _characterCount = 0;
  int _currentOffset = 0;
  int _currentIndex = 0;
  String? _contentText;

  // Incremental pagination state. The paginator measures only the pages needed
  // for the current reading window; it is recreated when the layout key
  // (font/size/viewport) changes, preserving the current character offset.
  PaginationSource? _source;
  String? _sourceText;
  ReadingPaginator? _paginator;
  PaginationKey? _paginationKey;

  // Structured rendering. The composer turns a measured page plus the elements
  // covering it into render blocks; the registry maps each block to a renderer.
  // None of this participates in pagination — page boundaries are already fixed
  // by the measurer over canonical text.
  final PageComposer _composer = PageComposer();
  final ElementRendererRegistry _registry = ElementRendererRegistry.standard();
  static const SelectionResolver _selectionResolver = SelectionResolver();
  DocumentOutline? _outline;

  @override
  void initState() {
    super.initState();
    _readerController = ref.read(readerControllerProvider);
    _logger = ref.read(loggerProvider);
    _sessionStopwatch = ref.read(readingStopwatchProvider)();
    WidgetsBinding.instance.addObserver(this);
    // Providers can't be modified mid-build; record the visit right after.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(lastOpenedBookProvider.notifier).open(widget.bookId);
      }
    });
    ref.listenManual(activitySummaryProvider, (_, next) {
      _activityAtOpen ??= next.value;
    }, fireImmediately: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _sessionStopwatch.start();
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        // Save on the way out and stop counting time the reader isn't here.
        if (_sessionStopwatch.isRunning) {
          _persistPosition();
          _sessionStopwatch.stop();
        }
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    // Persistence on teardown is best-effort: if the surrounding scope is
    // already gone, losing the final position must not throw during disposal.
    WidgetsBinding.instance.removeObserver(this);
    try {
      _persistPosition(endSession: true);
    } on Object {
      // Intentionally ignored; the last saved position stands.
    }
    _paginator?.removeListener(_onPaginatorChanged);
    _paginator?.dispose();
    super.dispose();
  }

  void _onPaginatorChanged() {
    if (mounted) setState(() {});
  }

  /// Returns the paginator for the current layout, creating a new one only when
  /// the layout key changes. Construction is cheap and does no measurement;
  /// pagination is kicked off after the frame, never inside `build()`.
  ReadingPaginator _ensurePaginator({
    required String text,
    required TextStyle style,
    required Size pageSize,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required Locale? locale,
  }) {
    if (_source == null || _sourceText != text) {
      final outline = _outline;
      // Structured when an outline is available, canonical text otherwise. The
      // choice is made once, here; nothing downstream branches on it.
      _source = outline == null
          ? StringPaginationSource(text)
          : DocumentPaginationSource(canonicalText: text, outline: outline);
      _sourceText = text;
    }

    final key = PaginationKey(
      fontSize: style.fontSize ?? 0,
      lineHeight: style.height ?? 0,
      width: pageSize.width,
      height: pageSize.height,
      textScalerDescription: textScaler.toString(),
      textDirection: textDirection,
      locale: locale,
    );

    if (_paginator == null || _paginationKey != key) {
      final previous = _paginator;
      previous?.removeListener(_onPaginatorChanged);
      previous?.dispose();

      final paginator = ReadingPaginator(
        source: _source!,
        style: style,
        pageSize: pageSize,
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
      )..addListener(_onPaginatorChanged);
      _paginator = paginator;
      _paginationKey = key;

      // Measure off the build phase: prepare the current page (and look-ahead)
      // for wherever the reader currently is, not the whole document.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _paginator != paginator) return;
        _prepareWindow(paginator);
      });
    }
    return _paginator!;
  }

  Future<void> _prepareWindow(ReadingPaginator paginator) async {
    final index = await paginator.ensureOffset(_currentOffset);
    if (!mounted || _paginator != paginator) return;
    setState(() => _currentIndex = index);
    unawaited(paginator.ensureIndex(index + _lookahead));
    unawaited(_prepareStructure(paginator, index));
  }

  /// Loads the structure covering the current page and its look-ahead.
  ///
  /// Always off the build phase, and never fatal: if elements cannot be loaded
  /// the page still renders from canonical text.
  Future<void> _prepareStructure(ReadingPaginator paginator, int index) async {
    final outline = _outline;
    if (outline == null) return;
    final page = paginator.pageOrNull(index);
    if (page == null) return;
    final last = paginator.pageOrNull(index + _lookahead) ?? page;
    try {
      await outline.ensureRange(page.startOffset, last.endOffset);
      unawaited(outline.prefetchAfter(last.endOffset));
    } on Object {
      // Degradation is the design: reading continues on canonical text.
      return;
    }
    if (mounted && _paginator == paginator) setState(() {});
  }

  /// Save the position and the reading time since the last save.
  ///
  /// [endSession] also refreshes today's activity (used when leaving).
  void _persistPosition({bool endSession = false}) {
    if (_characterCount == 0) return;
    // Leaving before the saved position arrives must not overwrite it with 0.
    if (!_progressLoaded && !_moved) return;
    final seconds = _sessionStopwatch.elapsed.inSeconds;
    // Nothing moved and no time passed: not worth a request.
    if (!_moved && seconds == 0) return;
    _moved = false;
    final fraction = (_currentOffset / _characterCount).clamp(0.0, 1.0);
    // Keeps running (or stopped) as it was; only the lap restarts.
    _sessionStopwatch.reset();
    final save = endSession
        ? _readerController.endSession
        : _readerController.saveProgress;
    unawaited(
      save(
        widget.bookId,
        currentPosition: _currentOffset.toString(),
        progressPercentage: fraction * 100,
        readingTimeSeconds: seconds,
      ).catchError((Object error) {
        // Best effort: the next save (or next session) catches up.
        _logger.warning('Could not save reading progress: $error');
      }),
    );
    if (!endSession) _noteReading(seconds);
  }

  /// Celebrate, once, when this session carries today's goal over the line.
  void _noteReading(int seconds) {
    _secondsReadThisSession += math.min(seconds, _maxSecondsPerSave);
    final before = _activityAtOpen;
    if (_celebrated || before == null || before.goalMetToday || !mounted) {
      return;
    }
    final goalSeconds = before.dailyGoalMinutes * 60;
    if (before.todayReadingSeconds + _secondsReadThisSession < goalSeconds) {
      return;
    }
    _celebrated = true;
    final streak = before.currentStreak + 1;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              // The snackbar is inverted, so use the deeper flame in both themes.
              const Icon(
                Icons.local_fire_department_rounded,
                color: AppColors.flame,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Daily goal reached \u00b7 $streak-day streak. Keep going!',
                ),
              ),
            ],
          ),
        ),
      );
  }

  void _restorePosition(String anchor, double percentage) {
    if (_restored || _characterCount == 0) return;
    _restored = true;
    final savedOffset = int.tryParse(anchor);
    _currentOffset =
        (savedOffset ??
                ((percentage / 100).clamp(0.0, 1.0) * _characterCount).round())
            .clamp(0, _characterCount);
    _progress = (_currentOffset / _characterCount).clamp(0.0, 1.0);

    // Reading progress resolves asynchronously, so it can arrive after the
    // paginator's initial window (built for offset 0) was already prepared.
    // Align the reading window to the restored offset off the build phase.
    if (_currentOffset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final paginator = _paginator;
        if (mounted && paginator != null) _prepareWindow(paginator);
      });
    }
  }

  Future<void> _jumpToAnchor(String anchor) async {
    if (_characterCount == 0) return;
    final offset = (int.tryParse(anchor) ?? 0).clamp(0, _characterCount);
    _currentOffset = offset;
    _progress = (_currentOffset / _characterCount).clamp(0.0, 1.0);
    _moved = true;

    final paginator = _paginator;
    if (paginator == null) {
      setState(() {});
    } else {
      final index = await paginator.ensureOffset(offset);
      if (!mounted) return;
      setState(() => _currentIndex = index);
      unawaited(paginator.ensureIndex(index + _lookahead));
      unawaited(_prepareStructure(paginator, index));
    }
    _persistPosition();
  }

  void _onPageChanged(ReadingPaginator paginator, int index) {
    final page = paginator.pageOrNull(index);
    if (page == null) return;
    setState(() {
      _currentIndex = index;
      _moved = _moved || page.startOffset != _currentOffset;
      _currentOffset = page.startOffset;
      _progress = _characterCount == 0
          ? 0
          : (_currentOffset / _characterCount).clamp(0.0, 1.0);
    });
    _persistPosition();
    // Prepare the next few pages so the following turn is instant.
    unawaited(paginator.ensureIndex(index + _lookahead));
    unawaited(_prepareStructure(paginator, index));
  }

  Future<void> _addBookmark() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final offset = _currentOffset;
    final label = _passageAt(_contentText ?? '', offset, maxLength: 72);
    await ref
        .read(readerControllerProvider)
        .addBookmark(
          widget.bookId,
          anchor: offset.toString(),
          label: label.isEmpty ? null : label,
        );
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
        contentText: _contentText,
        characterCount: _characterCount,
        onJump: (Bookmark bookmark) {
          Navigator.of(context).pop();
          _jumpToAnchor(bookmark.anchor);
        },
      ),
    );
  }

  void _openContents(List<ChapterMark> chapters) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => ContentsSheet(
        chapters: chapters,
        currentOffset: _currentOffset,
        onSelect: (chapter) {
          Navigator.of(sheetContext).pop();
          _jumpToAnchor(chapter.startOffset.toString());
        },
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
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

  /// Composes the blocks for a measured page.
  ///
  /// Structure is used only when it is already resident, so this never awaits
  /// and never triggers I/O during a build. With no structure the composer
  /// returns plain-text blocks covering the page exactly.
  List<RenderBlock> _composeBlocks(DocumentPage page) {
    final outline = _outline;
    final elements =
        outline != null && outline.isReady(page.startOffset, page.endOffset)
        ? outline.elementsIn(page.startOffset, page.endOffset)
        : const <ReaderElement>[];
    return _composer.compose(page: page, elements: elements);
  }

  RenderContext _renderContext(
    ThemeData theme,
    TextStyle textStyle,
    ReaderPalette palette,
  ) {
    final colors = theme.colorScheme;
    return RenderContext(
      bodyStyle: textStyle,
      // Text follows the chosen page tone; accents keep the app's theme.
      colors: RenderPalette(
        text: palette.ink,
        muted: palette.muted,
        accent: colors.primary,
        surface: colors.surfaceContainerHighest,
        outline: colors.outlineVariant,
      ),
      onLinkTap: _acknowledgeLink,
    );
  }

  /// Hyperlinks acknowledge their target without leaving the Reader.
  void _acknowledgeLink(String target) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(target), duration: const Duration(seconds: 2)),
      );
  }

  /// Resolves a page selection to canonical offsets, then explains it.
  ///
  /// Resolution can decline: an unlocatable or ambiguous selection submits
  /// nothing rather than a guessed range.
  void _explainPageSelection(DocumentPage page, String selectedText) {
    final span = _selectionResolver.resolve(
      pageText: page.text,
      pageStartOffset: page.startOffset,
      selectedText: selectedText,
      hintOffset: _currentOffset,
    );
    if (span == null) return;
    _explainSelection(selectedText.trim(), span.start, span.end);
  }

  void _explainCurrentPassage() {
    // Whole-passage explanation prefers the readable element the reader is
    // inside — paragraph, code block, list item, quote, caption or table cell —
    // and falls back to the surrounding text block when structure is absent.
    final element = _outline?.readableElementAt(_currentOffset);
    final span = element?.span;
    final text = _contentText;
    if (span != null && text != null) {
      final selected = CharacterAnchor.substring(
        text,
        span.start,
        span.end,
      ).trim();
      if (selected.isNotEmpty) {
        _explainSelection(selected, span.start, span.end);
        return;
      }
    }
    _explainSurroundingText();
  }

  void _explainSurroundingText() {
    final text = _contentText;
    if (text == null || text.isEmpty) return;
    final scalarOffset = _currentOffset.clamp(0, CharacterAnchor.length(text));
    final codeUnitOffset = CharacterAnchor.toCodeUnit(text, scalarOffset);
    final codeUnitStart = _paragraphStart(text, codeUnitOffset);
    final codeUnitEnd = _paragraphEnd(text, codeUnitOffset);
    final rawPassage = text.substring(codeUnitStart, codeUnitEnd);
    final leadingWhitespace = rawPassage.length - rawPassage.trimLeft().length;
    final trailingWhitespace =
        rawPassage.length - rawPassage.trimRight().length;
    final adjustedStart = codeUnitStart + leadingWhitespace;
    final adjustedEnd = codeUnitEnd - trailingWhitespace;
    final passage = text.substring(adjustedStart, adjustedEnd);
    if (passage.isNotEmpty) {
      _explainSelection(
        passage,
        CharacterAnchor.fromCodeUnit(text, adjustedStart),
        CharacterAnchor.fromCodeUnit(text, adjustedEnd),
      );
    }
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
            Text(
              '${(_progress * 100).round()}% complete',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          // A single chapter has nothing to navigate between.
          if ((contentState.value?.chapters.length ?? 0) > 1)
            IconButton(
              tooltip: l10n.contents,
              icon: const Icon(Icons.toc_rounded),
              onPressed: () => _openContents(contentState.value!.chapters),
            ),
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
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: _progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 180),
            builder: (context, value, _) =>
                LinearProgressIndicator(minHeight: 3, value: value),
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
      );
    }

    _characterCount = CharacterAnchor.length(content.text!);
    _contentText = content.text;
    _outline ??= ref.read(documentOutlineProvider(widget.bookId));
    final progressAsync = ref.watch(readingProgressProvider(widget.bookId));
    if (progressAsync.hasValue) _progressLoaded = true;
    final resume = progressAsync.value;
    if (resume != null) {
      _restorePosition(resume.currentPosition, resume.progressPercentage);
    }

    final settings = ref.watch(readerSettingsProvider);
    final theme = Theme.of(context);
    final palette = ReaderPalette.resolve(settings.pageTone, theme.brightness);
    final textStyle =
        theme.textTheme.bodyLarge?.copyWith(
          fontFamily: settings.fontFamily,
          fontSize: settings.fontSize,
          height: settings.lineHeight,
          letterSpacing: 0.05,
          color: palette.ink,
        ) ??
        TextStyle(
          fontFamily: settings.fontFamily,
          fontSize: settings.fontSize,
          height: settings.lineHeight,
          color: palette.ink,
        );

    return LayoutBuilder(
      key: const ValueKey('text-reader'),
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        final outerHorizontal = isWide ? 32.0 : 12.0;
        final paperHorizontal = isWide ? 56.0 : 30.0;
        const paperVertical = 34.0;
        const footerHeight = 62.0;
        final bookWidth = (constraints.maxWidth - outerHorizontal * 2).clamp(
          1.0,
          860.0,
        );
        final bookHeight = (constraints.maxHeight - 24 - footerHeight).clamp(
          1.0,
          double.infinity,
        );
        final textSize = Size(
          (bookWidth - paperHorizontal * 2).clamp(1.0, double.infinity),
          (bookHeight - paperVertical * 2).clamp(1.0, double.infinity),
        );
        final paginator = _ensurePaginator(
          text: content.text!,
          style: textStyle,
          pageSize: textSize,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.localeOf(context),
        );

        // The first readable page is prepared off the build phase; until then
        // show a lightweight indicator instead of blocking on the whole book.
        if (!paginator.hasFirstPage) {
          return const Center(
            key: ValueKey('reader-preparing'),
            child: CircularProgressIndicator(),
          );
        }

        final pageCount = paginator.pageCount;
        final currentPage = _currentIndex.clamp(0, pageCount - 1);

        return Padding(
          padding: EdgeInsets.fromLTRB(
            outerHorizontal,
            12,
            outerHorizontal,
            12,
          ),
          child: Center(
            child: SizedBox(
              width: bookWidth,
              child: Column(
                children: [
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.page,
                        borderRadius: BorderRadius.circular(isWide ? 18 : 10),
                        border: Border.all(color: palette.hairline),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.ink.withValues(alpha: 0.10),
                            blurRadius: 30,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(isWide ? 18 : 10),
                        child: PageTurnView(
                          itemCount: pageCount,
                          initialPage: currentPage,
                          onPageChanged: (index) =>
                              _onPageChanged(paginator, index),
                          itemBuilder: (context, index) {
                            final page = paginator.pageOrNull(index);
                            if (page == null) {
                              unawaited(paginator.ensureIndex(index));
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: paperHorizontal,
                                vertical: paperVertical,
                              ),
                              child: PageBody(
                                blocks: _composeBlocks(page),
                                registry: _registry,
                                explainLabel: l10n.explain,
                                renderContext: _renderContext(
                                  theme,
                                  textStyle,
                                  palette,
                                ),
                                onExplain: (selected) =>
                                    _explainPageSelection(page, selected),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: footerHeight,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Page ${currentPage + 1} of ${paginator.estimatedTotalPages}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.tonalIcon(
                          onPressed: _explainCurrentPassage,
                          icon: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 17,
                          ),
                          label: const Text('Explain'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UnsupportedView extends StatelessWidget {
  const _UnsupportedView({required this.message, super.key});

  final String message;

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
                  Icons.picture_as_pdf_outlined,
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
                'PDF, EPUB, Markdown and plain-text books are supported. '
                'Scanned or encrypted files may need OCR or a password first.',
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

int _paragraphStart(String text, int offset) {
  if (text.isEmpty) return 0;
  final safeOffset = offset.clamp(0, text.length);
  final separator = text.lastIndexOf(
    '\n\n',
    safeOffset == 0 ? 0 : safeOffset - 1,
  );
  return separator == -1 ? 0 : separator + 2;
}

int _paragraphEnd(String text, int offset) {
  if (text.isEmpty) return 0;
  final separator = text.indexOf('\n\n', offset.clamp(0, text.length));
  return separator == -1 ? text.length : separator;
}

String _passageAt(String text, int offset, {required int maxLength}) {
  if (text.isEmpty) return '';
  final codeUnitOffset = CharacterAnchor.toCodeUnit(text, offset);
  final passage = text
      .substring(
        _paragraphStart(text, codeUnitOffset),
        _paragraphEnd(text, codeUnitOffset),
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final passageLength = CharacterAnchor.length(passage);
  if (passageLength <= maxLength) return passage;
  if (maxLength <= 1) return maxLength == 1 ? '…' : '';
  return '${CharacterAnchor.substring(passage, 0, maxLength - 1).trimRight()}…';
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
