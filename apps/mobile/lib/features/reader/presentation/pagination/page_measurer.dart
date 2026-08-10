import 'package:flutter/material.dart';

import '../../domain/pagination_source.dart';
import 'document_page.dart';

/// Measures a single page without ever laying out more than roughly one
/// viewport of text.
///
/// This is the primitive that keeps pagination **O(page)** rather than
/// **O(document)**. The previous implementation measured the entire remaining
/// book in a [TextPainter] to size each page, which froze the UI thread on
/// large documents. Here, an exponential probe finds an overflow bound close to
/// the real page size, then a binary search settles the exact fit — so the
/// largest string ever measured is about twice a page, regardless of book size.
class PageMeasurer {
  const PageMeasurer({this.seedCapacity = 1400});

  /// Initial character-count guess for a page. Only affects how many probe
  /// measurements a page needs; correctness does not depend on it.
  final int seedCapacity;

  /// Measures the page beginning at canonical scalar offset [start].
  ///
  /// Returns `null` when [start] is at or beyond the end of [source].
  DocumentPage? measureForward({
    required PaginationSource source,
    required int start,
    required TextStyle style,
    required Size pageSize,
    required TextDirection textDirection,
    TextScaler textScaler = TextScaler.noScaling,
    Locale? locale,
  }) {
    final total = source.length;
    if (start >= total) return null;

    // No usable viewport yet: emit one logical page so callers still have valid
    // anchors. Nothing is measured, so this can never block.
    if (pageSize.width <= 0 || pageSize.height <= 0) {
      return DocumentPage(
        text: source.scalarSubstring(start, total),
        startOffset: start,
        endOffset: total,
      );
    }

    final maxLen = total - start;

    bool fitsLength(int length) => _fits(
      source.scalarSubstring(start, start + length),
      style: style,
      pageSize: pageSize,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
    );

    // Exponential probe: grow from the seed until the slice overflows (or the
    // remainder fits entirely). The largest slice measured is ~2x a page.
    var hi = seedCapacity.clamp(1, maxLen);
    while (hi < maxLen && fitsLength(hi)) {
      final next = hi * 2;
      hi = next >= maxLen ? maxLen : next;
    }
    if (hi >= maxLen && fitsLength(maxLen)) {
      // The whole remainder fits on this page (small tail or small book).
      return DocumentPage(
        text: source.scalarSubstring(start, total),
        startOffset: start,
        endOffset: total,
      );
    }

    // Binary search the largest fitting length within the bounded probe window.
    var low = 1;
    var high = hi;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (fitsLength(mid)) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }

    final rawEnd = (start + low).clamp(start + 1, total);
    final end = rawEnd == total
        ? rawEnd
        : _preferReadableBoundary(source, start, rawEnd);
    return DocumentPage(
      text: source.scalarSubstring(start, end),
      startOffset: start,
      endOffset: end,
    );
  }

  bool _fits(
    String text, {
    required TextStyle style,
    required Size pageSize,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required Locale? locale,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
    )..layout(maxWidth: pageSize.width);
    final fits = painter.height <= pageSize.height + 0.01;
    painter.dispose();
    return fits;
  }

  /// Prefers a whitespace boundary near the end of a measured page so words are
  /// not split mid-line. Searches only the last ~28% of the page.
  int _preferReadableBoundary(
    PaginationSource source,
    int start,
    int measuredEnd,
  ) {
    final searchStart = start + ((measuredEnd - start) * 0.72).floor();
    for (var index = measuredEnd; index > searchStart; index--) {
      final character = source.scalarAt(index - 1);
      if (character == '\n' || character == ' ' || character == '\t') {
        return index;
      }
    }
    return measuredEnd;
  }
}
