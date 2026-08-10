import '../../domain/document_outline.dart';
import '../../domain/reader_element.dart';
import '../../domain/reader_span.dart';
import '../pagination/document_page.dart';
import 'render_block.dart';

/// Turns a measured page plus document structure into an ordered block list.
///
/// The composer **consumes** page boundaries; it never computes them. Pagination
/// is decided entirely by `PageMeasurer` over canonical text, so composition
/// cannot move a page break, change a page count, or shift an anchor.
///
/// Its contract is coverage without duplication: the blocks it returns cover the
/// page's canonical range exactly once, in reading order, and every block's text
/// is the canonical text of its own span. Characters no element claims still
/// reach the page as plain text, so structure can be incomplete — or absent —
/// without losing a word.
///
/// Output is a pure render model: immutable [RenderBlock] values only.
class PageComposer {
  PageComposer({this.bulletDepthLimit = 8});

  /// Guard for the parent-chain walks used by nesting depth.
  final int bulletDepthLimit;

  final CompositionDiagnostics _diagnostics = CompositionDiagnostics();

  /// Composition counters, for measurement only.
  CompositionDiagnostics get diagnostics => _diagnostics;

  /// Compose using structure already resident in [outline].
  List<RenderBlock> composeFrom(DocumentPage page, DocumentOutline outline) =>
      compose(page: page, elements: outline.elementsIn(page.startOffset, page.endOffset));

  /// Compose [page] from the [elements] intersecting it.
  ///
  /// [elements] may arrive in any order and may include elements that reach
  /// beyond the page; both are handled. Passing an empty list yields a single
  /// plain-text block for the page, which is the graceful-degradation path.
  List<RenderBlock> compose({
    required DocumentPage page,
    required List<ReaderElement> elements,
  }) {
    final watch = Stopwatch()..start();
    final blocks = _compose(page, elements);
    watch.stop();

    _diagnostics.compositions++;
    _diagnostics.compositionMicroseconds += watch.elapsedMicroseconds;
    _diagnostics.composedBlocks += blocks.length;
    _diagnostics.clippedBlocks += blocks.where((block) => block.clipped).length;
    return blocks;
  }

  List<RenderBlock> _compose(DocumentPage page, List<ReaderElement> elements) {
    final pageSpan = ReaderSpan(page.startOffset, page.endOffset);
    if (pageSpan.isEmpty) return const [];

    final ordered = [...elements]
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    final byId = {for (final element in ordered) element.id: element};
    final headings = ordered
        .where(
          (element) =>
              (element.kind == ReaderElementKind.chapter ||
                  element.kind == ReaderElementKind.section) &&
              _titleOf(element) != null,
        )
        .toList();

    // Decoded once per page, not once per block: slicing by canonical offset
    // must stay O(block) rather than O(page) per call.
    final runes = page.text.runes.toList(growable: false);
    String slice(ReaderSpan span) {
      final safeStart = (span.start - page.startOffset).clamp(0, runes.length);
      final safeEnd = (span.end - page.startOffset).clamp(safeStart, runes.length);
      return String.fromCharCodes(runes.sublist(safeStart, safeEnd));
    }

    final keyed = <(double, RenderBlock)>[];
    // Single forward pass: the cursor is the first canonical offset on this page
    // not yet claimed, which is what makes coverage exact and duplication
    // impossible regardless of how elements overlap.
    var cursor = pageSpan.start;
    var lastKey = -1.0;

    void addGap(int start, int end, double key) {
      if (end <= start) return;
      // A gap can span several blank-line separated runs — a chapter heading and
      // a section heading, for instance. Split them so each run can be
      // recognised for what it is instead of collapsing into one block.
      for (final segment in _segments(start, end, runes, page.startOffset)) {
        final text = slice(segment);
        final heading = _headingFor(headings, segment, text);
        keyed.add((
          heading == null ? key : heading.sequence.toDouble(),
          RenderBlock(
            kind: heading?.kind ?? ReaderElementKind.unknown,
            visibleSpan: segment,
            text: text,
            element: heading,
            title: heading == null ? null : _titleOf(heading),
          ),
        ));
      }
    }

    for (var index = 0; index < ordered.length; index++) {
      final element = ordered[index];
      if (_isPlaceholder(element)) {
        if (!_placeholderBelongsToPage(ordered, index, pageSpan)) {
          _diagnostics.suppressedBlocks++;
          continue;
        }
        keyed.add((
          element.sequence.toDouble(),
          RenderBlock(
            kind: element.kind,
            // Placeholders occupy no canonical characters, so they can never
            // duplicate or displace text.
            visibleSpan: ReaderSpan.empty(cursor),
            text: '',
            element: element,
            caption: _captionTextFor(element, ordered, byId, slice),
          ),
        ));
        lastKey = element.sequence.toDouble();
        continue;
      }

      if (!element.isReadable) {
        // Structural containers carry no text of their own; their titles surface
        // through gap attribution below.
        _diagnostics.suppressedBlocks++;
        continue;
      }

      final span = element.span;
      final visible = span?.intersect(pageSpan);
      if (visible == null) {
        _diagnostics.suppressedBlocks++;
        continue;
      }

      final start = visible.start > cursor ? visible.start : cursor;
      if (visible.end <= start) {
        // Entirely claimed by an earlier element: emitting it would duplicate
        // characters.
        _diagnostics.suppressedBlocks++;
        continue;
      }

      addGap(cursor, start, lastKey + 0.5);

      final blockSpan = ReaderSpan(start, visible.end);
      final key = element.sequence.toDouble();
      keyed.add((
        key,
        RenderBlock(
          kind: element.kind,
          visibleSpan: blockSpan,
          text: slice(blockSpan),
          element: element,
          depth: _depthOf(element, byId),
          marker: _markerOf(element, byId),
          markerNumber: _markerNumberOf(element, byId),
          clipped: span != blockSpan,
        ),
      ));
      cursor = visible.end;
      lastKey = key;
    }

    addGap(cursor, pageSpan.end, lastKey + 0.5);

    // Stable sort by ordering key: reading order for text, sequence position for
    // placeholders.
    final indexed = [
      for (var index = 0; index < keyed.length; index++) (index, keyed[index]),
    ]..sort((a, b) {
      final byKey = a.$2.$1.compareTo(b.$2.$1);
      return byKey != 0 ? byKey : a.$1.compareTo(b.$1);
    });
    return List.unmodifiable(indexed.map((entry) => entry.$2.$2));
  }

  /// The caption text belonging to an image or table, if one is on this page.
  ///
  /// Association is resolved two ways, because parsers differ in which direction
  /// they record it: the image's own `captionId`, and any caption whose
  /// `describesId` points back at the element. Either link is sufficient, so a
  /// figure keeps its number even when only one side was recorded.
  String? _captionTextFor(
    ReaderElement element,
    List<ReaderElement> ordered,
    Map<String, ReaderElement> byId,
    String Function(ReaderSpan) slice,
  ) {
    CaptionElement? caption;

    if (element is ImageElement && element.captionId != null) {
      final candidate = byId[element.captionId];
      if (candidate is CaptionElement) caption = candidate;
    }
    caption ??= ordered.whereType<CaptionElement>().where((candidate) {
      return candidate.describesId == element.id ||
          candidate.parentId == element.id;
    }).firstOrNull;
    if (caption == null) return null;

    // Delivered text is authoritative; otherwise read the caption's own span.
    final delivered = caption.text;
    if (delivered != null && delivered.trim().isNotEmpty) {
      return delivered.trim();
    }
    final span = caption.span;
    if (span == null) return null;
    final text = slice(span).trim();
    return text.isEmpty ? null : text;
  }

  /// Splits a range at blank-line boundaries, keeping separators attached to the
  /// run they follow so coverage stays exact.
  List<ReaderSpan> _segments(
    int start,
    int end,
    List<int> runes,
    int pageStart,
  ) {
    const newline = 0x0A;
    final segments = <ReaderSpan>[];
    var segmentStart = start;
    var offset = start;

    while (offset < end) {
      final index = offset - pageStart;
      final isBreak =
          index >= 0 &&
          index + 1 < runes.length &&
          runes[index] == newline &&
          runes[index + 1] == newline;
      if (!isBreak) {
        offset++;
        continue;
      }
      // Consume the whole run of newlines into the current segment.
      var after = offset;
      while (after < end &&
          after - pageStart < runes.length &&
          runes[after - pageStart] == newline) {
        after++;
      }
      segments.add(ReaderSpan(segmentStart, after));
      segmentStart = after;
      offset = after;
    }
    if (segmentStart < end) segments.add(ReaderSpan(segmentStart, end));
    return segments;
  }

  /// Whether a span-less or container placeholder belongs to this page.
  ///
  /// An image carries no offsets, so its position is inferred from the nearest
  /// spanned elements around it in document order. Without this, an image
  /// anywhere in the document would appear on every page.
  bool _placeholderBelongsToPage(
    List<ReaderElement> ordered,
    int index,
    ReaderSpan pageSpan,
  ) {
    final span = ordered[index].span;
    if (span != null) return span.intersect(pageSpan) != null;

    for (var before = index - 1; before >= 0; before--) {
      final neighbour = ordered[before].span;
      if (neighbour == null) continue;
      return neighbour.intersect(pageSpan) != null ||
          _nextIntersects(ordered, index, pageSpan);
    }
    return _nextIntersects(ordered, index, pageSpan);
  }

  bool _nextIntersects(
    List<ReaderElement> ordered,
    int index,
    ReaderSpan pageSpan,
  ) {
    for (var after = index + 1; after < ordered.length; after++) {
      final neighbour = ordered[after].span;
      if (neighbour == null) continue;
      return neighbour.intersect(pageSpan) != null;
    }
    return false;
  }

  bool _isPlaceholder(ReaderElement element) =>
      element.kind == ReaderElementKind.image ||
      element.kind == ReaderElementKind.table;

  String? _titleOf(ReaderElement element) => switch (element) {
    ChapterElement(:final title) => title,
    SectionElement(:final title) => title,
    _ => null,
  };

  /// Attributes a run of unclaimed page text to a heading when it *is* that
  /// heading, which is how a heading printed into the reading flow renders as a
  /// heading instead of as body text.
  ReaderElement? _headingFor(
    List<ReaderElement> headings,
    ReaderSpan span,
    String text,
  ) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    for (final heading in headings) {
      if (_titleOf(heading)?.trim() != trimmed) continue;
      final headingSpan = heading.span;
      if (headingSpan != null && !headingSpan.contains(span.start)) continue;
      return heading;
    }
    return null;
  }

  int _depthOf(ReaderElement element, Map<String, ReaderElement> byId) {
    var depth = 0;
    var current = element;
    for (var step = 0; step < bulletDepthLimit; step++) {
      final parentId = current.parentId;
      if (parentId == null) break;
      final parent = byId[parentId];
      if (parent == null) break;
      if (parent.kind == ReaderElementKind.list) depth++;
      current = parent;
    }
    return depth;
  }

  ListElement? _listOf(ReaderElement element, Map<String, ReaderElement> byId) {
    if (element.kind != ReaderElementKind.listItem) return null;
    final parentId = element.parentId;
    if (parentId == null) return null;
    final parent = byId[parentId];
    return parent is ListElement ? parent : null;
  }

  BlockMarker _markerOf(ReaderElement element, Map<String, ReaderElement> byId) {
    if (element.kind != ReaderElementKind.listItem) return BlockMarker.none;
    final list = _listOf(element, byId);
    // An orphaned item still gets a bullet rather than losing its marker.
    if (list == null) return BlockMarker.bullet;
    return list.ordered ? BlockMarker.number : BlockMarker.bullet;
  }

  int? _markerNumberOf(ReaderElement element, Map<String, ReaderElement> byId) {
    final list = _listOf(element, byId);
    if (list == null || !list.ordered) return null;
    return (list.startNumber ?? 1) + element.orderIndex;
  }
}
