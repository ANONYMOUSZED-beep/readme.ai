import 'package:flutter/foundation.dart';

import 'reader_element.dart';

/// A bounded window of document elements around a reading position.
///
/// Windows are how the Reader consumes a book without ever holding all of it: a
/// 900-page reference book has tens of thousands of elements, and only the ones
/// covering the current reading window are ever materialised.
@immutable
class ElementWindow {
  const ElementWindow({
    required this.start,
    required this.end,
    required this.characterCount,
    required this.elements,
    this.truncated = false,
    this.skipped = 0,
  });

  const ElementWindow.empty({this.start = 0, this.end = 0})
    : characterCount = 0,
      elements = const [],
      truncated = false,
      skipped = 0;

  /// Canonical start offset of the window the server served.
  final int start;

  /// Canonical end offset of the window the server served, after clamping.
  final int end;

  /// Total canonical characters in the whole document, not just this window.
  final int characterCount;

  /// Elements in document order.
  final List<ReaderElement> elements;

  /// Whether the server's element cap stopped this window short.
  final bool truncated;

  /// Elements the client could not decode and skipped.
  ///
  /// Partial success is deliberate: one malformed element must never cost the
  /// reader a whole page of text.
  final int skipped;

  bool get isEmpty => elements.isEmpty;

  bool get isNotEmpty => elements.isNotEmpty;

  /// Whether anything was dropped, by the server or by the client.
  bool get isComplete => !truncated && skipped == 0;

  @override
  bool operator ==(Object other) =>
      other is ElementWindow &&
      other.start == start &&
      other.end == end &&
      other.characterCount == characterCount &&
      other.truncated == truncated &&
      other.skipped == skipped &&
      listEquals(other.elements, elements);

  @override
  int get hashCode => Object.hash(
    start,
    end,
    characterCount,
    truncated,
    skipped,
    Object.hashAll(elements),
  );

  @override
  String toString() =>
      'ElementWindow($start, $end, elements: ${elements.length}, '
      'truncated: $truncated, skipped: $skipped)';
}
