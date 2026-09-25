import 'package:flutter/foundation.dart';

import '../../domain/reader_element.dart';
import '../../domain/reader_span.dart';

/// How a block's list marker should be presented, if at all.
enum BlockMarker { none, bullet, number }

/// One renderable unit of a page: a pure data description, never a widget.
///
/// A block says *what* to draw and *which canonical characters* it covers. It
/// holds no `Widget`, no `TextPainter`, no layout object and no `BuildContext`,
/// so composition can be tested and compared without a render tree — which is
/// what makes rendering determinism assertable.
///
/// [visibleSpan] is always clipped to the page being composed, and [text] is
/// always exactly the canonical text of that span. Together they guarantee that
/// what is rendered is a faithful, non-duplicating slice of the document.
@immutable
class RenderBlock {
  const RenderBlock({
    required this.kind,
    required this.visibleSpan,
    required this.text,
    this.element,
    this.title,
    this.caption,
    this.depth = 0,
    this.marker = BlockMarker.none,
    this.markerNumber,
    this.clipped = false,
  });

  /// What this block represents. Drives renderer dispatch in the next wave.
  final ReaderElementKind kind;

  /// The canonical range this block covers on this page, already clipped.
  final ReaderSpan visibleSpan;

  /// The canonical text of [visibleSpan]. Empty for placeholders.
  final String text;

  /// The source element, or `null` for text on the page that no element claims.
  final ReaderElement? element;

  /// Heading title, for chapter and section blocks.
  final String? title;

  /// The associated caption's text, for image and table placeholders.
  ///
  /// Supplied so a placeholder can name itself ("Figure 5") and describe itself
  /// to assistive technology. The caption still renders as its own block
  /// immediately below, so this is never drawn twice.
  final String? caption;

  /// List nesting depth: 0 outside a list, 1 for a top-level item.
  final int depth;

  final BlockMarker marker;

  /// The number to show for an ordered list item.
  final int? markerNumber;

  /// Whether the source element extended beyond this page and was cut.
  final bool clipped;

  /// Whether this block contributes characters to the page's reading flow.
  bool get carriesText => text.isNotEmpty;

  /// Whether this block stands in for content rendered richly in a later sprint.
  bool get isPlaceholder =>
      kind == ReaderElementKind.image || kind == ReaderElementKind.table;

  @override
  bool operator ==(Object other) =>
      other is RenderBlock &&
      other.kind == kind &&
      other.visibleSpan == visibleSpan &&
      other.text == text &&
      other.element == element &&
      other.title == title &&
      other.caption == caption &&
      other.depth == depth &&
      other.marker == marker &&
      other.markerNumber == markerNumber &&
      other.clipped == clipped;

  @override
  int get hashCode => Object.hash(
    kind,
    visibleSpan,
    text,
    element,
    title,
    caption,
    depth,
    marker,
    markerNumber,
    clipped,
  );

  @override
  String toString() =>
      'RenderBlock(${kind.name}, $visibleSpan, '
      '${text.length} chars${clipped ? ', clipped' : ''})';
}

/// Composition counters, for measurement only. Nothing branches on them.
class CompositionDiagnostics {
  int composedBlocks = 0;
  int clippedBlocks = 0;
  int suppressedBlocks = 0;
  int compositionMicroseconds = 0;
  int compositions = 0;

  double get averageCompositionMicroseconds =>
      compositions == 0 ? 0 : compositionMicroseconds / compositions;

  void reset() {
    composedBlocks = 0;
    clippedBlocks = 0;
    suppressedBlocks = 0;
    compositionMicroseconds = 0;
    compositions = 0;
  }

  @override
  String toString() =>
      'CompositionDiagnostics(composed: $composedBlocks, '
      'clipped: $clippedBlocks, suppressed: $suppressedBlocks, '
      'avgUs: ${averageCompositionMicroseconds.toStringAsFixed(1)})';
}
