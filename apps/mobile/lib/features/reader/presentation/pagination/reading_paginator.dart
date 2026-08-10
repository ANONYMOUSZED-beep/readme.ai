import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/pagination_source.dart';
import 'document_page.dart';
import 'page_measurer.dart';

/// Identifies a pagination layout. Any change (font size, line height, viewport
/// size, text scaler, direction, locale) produces a new key, which the Reader
/// uses to decide when a fresh [ReadingPaginator] is required. Pages measured
/// for one key are never reused for another, and identical keys reuse the cache
/// — so repeated rebuilds never re-paginate.
@immutable
class PaginationKey {
  const PaginationKey({
    required this.fontSize,
    required this.lineHeight,
    required this.width,
    required this.height,
    required this.textScalerDescription,
    required this.textDirection,
    required this.locale,
  });

  final double fontSize;
  final double lineHeight;
  final double width;
  final double height;
  final String textScalerDescription;
  final TextDirection textDirection;
  final Locale? locale;

  @override
  bool operator ==(Object other) =>
      other is PaginationKey &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.width == width &&
      other.height == height &&
      other.textScalerDescription == textScalerDescription &&
      other.textDirection == textDirection &&
      other.locale == locale;

  @override
  int get hashCode => Object.hash(
    fontSize,
    lineHeight,
    width,
    height,
    textScalerDescription,
    textDirection,
    locale,
  );
}

/// Incrementally paginates a document into a **reading window**.
///
/// Design goals (Sprint 6.1):
/// * Pagination never runs inside widget `build()` — callers invoke
///   [ensureOffset]/[ensureIndex] and read the cache; measurement happens in an
///   asynchronous, chunked loop.
/// * The whole document is never paginated up front. Only the pages needed to
///   reach the requested offset/index (plus a small look-ahead the caller
///   requests) are measured.
/// * Results are cached; repeated requests are O(1) once measured.
/// * Each page is measured with the bounded [PageMeasurer], so per-page cost is
///   independent of document size.
///
/// Because [TextPainter] must run on the UI isolate, the heavy work cannot move
/// to a background isolate; instead the loop measures in small chunks and
/// yields to the event loop between them, so frames render and the UI never
/// freezes.
class ReadingPaginator extends ChangeNotifier {
  ReadingPaginator({
    required this.source,
    required this.style,
    required this.pageSize,
    required this.textDirection,
    this.textScaler = TextScaler.noScaling,
    this.locale,
    this.measurer = const PageMeasurer(),
    this.chunkSize = 6,
  });

  final PaginationSource source;
  final TextStyle style;
  final Size pageSize;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Locale? locale;
  final PageMeasurer measurer;

  /// Pages measured per event-loop turn before yielding. Keeps each turn short
  /// so the UI stays responsive while catching up to a deep resume position.
  final int chunkSize;

  final List<DocumentPage> _pages = <DocumentPage>[];
  bool _complete = false;
  bool _disposed = false;

  int _goalIndex = -1;
  int _goalOffset = -1;
  Future<void>? _loop;

  // A cancelable "yield to the event loop" between chunks. Storing the timer
  // and its completer lets [dispose] cancel pending work immediately, so no
  // timer or future outlives the paginator (important for a closed reader and
  // for test isolation).
  Timer? _yieldTimer;
  Completer<void>? _yieldCompleter;

  Future<void> _yieldToEventLoop() {
    _yieldTimer?.cancel();
    final completer = _yieldCompleter = Completer<void>();
    _yieldTimer = Timer(Duration.zero, () {
      _yieldTimer = null;
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  /// Number of pages measured so far (grows as the reader advances).
  int get pageCount => _pages.length;

  /// Whether the entire document has been paginated.
  bool get isComplete => _complete;

  /// Whether at least the first page is ready to render.
  bool get hasFirstPage => _pages.isNotEmpty;

  DocumentPage pageAt(int index) => _pages[index];

  DocumentPage? pageOrNull(int index) =>
      index >= 0 && index < _pages.length ? _pages[index] : null;

  int get _nextStart => _pages.isEmpty ? 0 : _pages.last.endOffset;

  /// Display-only estimate of the total page count. Exact once [isComplete];
  /// before that it extrapolates from the average page length measured so far.
  int get estimatedTotalPages {
    if (_complete) return _pages.isEmpty ? 0 : _pages.length;
    if (_pages.isEmpty) return 0;
    final measuredChars = _pages.last.endOffset;
    if (measuredChars <= 0) return _pages.length;
    final average = measuredChars / _pages.length;
    final estimate = (source.length / average).ceil();
    return estimate < _pages.length ? _pages.length : estimate;
  }

  /// Index of the measured page containing [offset], clamped to what is known.
  int indexForOffset(int offset) {
    if (_pages.isEmpty) return 0;
    for (var index = 0; index < _pages.length; index++) {
      if (_pages[index].contains(offset)) return index;
    }
    if (offset >= _pages.last.endOffset) return _pages.length - 1;
    return 0;
  }

  /// Ensures pages are measured through [index] (or the document ends).
  Future<void> ensureIndex(int index) => _ensure(index: index);

  /// Ensures the page containing [scalarOffset] is measured; returns its index.
  Future<int> ensureOffset(int scalarOffset) async {
    await _ensure(offset: scalarOffset);
    return indexForOffset(scalarOffset);
  }

  Future<void> _ensure({int? index, int? offset}) {
    if (index != null && index > _goalIndex) _goalIndex = index;
    if (offset != null && offset > _goalOffset) _goalOffset = offset;
    return _loop ??= _startLoop();
  }

  Future<void> _startLoop() async {
    try {
      await _measureLoop();
    } finally {
      _loop = null;
    }
    // If a new goal arrived just as the loop finished, keep going.
    if (!_disposed && !_goalReached) return _ensure();
  }

  bool get _goalReached {
    if (_complete) return true;
    final indexReached = _goalIndex < 0 || _pages.length > _goalIndex;
    final offsetReached =
        _goalOffset < 0 ||
        (_pages.isNotEmpty && _pages.last.endOffset > _goalOffset);
    return indexReached && offsetReached;
  }

  Future<void> _measureLoop() async {
    while (!_disposed && !_complete && !_goalReached) {
      var measured = 0;
      while (measured < chunkSize && !_complete && !_goalReached) {
        final start = _nextStart;
        final page = measurer.measureForward(
          source: source,
          start: start,
          style: style,
          pageSize: pageSize,
          textDirection: textDirection,
          textScaler: textScaler,
          locale: locale,
        );
        if (page == null || page.endOffset <= start) {
          _complete = true;
          break;
        }
        _pages.add(page);
        if (page.endOffset >= source.length) _complete = true;
        measured++;
      }
      if (_disposed) return;
      notifyListeners();
      // Yield so a frame can render between chunks — the UI never freezes.
      await _yieldToEventLoop();
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    // Cancel any pending inter-chunk yield so no timer or awaiting future
    // survives disposal.
    _yieldTimer?.cancel();
    _yieldTimer = null;
    final pending = _yieldCompleter;
    if (pending != null && !pending.isCompleted) pending.complete();
    super.dispose();
  }
}
