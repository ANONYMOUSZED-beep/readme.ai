import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/state_message.dart';
import '../../activity/application/activity_providers.dart';
import '../../activity/domain/activity_summary.dart';
import '../../explanation/presentation/explanation_sheet.dart';
import '../application/last_opened_book_controller.dart';
import '../application/reader_controller.dart';
import '../application/reader_providers.dart';
import '../application/reader_settings.dart';
import '../application/reader_settings_controller.dart';
import '../domain/book_content.dart';
import '../domain/bookmark.dart';
import '../domain/content_format.dart';
import 'reader_palette.dart';
import 'widgets/bookmarks_sheet.dart';
import 'widgets/explainable_text.dart';
import 'widgets/reader_settings_sheet.dart';

/// Characters read per minute for time estimates (roughly 230 words/min).
const int _charsPerMinute = 1200;

/// Mirrors the backend's cap on reading time credited by a single save.
const int _maxSecondsPerSave = 15 * 60;

/// Immersive, API-backed reader with contextual AI assistance.
///
/// The page fills the screen; the top and bottom chrome slide away while the
/// reader scrolls forward and return when they scroll back.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({required this.bookId, super.key});

  final String bookId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  // Measures reading time between saves; paused while the app is hidden.
  final Stopwatch _sessionStopwatch = Stopwatch()..start();
  // Scroll-driven state lives in notifiers so scrolling never rebuilds the
  // (potentially very long) book text.
  final ValueNotifier<double> _progress = ValueNotifier(0);
  final ValueNotifier<bool> _chromeVisible = ValueNotifier(true);
  Timer? _saveDebounce;
  bool _restored = false;
  bool _showTip = true;
  int _characterCount = 0;
  String? _text;

  // Today's activity when the book opened, to notice the goal being reached.
  ActivitySummary? _activityAtOpen;
  int _secondsReadThisSession = 0;
  bool _celebrated = false;

  @override
  void initState() {
    super.initState();
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
    WidgetsBinding.instance.removeObserver(this);
    _saveDebounce?.cancel();
    _persistPosition(endSession: true);
    _scrollController.dispose();
    _progress.dispose();
    _chromeVisible.dispose();
    super.dispose();
  }

  double get _scrollFraction {
    if (!_scrollController.hasClients) return 0;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return 0;
    return (_scrollController.offset / max).clamp(0.0, 1.0);
  }

  int _offsetFromFraction(double fraction) =>
      (fraction * _characterCount).round();

  bool _handleScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification is! ScrollUpdateNotification) {
      return false;
    }
    _progress.value = _scrollFraction;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 1200), _persistPosition);

    final metrics = notification.metrics;
    final delta = notification.scrollDelta ?? 0;
    if (metrics.pixels <= 40 || metrics.extentAfter <= 40) {
      _chromeVisible.value = true;
    } else if (notification.dragDetails != null && delta.abs() > 4) {
      // Only user drags toggle the chrome, not programmatic jumps.
      _chromeVisible.value = delta < 0;
    }
    return false;
  }

  /// Save the position and the reading time since the last save.
  ///
  /// [endSession] also refreshes today's activity (used when leaving).
  void _persistPosition({bool endSession = false}) {
    if (!_scrollController.hasClients || _characterCount == 0) return;
    final fraction = _scrollFraction;
    final seconds = _sessionStopwatch.elapsed.inSeconds;
    // Keeps running (or stopped) as it was; only the lap restarts.
    _sessionStopwatch.reset();
    final controller = ref.read(readerControllerProvider);
    final save = endSession ? controller.endSession : controller.saveProgress;
    unawaited(
      save(
        widget.bookId,
        currentPosition: _offsetFromFraction(fraction).toString(),
        progressPercentage: fraction * 100,
        readingTimeSeconds: seconds,
      ),
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
                  'Daily goal reached · $streak-day streak. Keep going!',
                ),
              ),
            ],
          ),
        ),
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
    _chromeVisible.value = true;
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
      isScrollControlled: true,
      builder: (_) => BookmarksSheet(
        bookId: widget.bookId,
        bookText: _text,
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
      isScrollControlled: true,
      builder: (_) => ExplanationSheet(args: args),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contentState = ref.watch(bookContentProvider(widget.bookId));
    final settings = ref.watch(readerSettingsProvider);
    final palette = ReaderPalette.resolve(
      settings.pageTone,
      Theme.of(context).brightness,
    );
    final content = contentState.value;
    final readable =
        content != null &&
        content.format == ContentFormat.text &&
        content.text != null;

    return Scaffold(
      backgroundColor: palette.page,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        color: palette.page,
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: switch (contentState) {
                  AsyncData(:final value) => _buildContent(
                    context,
                    value,
                    settings,
                    palette,
                  ),
                  AsyncError() => _ReaderError(
                    key: const ValueKey('reader-error'),
                    onRetry: () =>
                        ref.invalidate(bookContentProvider(widget.bookId)),
                  ),
                  _ => const Center(
                    key: ValueKey('reader-loading'),
                    child: CircularProgressIndicator(),
                  ),
                },
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TopBar(
                visible: _chromeVisible,
                palette: palette,
                onBookmark: readable ? _addBookmark : null,
                onBookmarks: _openBookmarks,
                onSettings: _openSettings,
              ),
            ),
            if (readable)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _BottomBar(
                  visible: _chromeVisible,
                  progress: _progress,
                  palette: palette,
                  characterCount: content.characterCount,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    BookContent content,
    ReaderSettings settings,
    ReaderPalette palette,
  ) {
    final l10n = AppLocalizations.of(context);
    if (content.format != ContentFormat.text || content.text == null) {
      return StateMessage(
        key: const ValueKey('unsupported-reader'),
        icon: Icons.picture_as_pdf_outlined,
        title: l10n.readerUnsupportedFormat,
        message:
            'Text files are fully supported today. PDF reading is coming next.',
      );
    }

    _characterCount = content.characterCount;
    _text = content.text;
    final resume = ref.watch(readingProgressProvider(widget.bookId)).value;
    if (resume != null) _restorePosition(resume.progressPercentage);

    final width = MediaQuery.sizeOf(context).width;
    final gutter = width > 620 ? 40.0 : 24.0;
    final insets = MediaQuery.paddingOf(context);
    final serif = settings.typeface == ReaderTypeface.serif;

    return NotificationListener<ScrollNotification>(
      key: const ValueKey('text-reader'),
      onNotification: _handleScroll,
      child: Scrollbar(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(
            gutter,
            insets.top + 76,
            gutter,
            insets.bottom + 120,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ReaderHeading(
                    title: content.title,
                    minutes: math.max(
                      1,
                      (content.characterCount / _charsPerMinute).ceil(),
                    ),
                    palette: palette,
                  ),
                  if (_showTip)
                    _ExplainTip(
                      palette: palette,
                      onDismiss: () => setState(() => _showTip = false),
                    ),
                  ExplainableText(
                    text: content.text!,
                    explainLabel: l10n.explain,
                    style: TextStyle(
                      fontFamily: serif ? AppFonts.serif : null,
                      fontSize: settings.fontSize,
                      height: settings.lineHeight,
                      letterSpacing: serif ? 0.1 : 0.05,
                      color: palette.ink,
                    ),
                    onExplain: _explainSelection,
                  ),
                  _EndMark(palette: palette),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.visible,
    required this.palette,
    required this.onBookmark,
    required this.onBookmarks,
    required this.onSettings,
  });

  final ValueListenable<bool> visible;
  final ReaderPalette palette;
  final VoidCallback? onBookmark;
  final VoidCallback onBookmarks;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canPop = Navigator.of(context).canPop();
    return ValueListenableBuilder<bool>(
      valueListenable: visible,
      builder: (context, shown, child) => IgnorePointer(
        ignoring: !shown,
        child: AnimatedSlide(
          offset: shown ? Offset.zero : const Offset(0, -1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: shown ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: child,
          ),
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0, 0.7, 1],
            colors: [
              palette.page,
              palette.page,
              palette.page.withValues(alpha: 0),
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 16),
            child: Row(
              children: [
                if (canPop) BackButton(color: palette.ink),
                const Spacer(),
                IconButton(
                  tooltip: l10n.bookmarkThisPosition,
                  color: palette.ink,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  onPressed: onBookmark,
                ),
                IconButton(
                  tooltip: l10n.bookmarks,
                  color: palette.ink,
                  icon: const Icon(Icons.bookmarks_outlined),
                  onPressed: onBookmarks,
                ),
                IconButton(
                  tooltip: l10n.readerSettings,
                  color: palette.ink,
                  icon: const Icon(Icons.text_fields_rounded),
                  onPressed: onSettings,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.visible,
    required this.progress,
    required this.palette,
    required this.characterCount,
  });

  final ValueListenable<bool> visible;
  final ValueListenable<double> progress;
  final ReaderPalette palette;
  final int characterCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.tertiary;
    final caption = theme.textTheme.labelMedium?.copyWith(color: palette.muted);

    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, value, _) {
        final minutesLeft = ((1 - value) * characterCount / _charsPerMinute)
            .ceil();
        final remaining = value >= 0.995
            ? 'Finished'
            : minutesLeft <= 1
            ? 'Under a minute left'
            : '${_duration(minutesLeft)} left';

        return ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (context, shown, _) => Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // A hairline of progress stays while the chrome is hidden.
              _ProgressTrack(
                value: value,
                height: 2,
                color: accent,
                track: Colors.transparent,
              ),
              IgnorePointer(
                ignoring: !shown,
                child: AnimatedSlide(
                  offset: shown ? Offset.zero : const Offset(0, 1),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        stops: const [0, 0.7, 1],
                        colors: [
                          palette.page,
                          palette.page,
                          palette.page.withValues(alpha: 0),
                        ],
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 680),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '${(value * 100).round()}%',
                                      style: caption,
                                    ),
                                    const Spacer(),
                                    Text(remaining, style: caption),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                _ProgressTrack(
                                  value: value,
                                  height: 4,
                                  color: accent,
                                  track: palette.hairline,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({
    required this.value,
    required this.height,
    required this.color,
    required this.track,
  });

  final double value;
  final double height;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: track)),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              heightFactor: 1,
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderHeading extends StatelessWidget {
  const _ReaderHeading({
    required this.title,
    required this.minutes,
    required this.palette,
  });

  final String title;
  final int minutes;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        children: [
          Text(
            '${_duration(minutes)} read'.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: palette.muted,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.serif,
              fontSize: 30,
              fontWeight: FontWeight.w600,
              height: 1.2,
              letterSpacing: -0.5,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 18),
          _Ornament(palette: palette),
        ],
      ),
    );
  }
}

class _Ornament extends StatelessWidget {
  const _Ornament({required this.palette});

  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    Widget rule() => Container(width: 32, height: 1, color: palette.hairline);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        rule(),
        const SizedBox(width: 10),
        Icon(Icons.auto_awesome, size: 12, color: palette.muted),
        const SizedBox(width: 10),
        rule(),
      ],
    );
  }
}

class _ExplainTip extends StatelessWidget {
  const _ExplainTip({required this.palette, required this.onDismiss});

  final ReaderPalette palette;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.tertiary;
    final style = theme.textTheme.bodyMedium?.copyWith(color: palette.ink);
    return Container(
      margin: const EdgeInsets.only(bottom: 28),
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_rounded, size: 18, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: style,
                children: [
                  const TextSpan(
                    text:
                        'Long-press a word or drag across a passage, then tap ',
                  ),
                  TextSpan(
                    text: 'Explain',
                    style: style?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss tip',
            color: palette.muted,
            iconSize: 18,
            icon: const Icon(Icons.close_rounded),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _EndMark extends StatelessWidget {
  const _EndMark({required this.palette});

  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 56),
      child: Column(
        children: [
          _Ornament(palette: palette),
          const SizedBox(height: 12),
          Text(
            'END',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: palette.muted,
              letterSpacing: 2.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderError extends StatelessWidget {
  const _ReaderError({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StateMessage(
      icon: Icons.cloud_off_rounded,
      title: "Couldn't open this book.",
      message: 'Check your connection and try again.',
      action: OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(l10n.retry),
      ),
    );
  }
}

/// Human-friendly duration, e.g. `12 min` or `2 hr 5 min`.
String _duration(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours hr' : '$hours hr $rest min';
}
